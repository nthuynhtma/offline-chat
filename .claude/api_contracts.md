# API Contracts

## Services

---

### GemmaService

```dart
abstract interface class GemmaService {
  /// Khởi tạo model, load vào memory
  /// Throws [ModelNotLoadedException] nếu file không tồn tại
  Future<void> initialize(String modelPath);

  /// Check model đã load chưa
  bool get isReady;

  /// Unload model khỏi memory
  Future<void> dispose();

  /// Generate response theo kiểu streaming
  /// [prompt] là prompt hoàn chỉnh đã build sẵn
  /// Yields từng token string
  Stream<String> generateStream(String prompt);

  /// Generate toàn bộ response (non-streaming)
  Future<String> generate(String prompt);
}
```

---

### GeckoService

```dart
/// Sử dụng flutter_gemma EmbeddingModel API (KHÔNG dùng tflite_flutter Interpreter).
/// flutter_gemma tự quản lý tokenizer (SentencePiece) + inference + normalization.
abstract interface class GeckoService {
  /// Đăng ký model + tokenizer với flutter_gemma qua installEmbedder().
  /// Gọi 1 lần sau khi cả 2 file đã được download xuống disk.
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  });

  /// Initialize embedding model lấy từ FlutterGemma.getActiveEmbedder().
  /// Không cần path — flutter_gemma tự quản lý.
  Future<void> initialize();

  bool get isReady;

  Future<void> dispose();

  /// Embed một đoạn text → vector (query mode, TaskType.retrievalQuery)
  Future<List<double>> embed(String text);

  /// Embed nhiều đoạn cùng lúc (batch, document mode TaskType.retrievalDocument)
  Future<List<List<double>>> embedBatch(List<String> texts);
}
```

---

### VectorStoreService

```dart
abstract interface class VectorStoreService {
  /// Lưu vector cho một chunk
  Future<void> insert({
    required String chunkId,
    required List<double> embedding,
  });

  /// Lưu nhiều vectors cùng lúc
  Future<void> insertBatch(List<VectorEntry> entries);

  /// Tìm top-K chunks gần nhất với queryVector
  /// Chỉ trả về kết quả có score >= threshold
  Future<List<SearchResult>> search({
    required List<double> queryVector,
    int topK = 5,
    double threshold = 0.7,
  });

  /// Xóa vectors theo danh sách chunk IDs
  Future<void> deleteByChunkIds(List<String> chunkIds);

  /// Tổng số vectors
  Future<int> count();
}

class VectorEntry {
  final String chunkId;
  final List<double> embedding;
  const VectorEntry({required this.chunkId, required this.embedding});
}

class SearchResult {
  final String chunkId;
  final double score;       // cosine similarity [0, 1]
  final String chunkText;   // đã join từ Chunks table
  const SearchResult({
    required this.chunkId,
    required this.score,
    required this.chunkText,
  });
}
```

---

### DocumentParserService

```dart
abstract interface class DocumentParserService {
  /// Parse file về raw text
  /// Hỗ trợ: .pdf, .docx, .txt, .md
  /// Throws [DocumentParseException] nếu không parse được
  Future<String> parse(String filePath);

  /// Check file type có support không
  bool isSupported(String filePath);
}
```

---

### ChunkingService

```dart
abstract interface class ChunkingService {
  /// Chia text thành chunks với sliding window
  /// [chunkSize] tính theo xấp xỉ token (~4 ký tự = 1 token)
  /// [overlap] số token chồng lặp giữa 2 chunk liền kề
  List<String> chunk(
    String text, {
    int chunkSize = 500,
    int overlap = 100,
  });
}
```

---

### ContextManagerService

```dart
abstract interface class ContextManagerService {
  static const int totalBudget = 8000;
  static const int ragBudget   = 4000;
  static const int historyBudget = 3000;
  static const int questionBudget = 1000;

  /// Build context từ RAG results + conversation history
  Future<BuiltContext> buildContext({
    required String question,
    required String sessionId,
    required List<SearchResult> ragResults,
  });
}

class BuiltContext {
  final String question;
  final List<SearchResult> relevantChunks;
  final List<MessageModel> history;
  final bool historyWasTrimmed;
  final int estimatedTokens;

  const BuiltContext({
    required this.question,
    required this.relevantChunks,
    required this.history,
    required this.historyWasTrimmed,
    required this.estimatedTokens,
  });
}
```

