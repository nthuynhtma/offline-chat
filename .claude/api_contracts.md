# API Contracts

## Services

---

### GemmaService

```dart
abstract interface class GemmaService {
  /// Initialize Gemma model.
  Future<void> initialize({String? modelPath, int maxTokens = kGemmaMaxTokens});
  bool get isReady;
  Future<void> dispose();

  /// Legacy: full prompt → new session → generate → close session.
  Stream<String> generateStream(String prompt);
  Future<String> generate(String prompt);

  /// Session-based API (turn-based, giữ session giữa các request).
  Future<void> createSession({String? systemInstruction});
  Future<void> addHistoryMessage(String role, String content);
  Stream<String> generateWithSession(String userMessage);
  Future<void> closeSession();
  bool get hasActiveSession;
}
```

Implementation: `GemmaServiceImpl` — dùng flutter_gemma 0.16.4 LiteRT-LM.

---

### GeckoService

```dart
/// Dùng flutter_gemma EmbeddingModel API (KHÔNG dùng tflite_flutter).
abstract interface class GeckoService {
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  });
  Future<void> initialize();
  bool get isReady;
  Future<void> dispose();

  /// Embed một đoạn text → vector (TaskType.retrievalQuery)
  Future<List<double>> embed(String text);

  /// Embed nhiều đoạn cùng lúc (TaskType.retrievalDocument)
  Future<List<List<double>>> embedBatch(List<String> texts);
}
```

Implementation: `GeckoServiceImpl` + `GeckoRetryService` wrapper.
FIFO lock: `_runLocked<T>(fn)` — Completer-based, tránh race GPU/FFI.

---

### RagService

```dart
abstract interface class RagService {
  Future<RagContext> retrieve({
    required String query,
    required int tokenBudget,
    required KnowledgeScope scope,
    String? sessionId,
  });
}
```

**RagContext:**
```dart
class RagContext {
  final List<SearchResult> chunks;  // try-fit packed
  final int tokenCount;
  final double? bestScore;
  bool get hasContext => chunks.isNotEmpty;
}
```

**RagServiceImpl pipeline:**
```
0. shouldSkipRag() guard → RagSkipReason (tooShort/greeting/capability)
1. Embed query → GeckoService
2. Filter completed documents theo KnowledgeScope
3. Nếu rỗng → early return RagContext.empty
4. Vector search → topK:20, threshold:0.7
5. Log candidates (top 3): score, chars, tokens, preview
6. Try-fit packing (kMaxRagChunks=3, kMaxRagTokens=500)
7. Log packing + RagTelemetry
```

VERSION=try_fit_v2

---

### VectorStoreService

```dart
abstract interface class VectorStoreService {
  Future<void> insert({required String chunkId, required List<double> embedding});
  Future<void> insertBatch(List<VectorEntry> entries);

  Future<List<SearchResult>> search({
    required List<double> queryVector,
    int topK = 5,
    double threshold = 0.7,
    Set<String>? allowedDocumentIds,  // filter trước ranking
  });

  Future<void> deleteByChunkIds(List<String> chunkIds);
  Future<int> count();
}

class VectorEntry {
  final String chunkId;
  final List<double> embedding;
}

class SearchResult {
  final String chunkId;
  final double score;       // cosine similarity [0, 1]
  final String chunkText;
}
```

Implementation: `VectorStoreServiceImpl` — SQLite brute-force cosine similarity.
2-step search: filter → preTopK(200) → cosine → re-rank → topK(20).

---

### DocumentParserService

```dart
abstract interface class DocumentParserService {
  /// Parse file về raw text. Hỗ trợ: .pdf, .docx, .txt, .md
  Future<String> parse(String filePath);
  bool isSupported(String filePath);
}
```

---

### ChunkingService

```dart
abstract interface class ChunkingService {
  /// Chia text thành chunks với sliding window.
  /// [chunkSize] tính theo xấp xỉ token (~4 ký tự = 1 token)
  /// [overlap] số token chồng lặp giữa 2 chunk liền kề
  List<String> chunk(
    String text, {
    int chunkSize = 500,
    int overlap = 100,
  });
}
```

Runtime default: chunkSize=200, overlap=50 (set trong DocumentUploadQueue).

---

### PromptBuilder

```dart
abstract interface class PromptBuilder {
  Future<String> build({
    required String question,
    required RagContext ragContext,
    required List<MessageModel> history,
    String? sessionSummary,
    List<UserMemory> userMemories,
  });
}
```

Ordering:
```
<start_of_turn>system
  You are AgriAI...
  === User Memory ===       (cross-session persona)
  === Session Summary ===   (conversation state)
<end_of_turn>

=== Recent Conversation === (history — budget-based, kMaxHistoryTokens=300)
=== Reference Documents === (RAG chunks)
=== Current Question ===
<start_of_turn>user question <end_of_turn>
<start_of_turn>model
```

VERSION=dedup_v1

---

### MemoryStoreService

