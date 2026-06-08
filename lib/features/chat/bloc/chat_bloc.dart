import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/features/session/repositories/session_repository.dart';
import 'package:offline_chat/services/context/context_manager_service.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
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
  const ChatStreaming({
    required this.messages,
    required this.streamingText,
    required this.streamingId,
  });

  @override
  List<Object?> get props => [messages, streamingText, streamingId];
}

class ChatError extends ChatState {
  final String message;
  final bool needsModelDownload;
  const ChatError({
    required this.message,
    this.needsModelDownload = false,
  });

  @override
  List<Object?> get props => [message, needsModelDownload];
}

// Bloc
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MessageRepository _messageRepo;
  final SessionRepository _sessionRepo;
  final ContextManagerService _contextManager;
  final GemmaService _gemmaService;
  final PromptBuilderService _promptBuilder;
  final Uuid _uuid = const Uuid();

  String? _currentSessionId;

  ChatBloc({
    required MessageRepository messageRepo,
    required SessionRepository sessionRepo,
    required ContextManagerService contextManager,
    required GemmaService gemmaService,
    required PromptBuilderService promptBuilder,
  })  : _messageRepo = messageRepo,
        _sessionRepo = sessionRepo,
        _contextManager = contextManager,
        _gemmaService = gemmaService,
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
    _currentSessionId = event.sessionId;
    emit(const ChatLoading());
    try {
      final messages = await _messageRepo.getMessages(event.sessionId);
      emit(ChatLoaded(messages));
    } catch (e) {
      emit(ChatError(message: e.toString()));
    }
  }

  Future<void> _onSendMessageRequested(
    SendMessageRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (_currentSessionId == null) return;
    if (!_gemmaService.isReady) {
      emit(const ChatError(
        message: 'Model chưa sẵn sàng',
        needsModelDownload: true,
      ));
      return;
    }

    try {
      // 1. Save user message
      final userMsg = await _messageRepo.saveMessage(
        sessionId: _currentSessionId!,
        role: MessageRole.user,
        content: event.content,
      );

      final currentMessages = <MessageModel>[
        ...(state is ChatLoaded ? (state as ChatLoaded).messages : <MessageModel>[]),
        userMsg,
      ];
      emit(ChatLoaded(currentMessages));

      // 2. Build context (RAG will be added in Phase 3)
      final context = await _contextManager.buildContext(
        question: event.content,
        sessionId: _currentSessionId!,
        ragResults: [],
      );

      // 3. Build prompt
      final prompt = _promptBuilder.build(context);

      // 4. Stream response
      final assistantMsgId = _uuid.v4();
      String accumulated = '';

      await emit.forEach<String>(
        _gemmaService.generateStream(prompt),
        onData: (token) {
          accumulated += token;
          return ChatStreaming(
            messages: currentMessages,
            streamingText: accumulated,
            streamingId: assistantMsgId,
          );
        },
        onError: (error, _) => ChatError(message: error.toString()),
      );

      // 5. Save complete assistant message
      final assistantMsg = await _messageRepo.saveMessage(
        sessionId: _currentSessionId!,
        role: MessageRole.assistant,
        content: accumulated,
      );

      // 6. Update session timestamp
      await _sessionRepo.updateSessionTimestamp(_currentSessionId!);

      emit(ChatLoaded(<MessageModel>[...currentMessages, assistantMsg]));
    } catch (e) {
      if (e is ModelNotLoadedException) {
        emit(ChatError(message: e.message, needsModelDownload: true));
      } else {
        emit(ChatError(message: e.toString()));
      }
    }
  }

  void _onStreamingCancelled(
    StreamingCancelled event,
    Emitter<ChatState> emit,
  ) {
    // When streaming is cancelled, emit current messages without streaming text
    if (state is ChatStreaming) {
      final streamingState = state as ChatStreaming;
      emit(ChatLoaded(streamingState.messages));
    }
  }

  Future<void> _onMessagesCleared(
    MessagesCleared event,
    Emitter<ChatState> emit,
  ) async {
    if (_currentSessionId == null) return;
    try {
      await _messageRepo.deleteMessagesBySession(_currentSessionId!);
      emit(const ChatLoaded([]));
    } catch (e) {
      emit(ChatError(message: e.toString()));
    }
  }
}
