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
abstract interface class GeckoService {
  /// Load Gecko TFLite model
  Future<void> initialize(String modelPath);

  bool get isReady;

  Future<void> dispose();

  /// Embed một đoạn text → vector 768 chiều
  Future<List<double>> embed(String text);

  /// Embed nhiều đoạn cùng lúc (batch)
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
  ModelStatusChecked()
  GemmaDownloadStarted()
  GeckoDownloadStarted()
  DownloadCancelled()

States:
  ModelInitial
  ModelChecking
  ModelReady(gemmaVersion: String, geckoVersion: String)
  ModelNotReady(gemmaAvailable: bool, geckoAvailable: bool)
  ModelDownloading(modelName: String, progress: double, bytesDownloaded: int, totalBytes: int)
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

abstract interface class ModelManagerService {
  /// Khởi tạo FileDownloader, config notification
  Future<void> initialize();

  /// Check xem model file đã tồn tại và hợp lệ chưa
  Future<ModelFileStatus> checkStatus(ModelType model);

  /// Bắt đầu download (background, resume-capable)
  /// Trả về Stream để theo dõi progress
  Stream<DownloadProgressEvent> download(ModelType model);

  /// Pause download đang chạy
  Future<void> pause(ModelType model);

  /// Resume download đã pause
  Future<void> resume(ModelType model);

  /// Cancel và xóa partial file
  Future<void> cancel(ModelType model);

  /// Xóa model file đã download
  Future<void> delete(ModelType model);
}

enum ModelType { gemma, gecko }

class ModelFileStatus {
  final ModelType model;
  final bool exists;
  final bool checksumValid;
  final int? fileSizeBytes;
  const ModelFileStatus({
    required this.model,
    required this.exists,
    required this.checksumValid,
    this.fileSizeBytes,
  });
}

class DownloadProgressEvent {
  final ModelType model;
  final double progress;        // 0.0 - 1.0
  final int bytesDownloaded;
  final int totalBytes;
  final DownloadStatus status;  // running | paused | complete | failed
  final String? error;
  const DownloadProgressEvent({
    required this.model,
    required this.progress,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.status,
    this.error,
  });
}

enum DownloadStatus { running, paused, complete, failed, cancelled }
```

### Implementation quan trọng

```dart
class ModelManagerServiceImpl implements ModelManagerService {
  static const _gemmaUrl = 'YOUR_GEMMA_DOWNLOAD_URL'; // Hugging Face hoặc CDN
  static const _geckoUrl = 'YOUR_GECKO_DOWNLOAD_URL';

  @override
  Future<void> initialize() async {
    // KHÔNG cần flutter_local_notifications — background_downloader có
    // built-in notification system, không cần package nào thêm.
    //
    // Config notification hiện lên khi app background:
    FileDownloader().configureNotification(
      running: const TaskNotification(
        'Đang tải model AI',
        'Tiến trình: {progress}%',
      ),
      paused: const TaskNotification('Tạm dừng', 'Nhấn để tiếp tục'),
      complete: const TaskNotification('Hoàn thành', 'Model đã sẵn sàng'),
      error: const TaskNotification('Lỗi', 'Không thể tải model'),
      tapOpensFile: false,
    );
    // Gọi start() để kích hoạt persistent database và đảm bảo
    // task tiếp tục sau khi app bị kill/suspend
    await FileDownloader().start();
  }

  @override
  Stream<DownloadProgressEvent> download(ModelType model) async* {
    final controller = StreamController<DownloadProgressEvent>();
    final url = model == ModelType.gemma ? _gemmaUrl : _geckoUrl;
    final filename = model == ModelType.gemma
        ? 'gemma4b-it.litertlm'
        : 'gecko-110m.tflite';

    final task = DownloadTask(
      url: url,
      filename: filename,
      directory: 'models',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
      allowPause: true,   // ← QUAN TRỌNG: giải quyết Android 9-min limit
                          // khi timeout, task tự pause rồi tự resume
      retries: 3,
      requiresWiFi: false,
      // Android 14+: priority 0 → dùng UIDT service, không bị 9-min limit
      // priority: 0,  // bỏ comment nếu muốn target Android 14+ specifically
    );

    await FileDownloader().download(
      task,
      onProgress: (progress) {
        controller.add(DownloadProgressEvent(
          model: model,
          progress: progress,
          bytesDownloaded: (progress * _totalBytes(model)).toInt(),
          totalBytes: _totalBytes(model),
          status: DownloadStatus.running,
        ));
      },
      onStatus: (status) {
        if (status == TaskStatus.complete) {
          controller.add(DownloadProgressEvent(
            model: model, progress: 1.0,
            bytesDownloaded: _totalBytes(model),
            totalBytes: _totalBytes(model),
            status: DownloadStatus.complete,
          ));
          controller.close();
        } else if (status == TaskStatus.failed) {
          controller.addError('Download failed');
          controller.close();
        } else if (status == TaskStatus.paused) {
          controller.add(DownloadProgressEvent(
            model: model, progress: -1,
            bytesDownloaded: 0, totalBytes: _totalBytes(model),
            status: DownloadStatus.paused,
          ));
        }
      },
    );

    yield* controller.stream;
  }

  int _totalBytes(ModelType model) => model == ModelType.gemma
      ? 2_800_000_000  // ~2.8GB
      : 440_000_000;   // ~440MB
}
```

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
