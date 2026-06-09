# Architecture Document

## 1. Tổng quan kiến trúc

```
Flutter App
│
├── Presentation Layer  (Widgets, Pages)
├── Bloc Layer          (Business Logic)
├── Repository Layer    (Data orchestration)
├── Service Layer       (AI, Parsing, VectorStore)
└── Data Layer          (Drift/SQLite, File System)
```

Áp dụng **Clean Architecture** kết hợp **Feature-first** folder structure.

---

## 2. Data Flow chính

### Chat Flow
```
User types message
    ↓
ChatBloc.add(SendMessageEvent)
    ↓
ContextManager.buildPrompt(question, sessionId)
    ├── SessionRepository.getRecentMessages(sessionId, limit: 20)
    └── RAGRetriever.search(question, topK: 5)
    ↓
PromptBuilder.build(context, history, question)
    ↓
GemmaService.generateStream(prompt)
    ↓
ChatBloc emits ChatStreamingState(token)
    ↓
ChatPage rebuilds with new token
    ↓
[stream complete]
    ↓
MessageRepository.save(assistantMessage)
```

### RAG Ingestion Flow
```
User uploads PDF/DOCX/TXT
    ↓
KnowledgeBloc.add(ImportDocumentEvent)
    ↓
DocumentParser.parse(file) → rawText
    ↓
ChunkingEngine.chunk(rawText, size:500, overlap:100) → chunks[]
    ↓
GeckoService.embed(chunk) → vector[768]  (for each chunk)
    ↓
VectorStore.insert(chunkId, vector, chunkText)
    ↓
DocumentRepository.save(document, chunks)
    ↓
KnowledgeBloc emits IndexingCompleteState
```

### Retrieval Flow
```
User question
    ↓
GeckoService.embed(question) → queryVector
    ↓
VectorStore.search(queryVector, topK:5, threshold:0.7)
    ↓
returns RetrievedChunk[] (with score)
    ↓
ContextManager uses chunks in prompt
```

---

## 3. Layer Details

### Presentation Layer
- Chỉ chứa Widget, Page
- KHÔNG chứa business logic
- Lắng nghe Bloc state, dispatch Bloc event
- Dùng `BlocBuilder`, `BlocListener`, `BlocConsumer`

### Bloc Layer
Mỗi feature có Bloc riêng:

| Bloc | Trách nhiệm |
|------|-------------|
| `ChatBloc` | Gửi message, nhận stream response, quản lý streaming state |
| `SessionBloc` | Tạo/đổi/xóa session, load session list |
| `RAGBloc` | Trigger retrieval, trả về relevant chunks |
| `KnowledgeBloc` | Import document, index, xóa document |
| `ModelBloc` | Download model, kiểm tra model status |

### Repository Layer
- Orchestrate giữa Service và Database
- Xử lý error, convert model
- KHÔNG biết về Bloc hay Widget

### Service Layer
Services thuần, không phụ thuộc Flutter:

| Service | Trách nhiệm |
|---------|-------------|
| `GemmaService` | Wrapper flutter_gemma, generate/stream |
| `GeckoService` | Wrapper flutter_gemma EmbeddingModel, embed text → vector (KHÔNG còn tflite_flutter) |
| `VectorStoreService` | CRUD vector, cosine search trên SQLite |
| `DocumentParserService` | Parse PDF/DOCX/TXT → rawText |
| `ChunkingService` | Split text → chunks với overlap |
| `ContextManagerService` | Budget tokens, build context cho prompt |
| `PromptBuilderService` | Điền template prompt |

---

## 4. Context Manager - Chi tiết quan trọng

```dart
class ContextManagerService {
  static const int totalBudget = 8000; // tokens
  static const int ragBudget   = 4000;
  static const int historyBudget = 3000;
  static const int questionBudget = 1000;

  Future<BuiltContext> buildContext({
    required String question,
    required String sessionId,
    required List<RetrievedChunk> ragChunks,
  }) async {
    // 1. Đếm token question
    // 2. Lấy history, trim nếu > historyBudget
    // 3. Nếu history vẫn quá dài → summarize
    // 4. Ghép RAG chunks, trim nếu > ragBudget
    // 5. Return BuiltContext
  }
}
```

Token counting: dùng xấp xỉ `text.length / 4` (tiếng Anh), `text.length / 2` (tiếng Việt).

