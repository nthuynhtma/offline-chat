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
  final GemmaService _gemmaService;
  final GeckoService _geckoService;
  final VectorStoreService _vectorStore;
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
    required GemmaService gemmaService,
    required GeckoService geckoService,
    required VectorStoreService vectorStore,
    required ModelBloc modelBloc,
  })  : _messageRepo = messageRepo,
        _sessionRepo = sessionRepo,
        _gemmaService = gemmaService,
        _geckoService = geckoService,
        _vectorStore = vectorStore,
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

      // Tạo Gemma session với system instruction
      await _createGemmaSessionWithHistory(messages);

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
          log_util.log.i('🔍 [RAG] Tìm thấy ${ragResults.length} chunks liên quan');
        } catch (e) {
          log_util.log.w('⚠️ [RAG] Lỗi khi retrieve chunks: $e — graceful degradation');
          ragResults = [];
        }
      }

      // 3. Build user message với RAG context nếu có
      String userMessageForModel = event.content;
      if (ragResults.isNotEmpty) {
        final ragPreface = StringBuffer();
        ragPreface.writeln('[Tài liệu tham khảo từ cơ sở tri thức cá nhân (ưu tiên dùng thông tin này):]');
        for (int i = 0; i < ragResults.length; i++) {
          ragPreface.writeln('\n[Tài liệu ${i + 1}]');
          ragPreface.writeln(ragResults[i].chunkText);
        }
        ragPreface.writeln('\n[Câu hỏi của người dùng:]');
        ragPreface.writeln(event.content);
        userMessageForModel = ragPreface.toString();

        // Kiểm tra nếu quá dài thì trim RAG chunks
        final estimatedTokens = (userMessageForModel.length / 3).ceil();
        if (estimatedTokens > 800) {
          log_util.log.w('⚠️ [RAG] User message + RAG quá dài (~$estimatedTokens tokens), cắt giảm RAG');
          final shortRagPreface = StringBuffer();
          shortRagPreface.writeln('[Tài liệu tham khảo:]');
          var usedChars = shortRagPreface.length;
          for (int i = 0; i < ragResults.length && usedChars < 2400; i++) {
            final chunk = ragResults[i].chunkText;
            final maxChunkLen = 800 - usedChars - event.content.length;
            final trimmedChunk = maxChunkLen > 100 ? chunk.substring(0, maxChunkLen) : chunk.substring(0, 100);
            shortRagPreface.writeln('\n[Tài liệu ${i + 1}]');
            shortRagPreface.writeln(trimmedChunk);
            usedChars += chunk.length + 20;
          }
          shortRagPreface.writeln('\n[Câu hỏi:]');
          shortRagPreface.writeln(event.content);
          userMessageForModel = shortRagPreface.toString();
        }
      }

      // 4. Đảm bảo session tồn tại
      if (!_gemmaService.hasActiveSession) {
        log_util.log.i('🔄 [Session] Tạo Gemma session mới...');
        await _createGemmaSessionWithHistory(_currentMessages);
      }

      // 5. Stream response qua session API
      final assistantMsgId = _uuid.v4();
      log_util.log.i('🚀 [Stream] Bắt đầu generateWithSession (assistantMsgId=$assistantMsgId)');

      await emit.forEach<String>(
        _gemmaService.generateWithSession(userMessageForModel),
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
        log_util.log.i('✅ [SendMessage] Hoàn tất: ${currentMessages.length} messages, response=${_accumulatedText.length} chars');
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

    // Replay lịch sử chat vào session
    for (final msg in messages) {
      await _gemmaService.addHistoryMessage(
        msg.role.name,
        msg.content,
      );
    }
    log_util.log.i('🔄 [Session] Replayed ${messages.length} messages into Gemma session');
  }

  @override
  Future<void> close() async {
    _modelSubscription?.cancel();
    _accumulatedText = '';
    return super.close();
  }
}