---

### PromptBuilderService

```dart
abstract interface class PromptBuilderService {
  /// Build prompt hoàn chỉnh từ context
  String build(BuiltContext context);
}
```

Template mặc định:
```
<start_of_turn>system
You are a helpful assistant. Answer in the same language as the user's question.
{% if context.relevantChunks.isNotEmpty %}
Use the following context to answer:

{relevant_chunks}
{% endif %}
<end_of_turn>
{% for message in context.history %}
<start_of_turn>{{ message.role }}
{{ message.content }}<end_of_turn>
{% endfor %}
<start_of_turn>user
{{ question }}<end_of_turn>
<start_of_turn>model
```

---

## Repositories

### SessionRepository

```dart
abstract interface class SessionRepository {
  Future<List<SessionModel>> getAllSessions();
  Stream<List<SessionModel>> watchAllSessions();
  Future<SessionModel?> getSessionById(String id);
  Future<SessionModel> createSession({String? title});
  Future<void> updateSessionTitle(String id, String title);
  Future<void> deleteSession(String id);
  Future<void> updateSessionTimestamp(String id);
}
```

### MessageRepository

```dart
abstract interface class MessageRepository {
  Future<List<MessageModel>> getMessages(String sessionId);
  Future<List<MessageModel>> getRecentMessages(String sessionId, {int limit = 20});
  Stream<List<MessageModel>> watchMessages(String sessionId);
  Future<MessageModel> saveMessage({
    required String sessionId,
    required MessageRole role,
    required String content,
  });
  Future<void> deleteMessagesBySession(String sessionId);
}
```

### DocumentRepository

```dart
abstract interface class DocumentRepository {
  Future<List<DocumentModel>> getAllDocuments();
  Stream<List<DocumentModel>> watchAllDocuments();
  Future<DocumentModel> importDocument(String filePath);
  Future<void> deleteDocument(String id);
  Future<void> reindexDocument(String id);
}
```

---

## Blocs

### ChatBloc

```
Events:
  SessionInitialized(sessionId)     → load messages, set active session
  SendMessageRequested(content)     → gửi message, stream response
  StreamingCancelled()              → cancel stream
  MessagesCleared()                 → xóa toàn bộ messages của session

States:
  ChatInitial
  ChatLoading
  ChatLoaded(messages: List<MessageModel>)
  ChatStreaming(messages: List<MessageModel>, streamingText: String, streamingId: String)
  ChatError(message: String, needsModelDownload: bool)
```

### SessionBloc

```
Events:
  SessionsLoaded()           → load danh sách sessions
  SessionCreated()           → tạo session mới
  SessionSelected(id)        → chọn session
  SessionDeleted(id)         → xóa session
  SessionTitleUpdated(id, title)

States:
  SessionInitial
  SessionLoading
  SessionLoaded(sessions: List<SessionModel>, activeSessionId: String?)
  SessionError(message: String)
```

### KnowledgeBloc

```
Events:
  DocumentsLoaded()
  DocumentImportRequested(filePath)
  DocumentDeleteRequested(id)
  DocumentReindexRequested(id)

States:
  KnowledgeInitial
  KnowledgeLoading
  KnowledgeLoaded(documents: List<DocumentModel>)
  KnowledgeIndexing(documentId: String, progress: double)  // 0.0 - 1.0
  KnowledgeError(message: String)
```

### ModelBloc

```
Events:
  StatusChecked()                        → kiểm tra trạng thái model files
  GemmaDownloadStarted()                 → bắt đầu download Gemma
  GeckoDownloadStarted()                 → bắt đầu download Gecko + tokenizer
  DownloadCancelled(fileName)            → huỷ download 1 file

States:
  ModelInitial
  ModelLoading
  ModelLoaded(gemmaInfo, geckoInfo, gemmaReady: bool, geckoReady: bool)
  ModelError(message: String)
```

---

## Models

