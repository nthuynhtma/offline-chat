# Coding Conventions

## 1. Đặt tên

### Files
```
snake_case cho tất cả file:
  chat_bloc.dart       ✅
  ChatBloc.dart        ❌
  chat-bloc.dart       ❌
```

### Classes
```dart
PascalCase:
  class ChatBloc extends Bloc<ChatEvent, ChatState> {}
  class GemmaService {}
  class RagServiceImpl {}
```

### Variables & Methods
```dart
camelCase:
  final String sessionId;
  void _onSendMessageRequested(SendMessageRequested event, Emitter<ChatState> emit) {}
  Stream<String> generateWithSession(String userMessage) async* {}
  
  // Private fields/methods có underscore
  String? _currentSessionId;
  List<MessageModel> _currentMessages = [];
  Future<void> _createGemmaSessionWithHistory(List<MessageModel> messages) async {}
```

### Constants
```dart
// Top-level constants trong constants/
const String kGemmaModelFileName = 'gemma-4-E2B-it.litertlm';
const String kGeckoModelFileName = 'Gecko_256_quant.tflite';
const int kGemmaMaxTokens = 2048;
const int kMaxRagChunks = 3;
const int kMaxRagTokens = 500;
const double kCharsPerToken = 2.5;

// Class-level constants
static const int _topK = 20;
static const double _threshold = 0.7;
const int kMaxHistoryTokens = 300;
```

---

## 2. Bloc Pattern - Bắt buộc

### Event naming
```dart
// sealed class + verb+past tense
sealed class ChatEvent extends Equatable {
  const ChatEvent();
  @override List<Object?> get props => [];
}

class SessionInitialized extends ChatEvent {
  final String sessionId;
  const SessionInitialized(this.sessionId);
  @override List<Object?> get props => [sessionId];
}

class SendMessageRequested extends ChatEvent {
  final String content;
  const SendMessageRequested(this.content);
}
```

### State naming
```dart
sealed class ChatState extends Equatable {
  const ChatState();
  @override List<Object?> get props => [];
}

class ChatInitial extends ChatState { const ChatInitial(); }
class ChatLoading extends ChatState { const ChatLoading(); }
class ChatLoaded extends ChatState implements ChatScopeProvider {
  final List<MessageModel> messages;
  @override final KnowledgeScope knowledgeScope;
  const ChatLoaded(this.messages, {this.knowledgeScope = KnowledgeScope.attachedAndGlobal});
}

// Scope-aware states dùng interface ChatScopeProvider
abstract class ChatScopeProvider {
  KnowledgeScope get knowledgeScope;
}
```

### Bloc implementation
```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MessageRepository _messageRepo;
  final GemmaService _gemmaService;
  final RagService _ragService;
  final PromptBuilder _promptBuilder;

  ChatBloc({
    required MessageRepository messageRepo,
    required GemmaService gemmaService,
    required RagService ragService,
    required PromptBuilder promptBuilder,
  }) : super(const ChatInitial()) {
    on<SessionInitialized>(_onSessionInitialized);
    on<SendMessageRequested>(_onSendMessageRequested);
  }

  // Handler viết tường minh, async/await
  Future<void> _onSendMessageRequested(
    SendMessageRequested event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(ChatThinking(currentMessages));
      final ragContext = await _ragService.retrieve(...);
      final prompt = await _promptBuilder.build(...);
      
      await emit.forEach(
        _gemmaService.generateWithSession(prompt),
        onData: (token) => ChatStreaming(messages: ..., streamingText: accumulated),
        onError: (error, _) => ChatError(message: error.toString()),
      );
    } catch (e) {
      emit(ChatError(message: e.toString()));
    }
  }
}
```

---

## 3. Logger Pattern

Dùng logger utility (không dùng `print`):

