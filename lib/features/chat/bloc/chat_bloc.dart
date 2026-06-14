import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/features/session/repositories/session_repository.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/constants/budget_allocation.dart';
import 'package:offline_chat/services/memory_store/memory_store_service.dart';
import 'package:offline_chat/services/memory_store/summary_service.dart';
import 'package:offline_chat/services/memory_store/memory_prompt_formatter.dart';
import 'package:offline_chat/services/rag/rag_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';

// ─── States ──────────────────────────────────────────────────────────────────

/// Extension property để ChatState có thể get knowledgeScope
extension ChatStateScopeX on ChatState {
  KnowledgeScope get knowledgeScope =>
      this is ChatScopeProvider ? (this as ChatScopeProvider).knowledgeScope : KnowledgeScope.attachedAndGlobal;
}

abstract class ChatScopeProvider {
  KnowledgeScope get knowledgeScope;
}

// Events
sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class SessionInitialized extends ChatEvent {
  final String sessionId;
  const SessionInitialized(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

class SendMessageRequested extends ChatEvent {
  final String content;
  const SendMessageRequested(this.content);

  @override
  List<Object?> get props => [content];
}

class StreamingCancelled extends ChatEvent {
  const StreamingCancelled();
}

class MessagesCleared extends ChatEvent {
  const MessagesCleared();
}

/// Được dispatch từ ChatPage khi ModelBloc báo gemmaReady = true.
/// Cho phép ChatBloc clear error "needsModelDownload" và chuyển về loaded.
class ModelBecameReady extends ChatEvent {
  const ModelBecameReady();
}

/// Chuyển đổi KnowledgeScope cho session hiện tại.
class KnowledgeScopeChanged extends ChatEvent {
  final KnowledgeScope scope;
  const KnowledgeScopeChanged(this.scope);

  @override
  List<Object?> get props => [scope];
}

// States
sealed class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {
  const ChatInitial();
}

class ChatLoading extends ChatState {
  const ChatLoading();
}

class ChatLoaded extends ChatState implements ChatScopeProvider {
  final List<MessageModel> messages;
  @override
  final KnowledgeScope knowledgeScope;
  const ChatLoaded(this.messages, {this.knowledgeScope = KnowledgeScope.attachedAndGlobal});

  @override
  List<Object?> get props => [messages, knowledgeScope];
}

class ChatThinking extends ChatState implements ChatScopeProvider {
  final List<MessageModel> messages;
  @override
  final KnowledgeScope knowledgeScope;
  const ChatThinking(this.messages, {this.knowledgeScope = KnowledgeScope.attachedAndGlobal});

  @override
  List<Object?> get props => [messages, knowledgeScope];
}

class ChatStreaming extends ChatState implements ChatScopeProvider {
  final List<MessageModel> messages;
  final String streamingText;
  final String streamingId;
  final List<SearchResult>? ragResults;
  @override
  final KnowledgeScope knowledgeScope;
  const ChatStreaming({
    required this.messages,
    required this.streamingText,
    required this.streamingId,
    this.ragResults,
    this.knowledgeScope = KnowledgeScope.attachedAndGlobal,
  });

  @override
  List<Object?> get props => [messages, streamingText, streamingId, ragResults, knowledgeScope];
}

class ChatError extends ChatState implements ChatScopeProvider {
  final String message;
  final bool needsModelDownload;
  final List<MessageModel> messages;
  @override
  final KnowledgeScope knowledgeScope;
  const ChatError({
    required this.message,
    this.needsModelDownload = false,
    this.messages = const [],
    this.knowledgeScope = KnowledgeScope.attachedAndGlobal,
  });

  @override
  List<Object?> get props => [message, needsModelDownload, messages, knowledgeScope];
}

// Bloc
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MessageRepository _messageRepo;
  final SessionRepository _sessionRepo;
  final GemmaService _gemmaService;
  final ModelBloc _modelBloc;
  final MemoryStoreService _memoryStore;
  final SummaryService _summaryService;
  final RagService _ragService;
  final PromptBuilder _promptBuilder;
  final Uuid _uuid = const Uuid();

  String? _currentSessionId;
  String _accumulatedText = '';
  List<MessageModel> _currentMessages = [];

  /// Subscribe vào modelBloc.stream để đợi gemmaReady.
  StreamSubscription<ModelState>? _modelSubscription;

  /// Nội dung message đang chờ gửi khi model init xong.
  String? _pendingMessage;

  /// true khi đang chờ model init (đã bỏ qua SendMessageRequested).
  bool _isWaitingForModel = false;

  /// Lock tránh chạy đồng thời 2 summarize jobs.
  bool _isSummarizing = false;

  /// Budget config (tính theo context window runtime).
  late final MemoryBudgetConfig _memoryBudget;

  /// KnowledgeScope hiện tại của session (hydrate từ DB khi init).
  KnowledgeScope _currentScope = KnowledgeScope.attachedAndGlobal;

  ChatBloc({
    required MessageRepository messageRepo,
    required SessionRepository sessionRepo,
    required GemmaService gemmaService,
    required ModelBloc modelBloc,
    required MemoryStoreService memoryStore,
    required SummaryService summaryService,
    required RagService ragService,
    required PromptBuilder promptBuilder,
    int? contextWindow,
  })  : _messageRepo = messageRepo,
        _sessionRepo = sessionRepo,
        _gemmaService = gemmaService,
        _modelBloc = modelBloc,
        _memoryStore = memoryStore,
        _summaryService = summaryService,
        _ragService = ragService,
        _promptBuilder = promptBuilder,
        _memoryBudget = MemoryBudgetConfig(contextWindow: contextWindow),
        super(const ChatInitial()) {
    on<SessionInitialized>(_onSessionInitialized);
    on<SendMessageRequested>(_onSendMessageRequested);
    on<StreamingCancelled>(_onStreamingCancelled);
    on<MessagesCleared>(_onMessagesCleared);
    on<ModelBecameReady>(_onModelBecameReady);
    on<KnowledgeScopeChanged>(_onKnowledgeScopeChanged);
  }

  Future<void> _onSessionInitialized(
    SessionInitialized event,
    Emitter<ChatState> emit,
  ) async {
    if (isClosed) return;
    _currentSessionId = event.sessionId;
    emit(const ChatLoading());
    try {
      final messages = await _messageRepo.getMessages(event.sessionId);
      _currentMessages = messages;

      // Hydrate KnowledgeScope từ DB
      final sessionInfo = await _sessionRepo.getSessionById(event.sessionId);
      _currentScope = sessionInfo?.knowledgeScope ?? KnowledgeScope.attachedAndGlobal;

      // Kiểm tra xem có SessionMemory (summary) không
      final memoryRow = await _memoryStore.getSessionMemory(event.sessionId);

      if (!_gemmaService.isReady) {
        log_util.log.w('⚠️ [Session] Gemma chưa ready — skip session creation, load messages only');
        emit(ChatLoaded(messages, knowledgeScope: _currentScope));
        return;
      }

      // ─── FIX: Đúng kiến trúc Session API ─────────────────────────────
      // 1. Build system instruction (KHÔNG chứa history)
      final userMemories = await _memoryStore.getAllUserMemories();
      final userMemoryList = <({String nspace, String key, String value})>[];
      for (final m in userMemories) {
        userMemoryList.add((nspace: m.namespace, key: m.key, value: m.value));
      }

      final String systemInstruction;
      if (memoryRow?.summary != null && memoryRow!.summary!.isNotEmpty) {
        // Có summary → dùng MemoryPromptFormatter
        systemInstruction = MemoryPromptFormatter.build(
          summary: memoryRow.summary,
          userMemories: userMemoryList,
        );
        log_util.log.i('🧠 [Session] Using summary (v${memoryRow.summaryVersion}, ~${memoryRow.estTokens}tok)');
      } else {
        // Không có summary → dùng PromptBuilder.buildSystemInstruction
        final userMemoryObjects = userMemories
            .map((m) => UserMemory(namespace: m.namespace, key: m.key, value: m.value))
            .toList();
        systemInstruction = await _promptBuilder.buildSystemInstruction(
          userMemories: userMemoryObjects,
        );
        log_util.log.i('🧠 [Session] Using default system instruction');
      }

      // 2. Tạo session với system instruction
      await _gemmaService.createSession(systemInstruction: systemInstruction);
      log_util.log.i('🆕 [Session] Gemma session created with system instruction');

      // 3. Replay history MỘT LẦN DUY NHẤT (token-budget)
      // Session init dùng kSessionInitHistoryRatio (35%) — KHÔNG dùng dynamic budget
      final historyBudget = (kGemmaMaxTokens * kSessionInitHistoryRatio).round();
      final historyMessages = <MessageModel>[];
      var historyTokenSum = 0;

      for (int i = messages.length - 1; i >= 0; i--) {
        final msgToken = estimateMessageTokens(messages[i].content);
        if (historyTokenSum + msgToken > historyBudget) break;
        historyTokenSum += msgToken;
        historyMessages.insert(0, messages[i]);
      }

      for (final msg in historyMessages) {
        await _gemmaService.addHistoryMessage(msg.role.name, msg.content);
      }
      log_util.log.i(
          '🔄 [Session] Replayed ${historyMessages.length}/${messages.length} messages (~${historyTokenSum}tok budget=${historyBudget}tok)');

      emit(ChatLoaded(messages, knowledgeScope: _currentScope));
    } catch (e) {
      log_util.log.e('⛔ [Session] Error: $e');
      emit(ChatError(
        message: e.toString(),
        knowledgeScope: _currentScope,
      ));
    }
  }

  Future<void> _onSendMessageRequested(
    SendMessageRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (isClosed) return;
    if (_currentSessionId == null) return;

    // Block send nếu đang streaming
    if (state is ChatStreaming) return;

    // Block send nếu đang chờ model init
    if (_isWaitingForModel) return;

    // ─── Kiểm tra Gemma sẵn sàng ──────────────────────────────────────────
    if (!_gemmaService.isReady) {
      final modelState = _modelBloc.state;

      if (modelState is ModelLoaded) {
        // Kiểm tra active model đã download chưa
        final activeModel = modelState.llmModels.firstWhere(
          (m) => m.fileName == modelState.activeLlmFileName,
          orElse: () => modelState.llmModels.first,
        );
        final isDownloaded = activeModel.status == ModelStatus.downloaded;

        if (isDownloaded && !modelState.gemmaReady) {
          _pendingMessage = event.content;
          _isWaitingForModel = true;

          _modelSubscription?.cancel();
          _modelSubscription = _modelBloc.stream.listen((newState) {
            if (newState is ModelLoaded && newState.gemmaReady && _pendingMessage != null) {
              final pending = _pendingMessage;
              _pendingMessage = null;
              _isWaitingForModel = false;
              _modelSubscription?.cancel();
              _modelSubscription = null;
              Future.microtask(() => add(SendMessageRequested(pending!)));
            }
          });

          final currentModelState = _modelBloc.state;
          if (currentModelState is ModelLoaded && currentModelState.gemmaReady) {
            _isWaitingForModel = false;
            _pendingMessage = null;
            _modelSubscription?.cancel();
            _modelSubscription = null;
          } else {
            emit(const ChatLoading());
            return;
          }
        }

        if (!isDownloaded) {
          emit(ChatError(
            message: 'Model AI chưa được tải. Vui lòng tải model trước.',
            needsModelDownload: true,
            messages: _currentMessages,
            knowledgeScope: _currentScope,
          ));
          return;
        }
      } else {
        emit(const ChatLoading());
        return;
      }
    }

    // Reset tracking
    _accumulatedText = '';

    log_util.log.i(
        '📤 [SendMessage] session=$_currentSessionId content="${event.content.length > 100 ? '${event.content.substring(0, 100)}...' : event.content}" (length=${event.content.length})');

    try {
      // 1. Save user message
      final userMsg = await _messageRepo.saveMessage(
        sessionId: _currentSessionId!,
        role: MessageRole.user,
        content: event.content,
      );
      log_util.log.i('💾 [SendMessage] Đã lưu user message vào DB (id=${userMsg.id})');

      final currentMessages = <MessageModel>[
        ..._currentMessages,
        userMsg,
      ];
      _currentMessages = currentMessages;
      emit(ChatThinking(currentMessages, knowledgeScope: _currentScope));

      // ─── 2. RAG retrieval via RagService ─────────────────────────────
      // VERSION=dynamic_budget_v1 - Phân bổ budget động theo loại câu hỏi
      final queryBudget = ContextBudget.forQuery(event.content);
      final allocation = queryBudget.calculate(kGemmaMaxTokens);
      final questionTokens = estimateTokens(event.content);

      // Tính history tokens thực tế (không vượt quá budget)
      var historyTokenSum = 0;
      for (int i = _currentMessages.length - 1; i >= 0; i--) {
        final msgToken = estimateMessageTokens(_currentMessages[i].content);
        if (historyTokenSum + msgToken > allocation.historyTokens) break;
        historyTokenSum += msgToken;
      }

      // RAG budget = allocation.ragTokens - questionTokens
      // (question tokens được trừ khỏi RAG budget để tránh tràn context window)
      final ragBudget = (allocation.ragTokens - questionTokens).clamp(0, kGemmaMaxTokens);

      log_util.log.i(
        '📊 [Budget] VERSION=dynamic_budget_v1 '
        'queryType=${queryBudget.queryType.name}, '
        'allocation=$allocation, '
        'actualHistory=$historyTokenSum/${allocation.historyTokens}, '
        'question=$questionTokens, '
        'rag=$ragBudget/${allocation.ragTokens}, '
        'response=${allocation.responseTokens}, '
        'total=${historyTokenSum + allocation.responseTokens + allocation.systemTokens + questionTokens + ragBudget}',
      );

      // Load KnowledgeScope từ session
      final sessionInfo = await _sessionRepo.getSessionById(_currentSessionId!);
      final scope = sessionInfo?.knowledgeScope ?? KnowledgeScope.attachedAndGlobal;

      final ragContext = await _ragService.retrieve(
        query: event.content,
        tokenBudget: ragBudget.clamp(0, kGemmaMaxTokens),
        scope: scope,
        sessionId: _currentSessionId,
      );

      // ─── 3. FIX: Đảm bảo session tồn tại (KHÔNG recreate) ─────────────
      // Session đã được tạo ở _onSessionInitialized, chỉ tạo mới nếu bị mất
      if (!_gemmaService.hasActiveSession) {
        log_util.log.w('⚠️ [Session] Session bị mất — tạo lại session mới...');
        await _recreateSession();
      }

      // ─── 4. Build turn payload (RAG + question, KHÔNG có history) ─────
      final turnPayload = await _promptBuilder.buildTurnPayload(
        question: event.content,
        ragContext: ragContext,
      );

      log_util.log.i('🔍 [RAG] Tìm thấy ${ragContext.chunks.length} chunks liên quan');
      log_util.log.i('📝 [Turn] Payload length: ${turnPayload.length} chars');

      // 5. Stream response qua session API
      final assistantMsgId = _uuid.v4();
      log_util.log.i('🚀 [Stream] Bắt đầu generateWithSession (assistantMsgId=$assistantMsgId)');

      await emit.forEach<String>(
        _gemmaService.generateWithSession(turnPayload),
        onData: (token) {
          _accumulatedText += token;
          return ChatStreaming(
            messages: currentMessages,
            streamingText: _accumulatedText,
            streamingId: assistantMsgId,
            ragResults: ragContext.hasContext ? ragContext.chunks : null,
            knowledgeScope: _currentScope,
          );
        },
        onError: (error, _) {
          log_util.log.e('❌ [Stream] Lỗi: $error');
          // Session lỗi → đóng để tạo lại lần sau
          _gemmaService.closeSession();
          return ChatError(
            message: error.toString(),
            messages: currentMessages,
            knowledgeScope: _currentScope,
          );
        },
      );

      // 6. Save complete assistant message
      if (_accumulatedText.isNotEmpty && state is! ChatError) {
        log_util.log.i('💾 [SendMessage] Assistant response:\n$_accumulatedText');
        final assistantMsg = await _messageRepo.saveMessage(
          sessionId: _currentSessionId!,
          role: MessageRole.assistant,
          content: _accumulatedText,
        );

        await _sessionRepo.updateSessionTimestamp(_currentSessionId!);

        final finalMessages = <MessageModel>[...currentMessages, assistantMsg];
        _currentMessages = finalMessages;
        log_util.log.i('✅ [SendMessage] Hoàn tất: ${finalMessages.length} messages'
            '\nAssistant response:\n$_accumulatedText');
        // ─── Auto-summary trigger ──────────────────────────────────
        _tryTriggerAutoSummary();

        emit(ChatLoaded(finalMessages, knowledgeScope: _currentScope));
      } else {
        log_util.log.w('⚠️ [SendMessage] Response rỗng hoặc có lỗi — không lưu assistant message');
      }
    } catch (e) {
      log_util.log.e('❌ [SendMessage] Lỗi: $e');
      _gemmaService.closeSession();
      if (e is ModelNotLoadedException) {
        emit(ChatError(
          message: e.message,
          needsModelDownload: true,
          messages: _currentMessages,
          knowledgeScope: _currentScope,
        ));
      } else {
        emit(ChatError(
          message: e.toString(),
          messages: _currentMessages,
          knowledgeScope: _currentScope,
        ));
      }
    }
  }

  /// Tạo lại session khi bị mất (giữa chừng).
  Future<void> _recreateSession() async {
    if (!_gemmaService.isReady) return;

    // Build system instruction
    final userMemories = await _memoryStore.getAllUserMemories();
    final userMemoryObjects = userMemories
        .map((m) => UserMemory(namespace: m.namespace, key: m.key, value: m.value))
        .toList();

    final memoryRow = await _memoryStore.getSessionMemory(_currentSessionId!);
    final String systemInstruction;

    if (memoryRow?.summary != null && memoryRow!.summary!.isNotEmpty) {
      final userMemoryList = <({String nspace, String key, String value})>[];
      for (final m in userMemories) {
        userMemoryList.add((nspace: m.namespace, key: m.key, value: m.value));
      }
      systemInstruction = MemoryPromptFormatter.build(
        summary: memoryRow.summary,
        userMemories: userMemoryList,
      );
    } else {
      systemInstruction = await _promptBuilder.buildSystemInstruction(
        userMemories: userMemoryObjects,
      );
    }

    await _gemmaService.createSession(systemInstruction: systemInstruction);
    log_util.log.i('🆕 [Session] Recreated session with system instruction');

    // Replay history (dùng kSessionInitHistoryRatio — đồng bộ với _onSessionInitialized)
    final historyBudget = (kGemmaMaxTokens * kSessionInitHistoryRatio).round();
    final historyMessages = <MessageModel>[];
    var historyTokenSum = 0;

    for (int i = _currentMessages.length - 1; i >= 0; i--) {
      final msgToken = estimateMessageTokens(_currentMessages[i].content);
      if (historyTokenSum + msgToken > historyBudget) break;
      historyTokenSum += msgToken;
      historyMessages.insert(0, _currentMessages[i]);
    }

    for (final msg in historyMessages) {
      await _gemmaService.addHistoryMessage(msg.role.name, msg.content);
    }
    log_util.log.i('🔄 [Session] Replayed ${historyMessages.length} messages (~${historyTokenSum}tok)');
  }

  void _onModelBecameReady(
    ModelBecameReady event,
    Emitter<ChatState> emit,
  ) {
    // Xoá trạng thái chờ
    _isWaitingForModel = false;
    _pendingMessage = null;
    _modelSubscription?.cancel();
    _modelSubscription = null;

    // Nếu đang ở trạng thái error hoặc loading do model chưa ready → chuyển về loaded
    if (state is ChatError || state is ChatLoading) {
      emit(ChatLoaded(_currentMessages, knowledgeScope: _currentScope));
    }
  }

  Future<void> _onKnowledgeScopeChanged(
    KnowledgeScopeChanged event,
    Emitter<ChatState> emit,
  ) async {
    if (isClosed) return;
    if (_currentSessionId == null) return;

    _currentScope = event.scope;

    try {
      await _sessionRepo.updateKnowledgeScope(_currentSessionId!, event.scope);
      log_util.log.i('🎯 [KnowledgeScope] Updated to ${event.scope.name} for session $_currentSessionId');

      // Nếu đang ở loaded/error → emit lại state với scope mới
      if (state is ChatLoaded) {
        final loaded = state as ChatLoaded;
        emit(ChatLoaded(loaded.messages, knowledgeScope: _currentScope));
      } else if (state is ChatError) {
        final err = state as ChatError;
        emit(ChatError(
          message: err.message,
          needsModelDownload: err.needsModelDownload,
          messages: err.messages,
          knowledgeScope: _currentScope,
        ));
      }
    } catch (e) {
      log_util.log.e('❌ [KnowledgeScope] Lỗi update: $e');
    }
  }

  Future<void> _onStreamingCancelled(
    StreamingCancelled event,
    Emitter<ChatState> emit,
  ) async {
    if (isClosed) return;
    if (state is! ChatStreaming) return;

    final streamingState = state as ChatStreaming;

    // Đóng session Gemma để dừng stream thực sự (fix Bug C)
    await _gemmaService.closeSession();
    log_util.log.i('🛑 [Stream] Streaming cancelled — session closed');

    if (_accumulatedText.isNotEmpty && _currentSessionId != null) {
      try {
        // Lưu partial response với suffix [đã dừng]
        final partialContent = '$_accumulatedText\n\n_(Đã dừng)_';
        final assistantMsg = await _messageRepo.saveMessage(
          sessionId: _currentSessionId!,
          role: MessageRole.assistant,
          content: partialContent,
        );
        await _sessionRepo.updateSessionTimestamp(_currentSessionId!);

        final finalMessages = <MessageModel>[
          ...streamingState.messages,
          assistantMsg,
        ];
        _currentMessages = finalMessages;
        _accumulatedText = '';
        emit(ChatLoaded(finalMessages, knowledgeScope: _currentScope));
        return;
      } catch (_) {
        // Nếu lưu DB thất bại, vẫn trả về UI bình thường
      }
    }

    _accumulatedText = '';
    emit(ChatLoaded(streamingState.messages, knowledgeScope: _currentScope));
  }

  Future<void> _onMessagesCleared(
    MessagesCleared event,
    Emitter<ChatState> emit,
  ) async {
    if (isClosed) return;
    if (_currentSessionId == null) return;
    if (state is ChatStreaming) return; // Block khi đang stream

    try {
      await _messageRepo.deleteMessagesBySession(_currentSessionId!);
      _currentMessages = [];
      emit(ChatLoaded([], knowledgeScope: _currentScope));
    } catch (e) {
      emit(ChatError(message: e.toString(), messages: _currentMessages, knowledgeScope: _currentScope));
    }
  }

  // ─── Auto Summary ────────────────────────────────────────────────────

  /// Kiểm tra điều kiện và trigger auto-summary (non-blocking).
  void _tryTriggerAutoSummary() {
    if (_isSummarizing) return;
    if (!_gemmaService.isReady) return;
    if (_currentSessionId == null) return;

    // Tính runningTokenCount hiện tại
    final newRunningCount = _currentMessages.fold<int>(
      0,
      (sum, m) => sum + estimateMessageTokens(m.content),
    );

    if (newRunningCount <= _memoryBudget.summaryTrigger) {
      // Cập nhật runningTokenCount trong DB mà không trigger summarize
      _memoryStore.updateRunningTokenCount(_currentSessionId!, newRunningCount);
      return;
    }

    log_util.log
        .i('📝 [AutoSummary] Triggered: runningTokens=$newRunningCount > trigger=${_memoryBudget.summaryTrigger}');
    unawaited(_runAutoSummary());
  }

  Future<void> _runAutoSummary() async {
    if (_isSummarizing) return;
    _isSummarizing = true;

    try {
      final sessionId = _currentSessionId;
      if (sessionId == null) return;

      // 1. Lấy old summary
      final oldRow = await _memoryStore.getSessionMemory(sessionId);

      // 2. Lấy messages từ lần summarize cuối (based on msgCount trong old summary)
      final allMessages = await _messageRepo.getMessages(sessionId);
      final oldMsgCount = oldRow?.msgCount ?? 0;
      var newMessages = <MessageModel>[];
      if (oldMsgCount < allMessages.length) {
        newMessages = allMessages.sublist(oldMsgCount);
      } else if (oldMsgCount == allMessages.length && oldMsgCount > 0) {
        // Đã summarize hết rồi nhưng runningTokenCount reset → không cần summarize lại
        log_util.log.i('📝 [AutoSummary] No new messages since last summary (msgCount=$oldMsgCount) — skipping');
        return;
      } else {
        newMessages = allMessages;
      }

      if (newMessages.isEmpty && oldRow?.summary != null) {
        log_util.log.i('📝 [AutoSummary] No new messages for this session — skipping');
        return;
      }

      // 3. Incremental summarize
      final summary = await _summaryService.incrementalSummarize(
        oldSummary: oldRow?.summary,
        newMessages: newMessages,
      );

      if (summary == null) {
        log_util.log.w('⚠️ [AutoSummary] Summary returned null — skipping');
        return;
      }

      // 4. Tính actual recent tokens (các message sẽ replay khi mở session)
      final actualRecentTokens = _currentMessages.fold<int>(
        0,
        (sum, m) => sum + estimateMessageTokens(m.content),
      );

      final summaryTokens = estimateTokens(summary);
      final newRunningCount = summaryTokens + actualRecentTokens;

      // 5. Lưu SessionMemory
      await _memoryStore.saveSessionMemory(
        sessionId: sessionId,
        summary: summary,
        summaryVersion: (oldRow?.summaryVersion ?? 0) + 1,
        msgCount: allMessages.length,
        estTokens: summaryTokens,
        runningTokenCount: newRunningCount,
      );

      log_util.log.i(
        '📝 [AutoSummary] Done: '
        'v${(oldRow?.summaryVersion ?? 0) + 1}, '
        '~${summaryTokens}tok, '
        'msgCount=${allMessages.length}, '
        'runningTokenCount reset to $newRunningCount',
      );

      // 6. Extract user memory (nếu đến interval)
      if ((oldRow?.summaryVersion ?? 0) % kUserMemoryExtractInterval == 0) {
        unawaited(_summaryService.extractUserMemory(allMessages));
      }
    } catch (e) {
      log_util.log.w('⚠️ [AutoSummary] Error: $e');
    } finally {
      _isSummarizing = false;
    }
  }

  @override
  Future<void> close() async {
    _modelSubscription?.cancel();
    _accumulatedText = '';
    return super.close();
  }
}