### SessionModel
```dart
class SessionModel {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### MessageModel
```dart
class MessageModel {
  final String id;
  final String sessionId;
  final MessageRole role;   // user | assistant | system
  final String content;
  final DateTime createdAt;
}
```

### DocumentModel
```dart
class DocumentModel {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final int chunkCount;
  final String mimeType;
  final DateTime createdAt;
}
```

### ChunkModel
```dart
class ChunkModel {
  final String id;
  final String documentId;
  final String chunkText;
  final int chunkIndex;
  final int tokenCount;
}
```

---

## ModelManagerService (background_downloader)

```dart
// pubspec.yaml
// background_downloader: ^9.4.0

/// ModelInfo: data class chứa trạng thái của 1 model file.
/// Dùng cho cả Gemma, Gecko model và Gecko tokenizer.
class ModelInfo {
  final String name;              // tên hiển thị
  final String fileName;          // tên file trên disk
  final String downloadUrl;       // URL download
  final int fileSizeBytes;        // kích thước mong đợi
  final String? checksumSha256;
  final ModelStatus status;       // notDownloaded | downloading | downloaded | error
  final double progress;          // 0.0 - 1.0
  final String? errorMessage;
}

abstract interface class ModelManagerService {
  /// Lấy thông tin model Gemma
  ModelInfo get gemmaInfo;

  /// Lấy thông tin model Gecko
  ModelInfo get geckoInfo;

  /// Stream cập nhật progress download (broadcast, replay state cuối khi subscribe)
  Stream<ModelInfo> get progressStream;

  /// Khởi tạo FileDownloader, config notification, kiểm tra file có sẵn
  Future<void> initialize();

  /// Bắt đầu download Gemma model (no-op nếu đang chạy)
  Future<void> downloadGemma();

  /// Bắt đầu download Gecko model (no-op nếu đang chạy)
  Future<void> downloadGecko();

  /// Bắt đầu download tokenizer SentencePiece cho Gecko
  Future<void> downloadGeckoTokenizer();

  /// Huỷ download của đúng file được chỉ định
  Future<void> cancelDownload(String fileName);

  /// Kiểm tra file đã tồn tại và kích thước hợp lệ không
  Future<bool> isModelFileValid(String fileName);

  /// Đường dẫn đầy đủ tới model file trên disk
  Future<String> getModelPath(String fileName);

  /// Giải phóng resource
  void dispose();
}
```

### Implementation (ModelManagerServiceImpl)

Triển khai trong `lib/services/model_manager/model_manager_service.dart`. Dùng `background_downloader` (FileDownloader) để download:
- **allowPause: true** — giải quyết Android 9-min WorkManager limit
- **Broadcast StreamController** — cho phép nhiều listener subscribe
- **Cache state cuối** — replay cho subscriber mới (tương tự BehaviorSubject)
- **taskId = fileName** — để background_downloader nhận diện và resume đúng task
- **Tolerance 5MB** — khi verify file size sau download
- **downloadGeckoTokenizer()** — download SentencePiece model (~4MB) cho Gecko

Xem code thực tế tại `lib/services/model_manager/model_manager_service.dart`.

### pubspec.yaml cần thêm

```yaml
dependencies:
  background_downloader: ^9.4.0
```

### Android setup

**Kotlin version** — bắt buộc Kotlin 2.1.0+ (android/settings.gradle):
```groovy
plugins {
    id "org.jetbrains.kotlin.android" version "2.1.0" apply false
}
```

**AndroidManifest.xml** — chỉ cần notification permission:
```xml
<!-- Chỉ cần POST_NOTIFICATIONS để hiện notification trên Android 13+ -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<!-- KHÔNG cần FOREGROUND_SERVICE nếu dùng allowPause: true thay vì runInForeground -->
```

### iOS setup

Trong XCode → Runner target → Signing & Capabilities → thêm **Background Modes** → tick **Background Fetch**.

Hoặc trực tiếp trong `ios/Runner/Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
</array>
```

> **Lưu ý**: Không cần `flutter_local_notifications`. `background_downloader` tự quản lý notification channel, không conflict với bất kỳ package nào khác.
