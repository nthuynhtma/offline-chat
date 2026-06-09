import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/features/session/repositories/session_repository.dart';
import 'package:offline_chat/services/context/context_manager_service.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';
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
  // FIX #1: Giữ messages khi có lỗi để UI không mất tin nhắn đã hiển thị
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
  final Uuid _uuid = const Uuid();

  String? _currentSessionId;

  // FIX #1: Track accumulated text và currentMessages để cancel có thể lưu
  String _accumulatedText = '';
  List<MessageModel> _currentMessages = [];

  ChatBloc({
    required MessageRepository messageRepo,
    required SessionRepository sessionRepo,
    required ContextManagerService contextManager,
    required GemmaService gemmaService,
    required GeckoService geckoService,
    required VectorStoreService vectorStore,
    required PromptBuilderService promptBuilder,
  })  : _messageRepo = messageRepo,
        _sessionRepo = sessionRepo,
        _contextManager = contextManager,
        _gemmaService = gemmaService,
        _geckoService = geckoService,
        _vectorStore = vectorStore,
        _promptBuilder = promptBuilder,
        super(const ChatInitial()) {
    on<SessionInitialized>(_onSessionInitialized);
    on<SendMessageRequested>(_onSendMessageRequested);
    on<StreamingCancelled>(_onStreamingCancelled);
    on<MessagesCleared>(_onMessagesCleared);
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

    // FIX #11: Block send nếu đang streaming để tránh race condition
    if (state is ChatStreaming) return;

    if (!_gemmaService.isReady) {
      emit(ChatError(
        message: 'Model chưa sẵn sàng',
        needsModelDownload: true,
        messages: _currentMessages,
      ));
      return;
    }

    // Reset tracking
    _accumulatedText = '';

    try {
      // 1. Save user message
      final userMsg = await _messageRepo.saveMessage(
        sessionId: _currentSessionId!,
        role: MessageRole.user,
        content: event.content,
      );

      final currentMessages = <MessageModel>[
        ..._currentMessages,
        userMsg,
      ];
      _currentMessages = currentMessages;
      emit(ChatLoaded(currentMessages));

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
        } catch (_) {
          // Graceful degradation: chat continues without RAG on embedding failure
          ragResults = [];
        }
      }

      // 3. Build context (with RAG results)
      final context = await _contextManager.buildContext(
        question: event.content,
        sessionId: _currentSessionId!,
        ragResults: ragResults,
      );

      // 4. Build prompt
      final prompt = _promptBuilder.build(context);

      // 5. Stream response
      final assistantMsgId = _uuid.v4();

      await emit.forEach<String>(
        _gemmaService.generateStream(prompt),
        onData: (token) {
          // FIX #1: Cập nhật _accumulatedText để _onStreamingCancelled có thể dùng
          _accumulatedText += token;
          return ChatStreaming(
            messages: currentMessages,
            streamingText: _accumulatedText,
            streamingId: assistantMsgId,
            ragResults: ragResults.isNotEmpty ? ragResults : null,
          );
        },
        onError: (error, _) {
          // FIX #1: Giữ lại messages khi stream lỗi, không mất chat history
          return ChatError(
            message: error.toString(),
            messages: currentMessages,
          );
        },
      );

      // 6. FIX #1: Chỉ lưu nếu có nội dung (stream hoàn thành bình thường)
      // Nếu bị cancel, _accumulatedText vẫn có giá trị và đã được lưu
      // bởi _onStreamingCancelled → skip nếu rỗng
      if (_accumulatedText.isNotEmpty && state is! ChatError) {
        final assistantMsg = await _messageRepo.saveMessage(
          sessionId: _currentSessionId!,
          role: MessageRole.assistant,
          content: _accumulatedText,
        );

        // 7. Update session timestamp
        await _sessionRepo.updateSessionTimestamp(_currentSessionId!);

        final finalMessages = <MessageModel>[...currentMessages, assistantMsg];
        _currentMessages = finalMessages;
        emit(ChatLoaded(finalMessages));
      }
    } catch (e) {
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

  // FIX #1: Cancel lưu partial response vào DB thay vì bỏ đi
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

  // FIX #11: Block delete khi đang streaming
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
    _accumulatedText = '';
    return super.close();
  }
}
