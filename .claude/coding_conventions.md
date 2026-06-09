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
  class MessageRepository {}
```

### Variables & Methods
```dart
camelCase:
  final String sessionId;
  void sendMessage(String content) {}
  Stream<String> generateStream(String prompt) async* {}
```

### Constants
```dart
// Trong class
static const int maxHistoryMessages = 20;
static const double similarityThreshold = 0.7;

// Top-level constants trong constants/
const String kGemmaModelFileName = 'gemma4b-it.litertlm';
const String kGeckoModelFileName = 'gecko-110m.tflite';
```

---

## 2. Bloc Pattern - Bắt buộc

### Event naming
```dart
// Dùng verb + noun, past tense cho events
class MessageSent extends ChatEvent {}        // ✅
class SendMessage extends ChatEvent {}        // ❌ (là command, không phải event)
class ChatMessageSentEvent extends ChatEvent {} // ❌ (thừa chữ Event)

// Nhưng một số team dùng command style, chọn 1 style và đồng nhất:
sealed class ChatEvent {}
class SendMessageRequested extends ChatEvent {
  final String content;
  const SendMessageRequested(this.content);
}
class SessionChanged extends ChatEvent {
  final String sessionId;
  const SessionChanged(this.sessionId);
}
class StreamingCancelled extends ChatEvent {}
```

### State naming
```dart
sealed class ChatState {}
class ChatInitial extends ChatState {}
class ChatLoading extends ChatState {}
class ChatStreaming extends ChatState {
  final String currentText;
  final String messageId;
  const ChatStreaming({required this.currentText, required this.messageId});
}
class ChatLoaded extends ChatState {
  final List<MessageModel> messages;
  const ChatLoaded(this.messages);
}
class ChatError extends ChatState {
  final String message;
  const ChatError(this.message);
}
```

### Bloc implementation
```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MessageRepository _messageRepo;
  final ContextManagerService _contextManager;
  final GemmaService _gemmaService;

  ChatBloc(this._messageRepo, this._contextManager, this._gemmaService)
      : super(ChatInitial()) {
    on<SendMessageRequested>(_onSendMessageRequested);
    on<StreamingCancelled>(_onStreamingCancelled);
  }

  Future<void> _onSendMessageRequested(
    SendMessageRequested event,
    Emitter<ChatState> emit,
  ) async {
    try {
      // 1. Save user message
      // 2. Build context
      // 3. Stream response
      String accumulated = '';
      await emit.forEach(
        _gemmaService.generateStream(prompt),
        onData: (token) {
          accumulated += token;
          return ChatStreaming(
            currentText: accumulated,
            messageId: assistantMsgId,
          );
        },
      );
      // 4. Save assistant message
      await _messageRepo.saveMessage(...);
      emit(ChatLoaded(await _messageRepo.getMessages(sessionId)));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }
}
```

---

## 3. Repository Pattern

```dart
// Abstract interface
abstract interface class MessageRepository {
  Future<List<MessageModel>> getMessages(String sessionId);
  Future<List<MessageModel>> getRecentMessages(String sessionId, {int limit = 20});
  Future<void> saveMessage(MessageModel message);
  Future<void> deleteMessagesBySession(String sessionId);
  Stream<List<MessageModel>> watchMessages(String sessionId);
}

// Implementation
class MessageRepositoryImpl implements MessageRepository {
  final MessagesDao _dao;
  MessageRepositoryImpl(this._dao);

  @override
  Future<List<MessageModel>> getMessages(String sessionId) async {
    final rows = await _dao.getMessagesBySession(sessionId);
    return rows.map(MessageModel.fromDbRow).toList();
  }
  // ...
}
```

---

## 4. Model Classes

```dart
// Dùng freezed hoặc plain Dart, KHÔNG dùng json_serializable nếu không cần API
class MessageModel {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  // Convert từ DB row
  factory MessageModel.fromDbRow(Message row) => MessageModel(
    id: row.id,
    sessionId: row.sessionId,
    role: row.role,
    content: row.content,
    createdAt: row.createdAt,
  );

  // copyWith
  MessageModel copyWith({String? content}) => MessageModel(
    id: id,
    sessionId: sessionId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
  );
}
```

---

## 5. Error Handling

```dart
// Định nghĩa exceptions rõ ràng
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);
}