```dart
import 'package:offline_chat/core/utils/logger.dart' as log_util;

log_util.log.i('💡 [Tag] message');     // info
log_util.log.d('🐛 [Tag] message');     // debug
log_util.log.w('⚠️ [Tag] message');     // warning
log_util.log.e('⛔ [Tag] message');     // error

// Tag convention: [Category] — PascalCase
log_util.log.i('💡 [UploadQueue] Processing: ${job.name}');
log_util.log.i('💡 [RAG] VERSION=try_fit_v2');
log_util.log.d('🐛 [PromptBuilder] VERSION=dedup_v1 Bắt đầu build prompt...');
log_util.log.w('⚠️ [RagService] Gecko chưa ready — graceful degradation');
log_util.log.e('⛔ [Stream] Lỗi: $error');
```

---

## 4. Error Handling

```dart
// Định nghĩa exceptions rõ ràng
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);
}

class ModelNotLoadedException extends AppException {
  final bool needsModelDownload;
  const ModelNotLoadedException({this.needsModelDownload = true}) 
      : super('AI model chưa được tải.');
}

class ModelTimeoutException extends AppException {
  const ModelTimeoutException() : super('Model timeout sau 120s');
}

class UploadQueueException extends AppException {
  const UploadQueueException(String msg) : super(msg);
}

// Trong bloc: try-catch + emit error state
try {
  // ...
} on ModelNotLoadedException catch (e) {
  emit(ChatError(message: e.message, needsModelDownload: true));
} catch (e) {
  log_util.log.e('⛔ Lỗi không xác định: $e');
  emit(ChatError(message: e.toString()));
}
```

---

## 5. Async/Stream Guidelines

```dart
// ✅ Dùng emit.forEach cho stream trong Bloc
await emit.forEach(
  _gemmaService.generateWithSession(prompt),
  onData: (token) => ChatStreaming(currentText: token),
  onError: (error, _) => ChatError(error.toString()),
);

// ✅ Dùng async* cho service methods trả về Stream
Stream<String> generateWithSession(String userMessage) async* {
  await _session!.addQueryChunk(Message.text(text: userMessage, isUser: true));
  final stream = _session!.getResponseAsync().timeout(
    const Duration(seconds: 120),
    onTimeout: (sink) { sink.addError(const ModelTimeoutException()); sink.close(); },
  );
  await for (final response in stream) {
    yield response;
  }
}

// ❌ KHÔNG dùng StreamController nếu có thể dùng async*
// ❌ KHÔNG forget await khi gọi async method
```

---

## 6. Dependency Injection Pattern

```dart
// registerLazySingleton — cho services, repositories, singleton blocs
sl.registerLazySingleton<GemmaService>(() => GemmaServiceImpl());
sl.registerLazySingleton<ModelBloc>(() => ModelBloc(modelManager: sl(), gemmaService: sl(), geckoService: sl()));

// registerFactory — cho non-singleton blocs (ChatBloc)
sl.registerFactory<ChatBloc>(() => ChatBloc(
  messageRepo: sl(),
  sessionRepo: sl(),
  gemmaService: sl(),
  ragService: sl(),
  promptBuilder: sl(),
));

// Singleton blocs dùng MultiBlocProvider ở app.dart (KHÔNG dùng GetIt lifecycle)
MultiBlocProvider(
  providers: [
    BlocProvider<ModelBloc>(create: (_) => sl<ModelBloc>()..add(const StatusChecked())),
    BlocProvider<SessionBloc>(create: (_) => sl<SessionBloc>()..add(const SessionsLoaded())),
  ],
)
```

---

## 7. Import Order

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:math';

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Pub packages
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:drift/drift.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// 4. Local imports (absolute)
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/services/rag/rag_service.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
```

---

## 8. Chunking Conventions

```dart
// Chars/token estimation: 2 strategies song song
// Chunker: charsPerToken = 4 (character-based split)
// Estimator: kCharsPerToken = 2.5 (Vietnamese conservative, dùng cho budget)

// Runtime default: chunkSize=200, overlap=50 (set trong DocumentUploadQueue)
final chunks = _chunker.chunk(rawText, chunkSize: 200, overlap: 50);