```dart
abstract interface class MemoryStoreService {
  // SessionMemory
  Future<SessionMemoryRow?> getSessionMemory(String sessionId);
  Future<void> upsertSessionMemory(SessionMemoryCompanion memory);
  Future<void> updateRunningTokenCount(String sessionId, int count);

  // UserMemory
  Future<List<UserMemoryRow>> getAllUserMemories();
  Future<void> upsertUserMemory(UserMemoryCompanion memory);
}
```

### SummaryService

```dart
abstract interface class SummaryService {
  /// Incremental summarize: old summary + new messages → new summary
  Future<SummaryResult> summarize(String sessionId, {String? currentSummary, required List<MessageModel> newMessages});

  /// Extract user memory từ conversation
  Future<List<UserMemoryExtract>> extractUserMemories(List<MessageModel> messages);
}
```

---

### DocumentUploadQueue

```dart
class DocumentUploadJob {
  final String documentId;
  final String filePath;
  final String name;
  final int sizeBytes;
  final String mimeType;
  final String? sessionId;
}

class DocumentUploadResult {
  final String documentId;
  final bool success;
  final int chunkCount;
  final String? error;
}

class DocumentUploadQueue {
  QueueState get state;
  Stream<QueueState> get stateStream;
  Stream<DocumentUploadResult> get resultStream;
  int get pendingCount;

  String enqueue(DocumentUploadJob job);
  String enqueuePriority(DocumentUploadJob job);
  Future<void> retry(String documentId);
  void dispose();
}
```

Pipeline: Parse → Chunk(chunkSize=200, overlap=50) → Embed → Insert → Complete.
Granular progress 0.0→1.0 streamed qua DB + resultStream.

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
  Future<void> updateSessionKnowledgeScope(String id, KnowledgeScope scope);
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
  Future<void> updateMessageContent(String id, String content);  // for partial response
}
```

### DocumentRepository

```dart
abstract interface class DocumentRepository {
  Future<List<DocumentModel>> getAllDocuments();
  Stream<List<DocumentModel>> watchAllDocuments();
  Future<DocumentModel> importDocumentWithProgress(String filePath, {String? sessionId});
  Future<void> deleteDocument(String id);
  Future<void> reindexDocument(String id);
}
```

---

## Blocs

### ChatBloc

```
Events:
  SessionInitialized(sessionId)
  SendMessageRequested(content)
  StreamingCancelled()
  MessagesCleared()
  ModelBecameReady()
  KnowledgeScopeChanged(scope)

States:
  ChatInitial → ChatLoading → ChatLoaded | ChatThinking | ChatStreaming → ChatLoaded | ChatError
                                                    ↑ StreamingCancelled
```

### ModelBloc

```
Events:
  StatusChecked()
  GemmaDownloadStarted()
  GeckoDownloadStarted()
  DownloadCancelled(fileName)

States:
  ModelInitial → ModelLoading → ModelLoaded(gemmaInfo, geckoInfo, gemmaReady, geckoReady) → ModelError
```

### SessionBloc

```
Events: SessionsLoaded, SessionCreated, SessionDeleted, SessionTitleUpdated
States: SessionInitial, SessionLoading, SessionLoaded, SessionError
```

### KnowledgeBloc

```
Events: DocumentsLoaded, _QueueResultArrived, DocumentDeleteRequested
States: KnowledgeInitial, KnowledgeLoading, KnowledgeLoaded, KnowledgeIndexing, KnowledgeError
```

### SessionFilesCubit

```
State: SessionFilesLoaded(files, queueState, pendingCount)
Methods: detachDocument(documentId), hasProcessingFiles(files)
```

---

## Models

### SessionModel
```dart
class SessionModel {
  final String id;
  final String title;
  final KnowledgeScope knowledgeScope;  // 0/1/2
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
  final IndexStatus status;       // pending/processing/completed/failed
  final double progress;          // 0.0→1.0
  final String? errorMessage;
  final int retryCount;
  final String? sessionId;        // null = Global KB
  final DateTime createdAt;
  final DateTime? lastProcessedAt;
}
```

---

## ModelManagerService

```dart
class ModelInfo {
  final String name;
  final String fileName;
  final String downloadUrl;
  final int fileSizeBytes;
  final String? checksumSha256;
  final ModelStatus status;       // notDownloaded | downloading | downloaded | error
  final double progress;          // 0.0→1.0
  final String? errorMessage;
}

abstract interface class ModelManagerService {
  ModelInfo get gemmaInfo;
  ModelInfo get geckoInfo;
  Stream<ModelInfo> get progressStream;
  Future<void> initialize();
  Future<void> downloadGemma();
  Future<void> downloadGecko();
  Future<void> downloadGeckoTokenizer();
  Future<void> cancelDownload(String fileName);
  Future<bool> isModelFileValid(String fileName);
  Future<String> getModelPath(String fileName);
  void dispose();
}
```

Dùng `background_downloader: ^9.4.0`. TaskId = fileName. Tolerance 5MB khi verify size.
Android: Kotlin 2.1.0+, chỉ cần POST_NOTIFICATIONS.
iOS: Background Modes → Background Fetch.