import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
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
import 'package:offline_chat/services/memory_store/memory_store_service.dart';
import 'package:offline_chat/services/memory_store/summary_service.dart';
import 'package:offline_chat/services/memory_store/memory_prompt_formatter.dart';
import 'package:offline_chat/services/rag/rag_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';

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

class ChatLoaded extends ChatState {
  final List<MessageModel> messages;
  const ChatLoaded(this.messages);

  @override
  List<Object?> get props => [messages];
}

class ChatThinking extends ChatState {
  final List<MessageModel> messages;
  const ChatThinking(this.messages);

  @override
  List<Object?> get props => [messages];
}

class ChatStreaming extends ChatState {
  final List<MessageModel> messages;
  final String streamingText;
  final String streamingId;
  final List<SearchResult>? ragResults;
  const ChatStreaming({
    required this.messages,
    required this.streamingText,
    required this.streamingId,
    this.ragResults,
  });

  @override
  List<Object?> get props => [messages, streamingText, streamingId, ragResults];
}

class ChatError extends ChatState {
  final String message;
  final bool needsModelDownload;
  final List<MessageModel> messages;
  const ChatError({
    required this.message,
    this.needsModelDownload = false,
    this.messages = const [],
  });

  @override
  List<Object?> get props => [message, needsModelDownload, messages];
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

      // Kiểm tra xem có SessionMemory (summary) không
      final memoryRow = await _memoryStore.getSessionMemory(event.sessionId);

      if (memoryRow?.summary != null && memoryRow!.summary!.isNotEmpty) {
        // Có summary → inject vào system instruction + replay recent messages
        final userMemories = await _memoryStore.getAllUserMemories();
        final userMemoryList = <({String nspace, String key, String value})>[];
        for (final m in userMemories) {
          userMemoryList.add((nspace: m.namespace, key: m.key, value: m.value));
        }

        final systemInstruction = MemoryPromptFormatter.build(
          summary: memoryRow.summary,
          userMemories: userMemoryList,
        );

        await _gemmaService.createSession(
          systemInstruction: systemInstruction,
        );
        log_util.log.i('🧠 [Session] Created with summary (v${memoryRow.summaryVersion}, ~${memoryRow.estTokens}tok)');

        // Replay N messages gần nhất (token-based, dùng recentConversationBudget)
        final recentBudget = _memoryBudget.recentConversationBudget;
        final recentMessages = <MessageModel>[];
        var recentTokenSum = 0;
        for (int i = messages.length - 1; i >= 0; i--) {
          final msgToken = estimateMessageTokens(messages[i].content);
          if (recentTokenSum + msgToken > recentBudget) break;
          recentTokenSum += msgToken;
          recentMessages.insert(0, messages[i]);
        }

        for (final msg in recentMessages) {
          await _gemmaService.addHistoryMessage(
            msg.role.name,
            msg.content,
          );
        }
        log_util.log.i('🔄 [Session] Replayed ${recentMessages.length} recent messages (~${recentTokenSum}tok budget=${recentBudget}tok)');
      } else {
        // Không có summary → replay history bình thường (token-budget)
        await _createGemmaSessionWithHistory(messages);
      }