---

## 5. Vector Store - Chi tiết

Dùng SQLite, KHÔNG dùng thư viện vector database bên ngoài.

```sql
CREATE TABLE vectors (
  id TEXT PRIMARY KEY,
  chunk_id TEXT NOT NULL,
  embedding BLOB NOT NULL,  -- Float32List serialized
  created_at INTEGER NOT NULL
);
```

Cosine similarity tính trong Dart:
```dart
double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB));
}
```

HNSW không khả dụng native → dùng brute-force search với SQLite, đủ dùng cho < 50,000 chunks.

---

## 6. Dependency Injection

Dùng `get_it` package kết hợp `MultiBlocProvider` ở top-level `app.dart`:

**Nguyên tắc quan trọng:**
- **GetIt**: quản lý dependency graph (services, repositories, các bloc singleton)
- **MultiBlocProvider ở app.dart**: nắm lifecycle cho các singleton bloc → tránh Bad state do BlocProvider tự động dispose bloc khi page pop
- **ChatBloc**: là ngoại lệ — mỗi session cần 1 instance riêng, giữ `BlocProvider` ở `ChatPage` với `key: ValueKey('chat_$sessionId')`

```dart
// injection/service_locator.dart
final sl = GetIt.instance;

Future<void> setupLocator() async {
  // Services (Singleton)
  sl.registerLazySingleton<GemmaService>(() => GemmaServiceImpl());
  sl.registerLazySingleton<GeckoService>(() => GeckoRetryService(GeckoServiceImpl()));
  sl.registerLazySingleton<VectorStoreService>(() => VectorStoreServiceImpl(sl<AppDatabase>()));
  sl.registerLazySingleton<DocumentParserService>(() => DocumentParserServiceImpl());
  sl.registerLazySingleton<ChunkingService>(() => ChunkingServiceImpl());
  sl.registerLazySingleton<ContextManagerService>(() => ContextManagerService(sl(), sl()));
  sl.registerLazySingleton<PromptBuilderService>(() => PromptBuilderServiceImpl());

  // Repositories (Singleton)
  sl.registerLazySingleton<MessageRepository>(() => MessageRepositoryImpl(sl()));
  sl.registerLazySingleton<SessionRepository>(() => SessionRepositoryImpl(sl()));
  sl.registerLazySingleton<DocumentRepository>(() => DocumentRepositoryImpl(sl()));

  // Blocs
  // LazySingleton — lifecycle do MultiBlocProvider ở app.dart quản lý
  sl.registerLazySingleton<ModelBloc>(() => ModelBloc(...));
  sl.registerLazySingleton<SessionBloc>(() => SessionBloc(sl()));
  sl.registerLazySingleton<KnowledgeBloc>(() => KnowledgeBloc(sl()));
  // Factory — mỗi session cần instance riêng
  sl.registerFactory<ChatBloc>(() => ChatBloc(...));
}
```

**app.dart** triển khai `MultiBlocProvider`:
```dart
@override
Widget build(BuildContext context) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ModelBloc>(create: (_) => sl<ModelBloc>()..add(const StatusChecked())),
      BlocProvider<SessionBloc>(create: (_) => sl<SessionBloc>()..add(const SessionsLoaded())),
      BlocProvider<KnowledgeBloc>(create: (_) => sl<KnowledgeBloc>()..add(const DocumentsLoaded())),
    ],
    child: ValueListenableBuilder<ThemeMode>(...),
  );
}
```

---

## 7. Error Handling Strategy

```
AppException (base)
├── ModelNotLoadedException    → Show "Download Model" screen
├── InsufficientMemoryException → Show warning dialog
├── DocumentParseException     → Show error snackbar
├── EmbeddingException         → Show error, allow retry
└── StorageException           → Show error, log
```

Mọi lỗi đều được Bloc convert thành Error State, UI xử lý hiển thị.

---

## 8. Performance Targets

| Metric | Target |
|--------|--------|
| TTFT (Time to First Token) | < 2 giây |
| Token/s | 10-25 token/s |
| Embedding latency | < 200ms/chunk |
| Search latency (10k chunks) | < 100ms |
| App cold start | < 3 giây |

Device target: Snapdragon 8 Gen 2, Apple A17 Pro trở lên.
