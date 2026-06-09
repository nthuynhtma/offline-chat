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
import 'package:offline_chat/services/context/context_manager_service.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

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
  final ContextManagerService _contextManager;
  final GemmaService _gemmaService;
  final GeckoService _geckoService;
  final VectorStoreService _vectorStore;
  final PromptBuilderService _promptBuilder;
  final ModelBloc _modelBloc;
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

  ChatBloc({
    required MessageRepository messageRepo,
    required SessionRepository sessionRepo,
    required ContextManagerService contextManager,
    required GemmaService gemmaService,
    required GeckoService geckoService,
    required VectorStoreService vectorStore,
    required PromptBuilderService promptBuilder,
    required ModelBloc modelBloc,
  })  : _messageRepo = messageRepo,
        _sessionRepo = sessionRepo,
        _contextManager = contextManager,
        _gemmaService = gemmaService,
        _geckoService = geckoService,
        _vectorStore = vectorStore,
        _promptBuilder = promptBuilder,
        _modelBloc = modelBloc,
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
          // File đã download, model đang init (load vào memory).
          // Lưu pending message để gửi sau, subscribe vào modelBloc stream.
          _pendingMessage = event.content;
          _isWaitingForModel = true;

          // Subscribe vào modelBloc stream để tự động gửi khi model ready
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
              // Gửi lại message đã lưu (dùng microtask tránh race condition)
              Future.microtask(() => add(SendMessageRequested(pending!)));
            }
          });

          // Subscribe lần đầu có thể bỏ qua state hiện tại
          // Nếu model đã ready giữa lúc kiểm tra và subscribe
          final currentModelState = _modelBloc.state;
          if (currentModelState is ModelLoaded &&
              currentModelState.gemmaReady) {
            _isWaitingForModel = false;
            _pendingMessage = null;
            _modelSubscription?.cancel();
            _modelSubscription = null;
            // Continue bên dưới thay vì loading
          } else {
            emit(const ChatLoading());
            return;
          }
        }

        if (!isDownloaded) {
          // Chưa download → emit error như cũ
          emit(ChatError(
            message: 'Model AI chưa được tải. Vui lòng tải model trước.',
            needsModelDownload: true,
            messages: _currentMessages,
          ));
          return;
        }
      } else {
        // ModelLoading hoặc ModelError → đợi
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

      // 2. RAG retrieval
      List<SearchResult> ragResults = [];
      if (_geckoService.isReady) {
        try {
          final queryVector = await _geckoService.embed(event.content);
          ragResults = await _vectorStore.search(
            queryVector: queryVector,
            topK: 5,
            threshold: 0.7,
          );
          log_util.log.i('🔍 [RAG] Tìm thấy ${ragResults.length} chunks liên quan (topK=5, threshold=0.7)');
          if (ragResults.isNotEmpty) {
            for (int i = 0; i < ragResults.length; i++) {
              log_util.log.d('[RAG]   chunk[$i]: score=${ragResults[i].score.toStringAsFixed(4)} chunkId=${ragResults[i].chunkId} text="${ragResults[i].chunkText.length > 80 ? '${ragResults[i].chunkText.substring(0, 80)}...' : ragResults[i].chunkText}"');
            }
          }
        } catch (e) {
          log_util.log.w('⚠️ [RAG] Lỗi khi retrieve chunks: $e — graceful degradation, ragResults=[]');
          // Graceful degradation
          ragResults = [];
        }
      } else {
        log_util.log.w('⚠️ [RAG] Gecko service chưa ready — bỏ qua RAG retrieval');
      }

      // 3. Build context
      log_util.log.i('🧠 [Context] Đang build context...');
      final context = await _contextManager.buildContext(
        question: event.content,
        sessionId: _currentSessionId!,
        ragResults: ragResults,
      );
      log_util.log.i('🧠 [Context] Context built: history=${context.history.length} messages, chunks=${context.relevantChunks.length}, summary=${context.summary != null && context.summary!.isNotEmpty ? context.summary!.length.toString() : "none"}, estimatedTokens=${context.estimatedTokens}, historyWasTrimmed=${context.historyWasTrimmed}');

      // 4. Build prompt
      log_util.log.i('📝 [Prompt] Đang build prompt...');
      final prompt = _promptBuilder.build(context);
      final promptLineCount = prompt.split('\n').length;
      log_util.log.i('📝 [Prompt] Prompt built: ${prompt.length} chars, $promptLineCount lines');
      log_util.log.d('📝 [Prompt] === FULL PROMPT ===\n$prompt\n📝 [Prompt] === END PROMPT ===');

      // 5. Stream response
      final assistantMsgId = _uuid.v4();
      log_util.log.i('🚀 [Stream] Bắt đầu generate stream (assistantMsgId=$assistantMsgId)');

      await emit.forEach<String>(
        _gemmaService.generateStream(prompt),
        onData: (token) {
          _accumulatedText += token;
          return ChatStreaming(
            messages: currentMessages,
            streamingText: _accumulatedText,
            streamingId: assistantMsgId,
            ragResults: ragResults.isNotEmpty ? ragResults : null,
          );
        },
        onError: (error, _) {
          log_util.log.e('❌ [Stream] Lỗi trong quá trình stream: $error');
          return ChatError(
            message: error.toString(),
            messages: currentMessages,
          );
        },
      );

      // 6. Save complete assistant message (nếu có nội dung và không lỗi)
      if (_accumulatedText.isNotEmpty && state is! ChatError) {
        log_util.log.i('💾 [SendMessage] Lưu assistant response (${_accumulatedText.length} chars)');

        final assistantMsg = await _messageRepo.saveMessage(
          sessionId: _currentSessionId!,
          role: MessageRole.assistant,
          content: _accumulatedText,
        );

        // 7. Update session timestamp
        await _sessionRepo.updateSessionTimestamp(_currentSessionId!);

        final finalMessages = <MessageModel>[...currentMessages, assistantMsg];
        _currentMessages = finalMessages;
        log_util.log.i('✅ [SendMessage] Hoàn tất: ${currentMessages.length} messages trong session, response length=${_accumulatedText.length}');
        emit(ChatLoaded(finalMessages));
      } else {
        log_util.log.w('⚠️ [SendMessage] Response rỗng hoặc có lỗi — không lưu assistant message');
      }
    } catch (e) {
      log_util.log.e('❌ [SendMessage] Lỗi: $e');
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

  @override
  Future<void> close() async {
    _modelSubscription?.cancel();
    _accumulatedText = '';
    return super.close();
  }
}