      emit(ChatLoaded(messages));
    } catch (e) {
      emit(ChatError(message: e.toString()));
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
        final isDownloaded =
            modelState.gemmaInfo.status == ModelStatus.downloaded;

        if (isDownloaded && !modelState.gemmaReady) {
          _pendingMessage = event.content;
          _isWaitingForModel = true;

          _modelSubscription?.cancel();
          _modelSubscription = _modelBloc.stream.listen((newState) {
            if (newState is ModelLoaded &&
                newState.gemmaReady &&
                _pendingMessage != null) {
              final pending = _pendingMessage;
              _pendingMessage = null;
              _isWaitingForModel = false;
              _modelSubscription?.cancel();
              _modelSubscription = null;
              Future.microtask(() => add(SendMessageRequested(pending!)));
            }
          });

          final currentModelState = _modelBloc.state;
          if (currentModelState is ModelLoaded &&
              currentModelState.gemmaReady) {
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

    log_util.log.i('📤 [SendMessage] session=$_currentSessionId content="${event.content.length > 100 ? '${event.content.substring(0, 100)}...' : event.content}" (length=${event.content.length})');

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
      emit(ChatThinking(currentMessages));

      // ─── 2. RAG retrieval via RagService ─────────────────────────────
      // Tính token budget động cho RAG
      final historyBudget = (kGemmaMaxTokens * kHistoryBudgetRatio).round();
      final reservedResponse = (kGemmaMaxTokens * kResponseBudgetRatio).round();
      final reservedSystem = (kGemmaMaxTokens * kSystemBudgetRatio).round();
      final questionTokens = estimateTokens(event.content);

      var historyTokenSum = 0;
      for (int i = _currentMessages.length - 1; i >= 0; i--) {
        final msgToken = estimateMessageTokens(_currentMessages[i].content);
        if (historyTokenSum + msgToken > historyBudget) break;
        historyTokenSum += msgToken;
      }

      final ragBudget = kGemmaMaxTokens -
          historyTokenSum -
          reservedResponse -
          reservedSystem -
          questionTokens;

      log_util.log.i(
        '📊 Context Budget: '
        'history=$historyTokenSum, '
        'response=$reservedResponse, '
        'system=$reservedSystem, '
        'question=$questionTokens, '
        'rag=$ragBudget, '
        'total=${historyTokenSum + reservedResponse + reservedSystem + questionTokens + ragBudget.clamp(0, kGemmaMaxTokens)}',
      );

      final ragContext = await _ragService.retrieve(
        query: event.content,
        tokenBudget: ragBudget.clamp(0, kGemmaMaxTokens),
      );

      // 3. Build prompt via PromptBuilder
      final userMemories = await _memoryStore.getAllUserMemories();
      final userMemoryList = userMemories
          .map((m) => UserMemory(
              namespace: m.namespace, key: m.key, value: m.value))
          .toList();

      final memoryRow = await _memoryStore.getSessionMemory(_currentSessionId!);

      final prompt = await _promptBuilder.build(
        question: event.content,
        ragContext: ragContext,
        history: _currentMessages,
        sessionSummary: memoryRow?.summary,
        userMemories: userMemoryList,
      );

      log_util.log.i('🔍 [RAG] Tìm thấy ${ragContext.chunks.length} chunks liên quan');

      // 4. Đảm bảo session tồn tại
      if (!_gemmaService.hasActiveSession) {
        log_util.log.i('🔄 [Session] Tạo Gemma session mới...');
        await _createGemmaSessionWithHistory(_currentMessages);
      }

      // 5. Stream response qua session API
      final assistantMsgId = _uuid.v4();
      log_util.log.i('🚀 [Stream] Bắt đầu generateWithSession (assistantMsgId=$assistantMsgId)');

      await emit.forEach<String>(
        _gemmaService.generateWithSession(prompt),
        onData: (token) {
          _accumulatedText += token;
          return ChatStreaming(
            messages: currentMessages,
            streamingText: _accumulatedText,
            streamingId: assistantMsgId,
            ragResults: ragContext.hasContext ? ragContext.chunks : null,
          );
        },
        onError: (error, _) {
          log_util.log.e('❌ [Stream] Lỗi: $error');
          // Session lỗi → đóng để tạo lại lần sau
          _gemmaService.closeSession();
          return ChatError(
            message: error.toString(),
            messages: currentMessages,
          );
        },
      );

      // 6. Save complete assistant message
      if (_accumulatedText.isNotEmpty && state is! ChatError) {
        log_util.log.i('💾 [SendMessage] Lưu assistant response (${_accumulatedText.length} chars)');

        final assistantMsg = await _messageRepo.saveMessage(
          sessionId: _currentSessionId!,
          role: MessageRole.assistant,
          content: _accumulatedText,
        );

        await _sessionRepo.updateSessionTimestamp(_currentSessionId!);

        final finalMessages = <MessageModel>[...currentMessages, assistantMsg];
        _currentMessages = finalMessages;
        log_util.log.i('✅ [SendMessage] Hoàn tất: ${finalMessages.length} messages, response=${_accumulatedText.length} chars');

        // ─── Auto-summary trigger ──────────────────────────────────
        _tryTriggerAutoSummary();

        emit(ChatLoaded(finalMessages));
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
        ));
      } else {
        emit(ChatError(
          message: e.toString(),
          messages: _currentMessages,
        ));
      }
    }
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
      emit(ChatLoaded(_currentMessages));
    }
  }

  Future<void> _onStreamingCancelled(
    StreamingCancelled event,
    Emitter<ChatState> emit,
  ) async {
    if (isClosed) return;
    if (state is! ChatStreaming) return;

    final streamingState = state as ChatStreaming;

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
        emit(ChatLoaded(finalMessages));
        return;
      } catch (_) {
        // Nếu lưu DB thất bại, vẫn trả về UI bình thường
      }
    }

    _accumulatedText = '';
    emit(ChatLoaded(streamingState.messages));
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
      emit(const ChatLoaded([]));
    } catch (e) {
      emit(ChatError(message: e.toString(), messages: _currentMessages));
    }
  }

  /// Tạo Gemma session mới với system instruction và replay history.
  Future<void> _createGemmaSessionWithHistory(List<MessageModel> messages) async {
    if (!_gemmaService.isReady) return;

    // System instruction là "linh hồn" của AgriAI
    const systemInstruction = '''
You are AgriAI, an agricultural assistant running completely offline on a mobile device.

Your primary purpose is to help users with:
- Crop cultivation and management
- Soil health and fertilization
- Pest and disease identification
- Irrigation and water management
- Livestock and poultry farming
- Agricultural best practices
- Sustainable farming techniques

Instructions:
- Answer in the same language as the user.
- Provide practical, clear, and actionable agricultural advice.
- If you are uncertain, clearly state your uncertainty instead of guessing.
- Keep answers concise unless the user asks for more detail.
- Explain agricultural terms in simple language.
- Do not claim to have internet access, real-time data, weather data, or external services.
- Remember that you operate completely offline on the user's mobile device.
''';

    await _gemmaService.createSession(
      systemInstruction: systemInstruction,
    );
    log_util.log.i('🆕 [Session] Gemma session created');

    // Replay lịch sử chat vào session dựa trên token budget
    // Duyệt từ message mới nhất → cũ nhất, dừng khi đạt historyBudget (35% context)
    final historyBudget = (kGemmaMaxTokens * kHistoryBudgetRatio).round();
    final historyMessages = <MessageModel>[];
    var historyTokenSum = 0;

    for (int i = messages.length - 1; i >= 0; i--) {
      final msgToken = estimateMessageTokens(messages[i].content);
      if (historyTokenSum + msgToken > historyBudget) break;
      historyTokenSum += msgToken;
      historyMessages.insert(0, messages[i]);
    }

    for (final msg in historyMessages) {
      await _gemmaService.addHistoryMessage(
        msg.role.name,
        msg.content,
      );
    }
    log_util.log.i('🔄 [Session] Replayed ${historyMessages.length}/${messages.length} messages (~${historyTokenSum}tok budget=${historyBudget}tok)');
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

    log_util.log.i('📝 [AutoSummary] Triggered: runningTokens=$newRunningCount > trigger=${_memoryBudget.summaryTrigger}');
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