class ModelNotLoadedException extends AppException {
  const ModelNotLoadedException() : super('AI model chưa được tải. Vui lòng tải model trước.');
}

class InsufficientMemoryException extends AppException {
  final int requiredMB;
  const InsufficientMemoryException(this.requiredMB)
      : super('Không đủ RAM. Cần ít nhất ${requiredMB}MB trống.');
}

class DocumentParseException extends AppException {
  const DocumentParseException(String msg) : super(msg);
}

// Trong bloc, bắt và convert
} catch (e) {
  if (e is ModelNotLoadedException) {
    emit(ChatError(needsModelDownload: true, message: e.message));
  } else {
    emit(ChatError(message: e.toString()));
  }
}
```

---

## 6. Async/Stream Guidelines

```dart
// ✅ Dùng emit.forEach cho stream trong Bloc
await emit.forEach(
  _gemmaService.generateStream(prompt),
  onData: (token) => ChatStreaming(currentText: token),
  onError: (error, _) => ChatError(error.toString()),
);

// ✅ Dùng async* cho service methods trả về Stream
Stream<String> generateStream(String prompt) async* {
  final stream = _gemmaModel.generateStream(prompt);
  await for (final response in stream) {
    yield response.text;
  }
}

// ❌ KHÔNG dùng StreamController nếu có thể dùng async*
// ❌ KHÔNG forget await khi gọi async method
```

---

## 7. BlocProvider Pattern — QUAN TRỌNG

### Singleton Blocs (ModelBloc, SessionBloc, KnowledgeBloc)

**KHÔNG** tạo `BlocProvider` trong page. Gom tất cả ở **`app.dart`** dùng `MultiBlocProvider`:

```dart
// app.dart
@override
Widget build(BuildContext context) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ModelBloc>(create: (_) => sl<ModelBloc>()..add(const StatusChecked())),
      BlocProvider<SessionBloc>(create: (_) => sl<SessionBloc>()..add(const SessionsLoaded())),
      BlocProvider<KnowledgeBloc>(create: (_) => sl<KnowledgeBloc>()..add(const DocumentsLoaded())),
      // KHÔNG có ChatBloc ở đây — mỗi session 1 instance riêng
    ],
    child: ValueListenableBuilder<ThemeMode>(...),
  );
}
```

Page chỉ cần `const` widget, không wrapper:
```dart
class ModelManagerPage extends StatelessWidget {
  const ModelManagerPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const _ModelManagerView();
  }
}

class SessionListPage extends StatelessWidget {
  const SessionListPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const SessionListView();
  }
}

class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key});
  @override
  Widget build(BuildContext context) {
    return const KnowledgeView();
  }
}
```

**Lý do:** Tránh `Bad state` khi GetIt singleton bị BlocProvider dispose.

### Factory Blocs (ChatBloc — mỗi session 1 instance)

Giữ `BlocProvider` ở page, nhưng thêm `key`:
```dart
class ChatPage extends StatelessWidget {
  final String sessionId;
  const ChatPage({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey('chat_$sessionId'), // ← đảm bảo tạo mới khi session đổi
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: ChatView(sessionId: sessionId),
    );
  }
}
```

---

## 8. Import Order (enforce với linter)

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:typed_data';

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Pub packages
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:drift/drift.dart';

// 4. Local imports (absolute)
import 'package:offline_chat/core/constants/app_constants.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
```

---

## 9. pubspec.yaml Dependencies

```yaml
name: offline_chat
description: Offline AI Chat with RAG
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_bloc: ^8.1.6
  equatable: ^2.0.5

  # AI
  flutter_gemma: ^0.16.4
  # tflite_flutter: ^0.12.1  ← Gecko embedding đã migrate sang flutter_gemma EmbeddingModel API
  # Chỉ giữ tflite_flutter nếu cần cho mục đích khác ngoài Gecko

  # Database
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0

  # DI
  get_it: ^7.7.0

  # File Parsing
  syncfusion_flutter_pdf: ^26.1.35
  path_provider: ^2.1.3
  path: ^1.9.0
  uuid: ^4.4.0
  file_picker: ^8.0.0+1

  background_downloader: ^9.4.0

  # Utils
  collection: ^1.18.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.18.0
  build_runner: ^2.4.11
  flutter_lints: ^4.0.0
```

---

## 10. analysis_options.yaml

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
```