// Log chunk detail với estimateTokens() (single source of truth)
final estimatedTokens = estimateTokens(chunks[i]);

// preview safe substring
final previewLen = min(60, chunks[i].length);
final preview = previewLen > 0 ? chunks[i].substring(0, previewLen) : '';
```

---

## 9. RAG Pipeline Conventions

```dart
// Version markers để verify runtime code
log_util.log.i('[RAG] VERSION=try_fit_v2');
log_util.log.d('🔨 [PromptBuilder] VERSION=dedup_v1');

// Try-fit packing (greedy knapsack)
for (final chunk in results) {
  if (chunkCount >= kMaxRagChunks) break;
  final chunkToken = estimateTokens(chunk.chunkText) + labelTokenOverhead;
  if (chunkToken > effectiveCap) continue;    // continue, không break
  if (tokenSum + chunkToken <= effectiveCap) {
    trimmed.add(chunk);
    tokenSum += chunkToken;
    chunkCount++;
    if (tokenSum >= effectiveCap) break;       // safety guard
  }
}

// shouldSkipRag guard cho no-context queries
RagSkipReason? _shouldSkipRag(String query) {
  if (q.split(' ').length <= 2 && !q.contains('?') && q.length < 15) return RagSkipReason.tooShort;
  if (RegExp(r'^(hi|hello|hey|chào|xin chào)(\s|$)').hasMatch(q)) return RagSkipReason.greeting;
  if (q.contains('bạn là ai') || q.contains('giúp gì')) return RagSkipReason.capability;
  return null;
}
```

---

## 10. BlocProvider Placement

### Singleton Blocs (ModelBloc, SessionBloc, KnowledgeBloc, SessionFilesCubit)
**MultiBlocProvider ở app.dart — KHÔNG trong page:**
```dart
MultiBlocProvider(
  providers: [
    BlocProvider<ModelBloc>(create: (_) => sl<ModelBloc>()..add(const StatusChecked())),
    BlocProvider<SessionBloc>(create: (_) => sl<SessionBloc>()..add(const SessionsLoaded())),
    BlocProvider<KnowledgeBloc>(create: (_) => sl<KnowledgeBloc>()..add(const DocumentsLoaded())),
    BlocProvider<SessionFilesCubit>(create: (_) => sl<SessionFilesCubit>()),
  ],
  child: MaterialApp.router(...),
)
```

### Factory Blocs (ChatBloc — mỗi session 1 instance)
**BlocProvider ở ChatPage với key:**
```dart
class ChatPage extends StatelessWidget {
  final String sessionId;
  const ChatPage({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey('chat_$sessionId'),  // ← đảm bảo tạo mới khi session đổi
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: const ChatView(),
    );
  }
}
```

---

## 11. Safe Substring Pattern

```dart
// KHÔNG dùng substring() trực tiếp — có thể crash
text.substring(0, 60);  // ❌ crash nếu text < 60

// Luôn dùng min():
final headLen = min(500, prompt.length);
log_util.log.i('[Gemma] prompt head:\n${prompt.substring(0, headLen)}');

// Với preview:
final previewLen = min(60, chunks[i].length);
final preview = previewLen > 0 ? chunks[i].substring(0, previewLen) : '';
```

---

## 12. pubspec.yaml Conventions

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^9.1.1
  equatable: ^2.0.5
  flutter_gemma: ^0.16.4
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.x
  get_it: ^9.2.1
  go_router: ^17.3.0
  path_provider: ^2.x
  path: ^1.x
  uuid: ^4.x
  file_picker: ^8.x
  syncfusion_flutter_pdf: ^33.2.10
  flutter_markdown_plus: ^1.0.7
  scrollview_observer: ^1.27.0
  background_downloader: ^9.4.0
  collection: ^1.x
```

---

## 13. analysis_options.yaml Linter Rules

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    - always_use_package_imports
    - avoid_print
    - prefer_const_constructors
    - prefer_const_declarations
    - sort_pub_dependencies
    - unawaited_futures
    - use_super_parameters