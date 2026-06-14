# Architecture Document

## 1. Tổng quan kiến trúc

```
Flutter App
│
├── Presentation Layer  (Widgets, Pages)
├── Bloc Layer          (Business Logic + State Management)
├── Service Layer       (AI, RAG, Parsing, VectorStore, Memory, BM25, ModelManager)
└── Data Layer          (Drift/SQLite — DAOs, Tables + SharedPreferences)
```

Áp dụng **Clean Architecture** kết hợp **Feature-first** folder structure.
Business logic tập trung trong Bloc, không dùng setState. Services thuần, không biết về UI.

**Chú ý:** Không còn Repository Layer riêng — MessageRepository và SessionRepository đơn giản, chỉ là wrapper DAO. DocumentRepository xử lý import + enqueue queue. Các service gọi DAO trực tiếp khi cần.

---

## 2. App Initialization Flow

```dart
// main.dart
main()
  ├── WidgetsFlutterBinding.ensureInitialized()
  ├── SystemChrome.setPreferredOrientations([portraitUp])
  ├── FlutterError.onError (global Flutter error handler)
  ├── ui.PlatformDispatcher.instance.onError (global async error handler)
  ├── [NEW] Detect device capability → DeviceCapability.detectTier()
  │     ├── Android: đọc physicalRamSize (MB) → convert GB
  │     ├── iOS: infer từ model name (iPhone15,2 = high, iPhone14 = medium, ...)
  │     └── Lưu contextWindow vào DeviceCapabilityHolder.contextWindow
  │         high (≥8GB)=4096, medium (6GB)=2048, low (≤4GB)=1024
  ├── FlutterGemma.initialize()
  ├── await setupLocator()           // DI registration (GetIt)
  ├── [UPDATED] sl<GemmaService>().initialize(maxTokens: contextWindow)
  │     └── Graceful: nếu chưa có model, không crash — chỉ log + _model = null
  │         ModelBloc sẽ init sau khi model được download.
  └── runApp(const App())
```

### setupLocator() — DI Registration (GetIt)

**Services (LazySingleton):**
| Service | Implementation | Deps |
|---------|---------------|------|
| `AppDatabase` | Drift SQLite | — |
| `ModelManagerService` | `ModelManagerServiceImpl` | — |
| `GemmaService` | `GemmaServiceImpl` | — |
| `GeckoService` | `GeckoRetryService(GeckoServiceImpl)` | — |
| `PromptBuilder` | `PromptBuilderImpl` | — |
| `RagService` | `RagServiceImpl` | AppDatabase, GeckoService, VectorStoreService, **Bm25Service** |
| `Bm25Service` | `Bm25ServiceImpl` | AppDatabase |
| `ChunkingService` | `ChunkingServiceImpl` | — |
| `DocumentParserService` | `DocumentParserServiceImpl` | — |
| `VectorStoreService` | `VectorStoreServiceImpl` | AppDatabase |
| `MemoryStoreService` | `MemoryStoreService` | AppDatabase |
| `SummaryService` | `SummaryService` | GemmaService, MemoryStoreService |
| `SemanticCacheService` | `SemanticCacheServiceImpl` | — |
| `ExportSessionService` | `ExportSessionServiceImpl` | — |
| `ContextManagerService` | `@Deprecated` | Giữ lại tránh break build |

**Blocs:**
| Bloc | Scope | Deps |
|------|-------|------|
| `ModelBloc` | LazySingleton | ModelManagerService, GemmaService, GeckoService |
| `SessionBloc` | LazySingleton | SessionRepository |
| `KnowledgeBloc` | LazySingleton | DocumentRepository, DocumentUploadQueue |
| `SessionFilesCubit` | LazySingleton | DocumentsDao, SessionDocumentRefsDao, DocumentUploadQueue |
| `ChatBloc` | **Factory** (mỗi session 1 instance) | MessageRepo, SessionRepo, GemmaService, ModelBloc, MemoryStore, SummaryService, RagService, PromptBuilder |

**Upload Queue:**
| Component | Scope | Deps |
|-----------|-------|------|
| `DocumentUploadQueue` | LazySingleton | DocsDao, ChunksDao, Parser, Chunker, Gecko, VectorStore, **Bm25Service** |
| `DocumentRepository` | LazySingleton | AppDatabase, DocumentUploadQueue |

**Utils:**
| Component | Scope | Mục đích |
|-----------|-------|----------|
| `DeviceCapability` | Static class | Detect device tier, tính contextWindow động |
| `DeviceCapabilityHolder` | Static class (model_constants.dart) | Lưu contextWindow runtime |

**Model Registry (NEW):**
| Component | File | Mục đích |
|-----------|------|----------|
| `AvailableModelInfo` | `model_constants.dart` | Danh sách LLM models có sẵn (Qwen2.5 + Gemma) |
| `kAvailableLlmModels` | `model_constants.dart` | Const list các model có thể tải |
| `ModelType` enum | `model_manager_service.dart` | `llm` / `embedding` |

---

## 3. App Widget Tree

```
app.dart — _AppState
  ├── GlobalKey<NavigatorState> _navigatorKey
  ├── GoRouter (navigatorKey)
  │    ├── /            → SessionListPage
  │    ├── /chat/:id    → ChatPage(sessionId)  [BlocProvider<ChatBloc>(key)]
  │    ├── /knowledge   → KnowledgePage
  │    ├── /settings    → SettingsPage (updated: model selector + available models)
  │    └── /settings/models → ModelManagerPage (dynamic LLM list + radio active)
  └── ValueListenableBuilder<ThemeMode> (themeModeNotifier)
       └── MaterialApp.router
            ├── builder: (context, child) → ModelOnboardingCoordinator(navigatorKey, child)
            ├── theme:  Material3 Light
            └── darkTheme: Material3 Dark

MultiBlocProvider (App level — 4 singleton blocs):
  ├── ModelBloc      (dispatch StatusChecked ngay khi tạo)
  ├── SessionBloc    (dispatch SessionsLoaded ngay khi tạo)
  ├── KnowledgeBloc  (dispatch DocumentsLoaded ngay khi tạo)
  └── SessionFilesCubit
```

Việc đặt singleton blocs trong `MultiBlocProvider` ở App level (thay vì GetIt lifecycle) đảm bảo Bloc không bị dispose khi page pop (lỗi thường gặp với GetIt~Bloc).

---

## 4. Data Flow — Chat

### ChatBloc States
```
ChatInitial → ChatLoading → ChatLoaded | ChatThinking | ChatStreaming → ChatLoaded | ChatError
                                                    ↑ Stop
                                                    StreamingCancelled → ChatLoaded
```

| State | Fields | Description |
|-------|--------|-------------|
| `ChatInitial` | — | Chưa load session |
| `ChatLoading` | — | Đang load messages từ DB |
| `ChatLoaded` | messages, knowledgeScope | Sẵn sàng nhận input |
| `ChatThinking` | messages, knowledgeScope | User msg saved, chờ RAG + prompt |
| `ChatStreaming` | messages, streamingText, streamingId, ragResults?, knowledgeScope | Đang streaming từng token |
| `ChatError` | message, needsModelDownload, messages, knowledgeScope | Lỗi (có thể kèm needsModelDownload flag) |

### ChatBloc Events
| Event | Trigger | Effect |
|-------|---------|--------|
| `SessionInitialized(sessionId)` | ChatPage mount | Load messages, hydrate KnowledgeScope, tạo Gemma session + replay history |
| `SendMessageRequested(content)` | Send button | RAG → Build prompt → Stream response |
| `StreamingCancelled` | Stop button | Save "(Đã dừng)" partial response |
| `MessagesCleared` | Clear button | Delete messages |
| `ModelBecameReady` | ModelBloc ready | Clear needsModelDownload error |
| `KnowledgeScopeChanged(scope)` | Scope selector | Update session scope |

### ChatBloc Constructor Dependencies
```dart
ChatBloc({
  required MessageRepository messageRepo,
  required SessionRepository sessionRepo,
  required GemmaService gemmaService,
  required ModelBloc modelBloc,
  required MemoryStoreService memoryStore,
  required SummaryService summaryService,
  required RagService ragService,
  required PromptBuilder promptBuilder,
  int? contextWindow,   // [NEW] từ DeviceCapabilityHolder.contextWindow
})
```

### SendMessage Full Flow (Session API + Dynamic Budget, updated 14/06/2026)
```
1. Guard checks: isClosed? _currentSessionId? is ChatStreaming? _isWaitingForModel?
2. If gemma not ready:
      → ModelLoaded: kiểm tra active model đã download chưa (modelState.llmModels + activeLlmFileName)
      → Nếu đã download nhưng chưa ready: subscribe ModelBloc, _isWaitingForModel=true
      → Nếu chưa download: emit ChatError(needsModelDownload=true)
3. Save user message → DB → emit ChatThinking
4. [NEW] Dynamic Budget: ContextBudget.forQuery(content) → phân bổ tokens
5. RAG retrieval → RagService.retrieve(query, tokenBudget, scope, sessionId)
6. Build turn payload → PromptBuilder.buildTurnPayload(question, ragContext)
7. Ensure Gemma session exists (recreate via _recreateSession() if lost)
8. Stream → emit.forEach(gemmaService.generateWithSession(turnPayload))
```

### Session Initialization Flow (Session API, updated 14/06/2026)
```
SessionInitialized(sessionId)
  ├→ emit ChatLoading
  ├→ load messages từ SQLite
  ├→ hydrate KnowledgeScope từ session DB
  ├→ Nếu !gemmaService.isReady → skip session creation, load messages only
  ├→ Kiểm tra SessionMemory (summary)
  │    ├→ Có summary → MemoryPromptFormatter.build(summary, memories) → createSession(systemInstruction)
  │    └→ Không summary → PromptBuilder.buildSystemInstruction(memories) → createSession(systemInstruction)
  ├→ [CHỈ 1 LẦN] Replay history (token-based, 35% context — kSessionInitHistoryRatio)
  └→ emit ChatLoaded
```

---

## 5. Data Flow — RAG Ingestion

```
User uploads file (ChatPage 📎 or Knowledge Page)
  └→ FilePicker (pdf, docx, txt, md, allowMultiple)
       └→ insertDocument(status=pending)
            └→ DocumentUploadQueue.enqueue(job)

FIFO _processNext() → _processJob():
  Parse    0.00 → 0.10    DocumentParserService.parse(file) → rawText
  Chunk    0.10 → 0.20    ChunkingService.chunk(rawText, chunkSize=200, overlap=50) → chunks[]
  Embed    0.20 → 0.95    GeckoService.embed(chunk) → vector[768] (per chunk, progressive %)
  Insert   0.95 → 1.00    ChunksCompanion batch → Vectors insert batch
  Index BM25              → Bm25Service.indexChunks() → FTS5 chunks_fts table
  Complete 1.00            status=completed, chunkCount updated
```

---

## 6. Data Flow — RAG Retrieval

```
RagService.retrieve(query, tokenBudget, scope, sessionId):
  0. Early exit guard: _shouldSkipRag() → RagSkipReason enum
  1. Embed query → GeckoService.embed(query)
  2. Filter document IDs theo KnowledgeScope (CHỈ status=completed)
  3. Nếu allowedDocIds rỗng → early return RagContext.empty
  4. Dense search → VectorStoreService.search(topK:50, threshold:0.7, allowedDocIds)
  5. Sparse search → Bm25Service.search(query, allowedDocIds, topK:50)
  6. Reciprocal Rank Fusion (RRF, k=60) hoặc fallback
  7. Try-fit packing (VERSION=try_fit_v2)
  8. Log RagTelemetry
Return: RagContext(chunks, tokenCount, bestScore)
```

---

## 7. Data Flow — Prompt Building (updated 14/06/2026)

PromptBuilder hiện có 2 methods riêng biệt (VERSION=session_api_v1):

### buildSystemInstruction() — cho createSession()
```
CHỈ chứa system + memories + summary. KHÔNG chứa history.
  <start_of_turn>system
    You are AgriAI...
    === User Memory ===       (cross-session persona)
    === Session Summary ===   (conversation state)
  <end_of_turn>
```

### buildTurnPayload() — cho generateWithSession()
```
CHỈ chứa RAG + question. KHÔNG chứa system/history.
  === Reference Documents === (RAG chunks — nếu có)
  === Current Question ===
```

### Legacy build() (VERSION=dedup_v1)
Giữ lại cho SummaryService (dùng generateStream legacy). KHÔNG dùng cho chat turns.

---

## 8. Core Services

### GemmaService (flutter_gemma 0.16.4)
```
API: Session-based (turn-based chat)
  createSession(systemInstruction?) → addHistoryMessage(role, content)
  → generateWithSession(userMessage) → Stream<String>

maxTokens: Detect từ device (4096/2048/1024)
  Khởi tạo trong main(): sl<GemmaService>().initialize(maxTokens: contextWindow)
  Graceful: nếu chưa có model, không crash — chỉ log + _model = null

Backend: PreferredBackend.gpu (CPU fallback đang debug)
Timeout: 120s

switchModel() [NEW 14/06/2026]:
  Dispose old model → FlutterGemma.installModel() → FlutterGemma.getActiveModel()
  Dùng khi user chọn model khác trong ModelManagerPage

Legacy API (dùng bởi SummaryService):
  generateStream(prompt) — tạo session mới mỗi lần
  generate(prompt) — tương tự, Future<String>
```

### ModelManagerService (mở rộng 14/06/2026)
```
Multi-model support:
  allLlmModels → List<ModelInfo> (từ kAvailableLlmModels registry)
  activeLlmFileName → String (persist qua SharedPreferences)
  downloadModel(fileName) → Generic download
  deleteModel(fileName) → Xoá file + reset status
  setActiveLlmModel(fileName) → Persist + update

ModelType enum: llm, embedding
ModelInfo.modelType: phân biệt LLM vs embedding models
```

### ModelBloc (mở rộng 14/06/2026)
```
State: ModelLoaded(llmModels, geckoInfo, gemmaReady, geckoReady, activeLlmFileName)
Events mới:
  ModelDownloadRequested(fileName) → Tải model bất kỳ
  ActiveModelChanged(fileName) → Lưu + switch model (nếu đã download)
  ModelDeleted(fileName) → Xoá file + fallback về default nếu active
```

### GeckoService (flutter_gemma EmbeddingModel)
```
registerModel(modelPath, tokenizerPath) → initialize()
  → embed(text) → List<double> (768-dim)
```

### VectorStoreService (SQLite Cosine Search)
```
Lưu vector dạng Float32List serialize → BLOB
Search: brute-force cosine similarity
```

### Bm25Service (SQLite FTS5)
```
SQLite FTS5 virtual table (chunks_fts)
Tokenizer: unicode61 (hỗ trợ tiếng Việt Unicode)
Ranking: BM25
```

### DeviceCapability
```
File: lib/core/utils/device_capability.dart
DeviceTier: { high, medium, low }
  high (≥8GB)=4096, medium (6GB)=2048, low (≤4GB)=1024
```

### ChunkingService
```
Interface: chunk(text, {chunkSize=500, overlap=100}) → List<String>
Runtime default: chunkSize=200, overlap=50
```

### MemoryStoreService + SummaryService — Auto Summary
```
Kiến trúc:
  Gemma Session → Recent Messages (15%) → Summary (8%) → User Memories (2%) → RAG Documents
```

---

## 9. Model Management (NEW 14/06/2026)

### Model Registry
```dart
// lib/core/constants/model_constants.dart
const List<AvailableModelInfo> kAvailableLlmModels = [
  AvailableModelInfo(
    name: 'Qwen2.5-1.5B Instruct (mặc định)',
    fileName: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    downloadUrl: 'https://huggingface.co/...',
    fileSizeBytes: 1597931520,  // 1.49 GB
  ),
  AvailableModelInfo(
    name: 'Gemma 4E2B IT',
    fileName: 'gemma-4-E2B-it.litertlm',
    downloadUrl: '...',
    fileSizeBytes: 2588147712,  // 2.59 GB
  ),
];
```

### User-facing UI
| Page | Action |
|------|--------|
| **SettingsPage** | Default model dropdown + Available models list + download |
| **ModelManagerPage** | Full management: download, activate (radio), delete LLM models + Gecko status |
| **ModelOnboardingCoordinator** | Tự động show dialog khi lần đầu mở app (Qwen2.5 + Gecko) |

### Persistent State
| Key | Storage | Giá trị |
|-----|---------|---------|
| `active_llm_model` | SharedPreferences | File name của model đang active |
| `hasSeenModelOnboarding` | SharedPreferences | Đã show onboarding dialog chưa |

---

## 10. Error Handling

```
AppException (base)
├── ModelNotLoadedException        → needsModelDownload: true (show "Download Model")
├── ModelTimeoutException (mới)    → timeout 120s
├── InsufficientMemoryException    → warning dialog
├── DocumentParseException         → error snackbar
├── EmbeddingException             → error, allow retry
├── StorageException               → error, log
└── UploadQueueException (mới)     → Gecko chưa ready, file upload fail

Runtime errors (non-AppException):
  GemmaService.initialize() fail → graceful: log + _model = null
  GemmaService.switchModel() fail → ModelNotLoadedException
  Bad state: Session is closed → Guarded bởi hasActiveSession check tại ChatBloc
  BM25 search error → graceful degradation, fallback về dense search
  DeviceCapability detect error → fallback medium (2048 tokens)
```

---

## 11. Chat UI Architecture

```
ChatPage
  └── AppBar (ScopeSelector + ClearButton)
  └── Column
       ├── ModelNotInstalledBanner (BlocBuilder, kiểm tra llmModels của ModelLoaded)
       ├── ChatBody (BlocBuilder)
       └── AttachedFilesBar + ChatInputBar
```

---

## 12. Token Estimation

```
File: lib/core/utils/token_estimator.dart
estimateTokens(text): chars / 2.5 (heuristic cho tiếng Việt)
estimateMessageTokens(text): estimateTokens(text) + 5 (role overhead)
```

---

## 13. Context Budget (Runtime Dynamic)

### Static Budget (legacy, dùng cho MemoryBudgetConfig)
```
kGemmaMaxTokens = 2048 (mặc định)
kHistoryBudgetRatio  = 0.35 (≈717 tok)
kResponseBudgetRatio = 0.25 (≈512 tok)
kSystemBudgetRatio   = 0.10 (≈205 tok)
kSessionInitHistoryRatio = 0.35
```

### Dynamic Budget Allocation (VERSION=dynamic_budget_v3)
```
Query classification: 8 types (conversational, factual, complex, creative, summarization, translation, mathCoding, multiHop)
Budget ratios phân bổ % theo type + context window
Session init luôn dùng kSessionInitHistoryRatio=0.35
```

### DeviceCapability
```
high (≥8GB) = 4096 tokens
medium (6GB) = 2048 tokens (fallback)
low (≤4GB) = 1024 tokens
```

---

## 14. Database Schema Highlights

```sql
documents: id TEXT PK, name, path, sizeBytes, mimeType, sessionId TEXT? FK, status INT, ...
sessions: id TEXT PK, knowledgeScope INT
session_document_refs: sessionId FK, documentId FK, attachedAt PK
chunks: id TEXT PK, documentId FK, chunkIndex INT, chunkText TEXT, tokenCount INT
vectors: id TEXT PK ('v_' + chunkId), chunkId FK, embedding BLOB
messages: id TEXT PK, sessionId FK, role TEXT, content TEXT, createdAt
session_memory: sessionId PK FK, summary TEXT, summaryVersion INT, msgCount INT, ...
user_memory: namespace TEXT, key TEXT, value TEXT, PK: (namespace, key)
chunks_fts: VIRTUAL TABLE (FTS5) — chunk_id, document_id, chunk_text
```

---

## 15. Model Onboarding Coordinator

```
ModelOnboardingCoordinator (StatefulWidget) — App level
  BlocListener<ModelBloc>: show confirm dialog khi chưa có LLM model nào download
  listenWhen: _promptCompleted, _isDialogVisible, _hasSeenOnboarding,
             curr is ModelLoaded && llmModels all notDownloaded

Flow (updated 14/06/2026):
  1. Confirm dialog → "Qwen2.5-1.5B (1.5GB) + Gecko (111MB)"
  2. Dispatch ModelDownloadRequested(activeLlmFileName) + GeckoDownloadStarted
  3. Progress dialog (2 progress bars) — BlocBuilder
  4. Hoàn tất → SnackBar "Model AI đã sẵn sàng!"
  5. Lỗi → [Để sau] / [Thử lại]

SharedPreferences: hasSeenModelOnboarding
```

---

## 16. Version Markers (Runtime Verification)

| File | Marker | Purpose | Added |
|------|--------|---------|-------|
| `rag_service_impl.dart` | `VERSION=try_fit_v2` | Verify RAG packing code đang chạy | 12/06/2026 |
| `rag_service_impl.dart` | `VERSION=hybrid_v1` | Verify hybrid search (dense+sparse+RRF) | 13/06/2026 |
| `prompt_builder_service.dart` | `VERSION=session_api_v1` | PromptBuilder 2 methods | 13/06/2026 |
| `budget_allocation.dart` | `VERSION=dynamic_budget_v3` | Dynamic Budget Allocation (8 types) | 13/06/2026 |
| `bm25_service_impl.dart` | `VERSION=bm25_v1` | BM25 FTS5 implementation | 13/06/2026 |
| `device_capability.dart` | (device log) | 📱 [Device] Tier: X, contextWindow: Y | 13/06/2026 |

---

## 17. Performance Observations (Gemma 4-E2B, verified 13/06/2026)

| Metric | Không RAG (34 chars) | Có RAG (313 chars) |
|--------|---------------------|--------------------|
| TTFT (prefill) | **1.2 giây** | **6.7 giây** |
| Total generation | 27.5 giây (188 tok) | 26.2 giây (167 tok) |
| Throughput | ~7.1 tok/s | **~8.5 tok/s** |
| Embedding latency | — | ~947ms |
| Search latency | — | ~86ms |

| Metric | Giá trị thực tế |
|--------|----------------|
| GPU crash rate (tested 13/06) | **~0%** (0 crash / 2 queries + 4 uploads) |
| Cold start (bao gồm model init) | ~13 giây |
| Device tiers | high=4096, medium=2048, low=1024 |

⚠️ GPU crash khi prompt có RAG chunks — đã giảm thiểu nhờ turn payload giảm + dynamic budget + device-aware context window.

---

## 18. Core Services Detail

### GeckoService — Chi tiết
```
registerModel(modelPath, tokenizerPath) → initialize()
  → embed(text) → List<double> (768-dim)

TaskType.retrievalQuery cho query
TaskType.retrievalDocument cho indexing

FIFO lock: _runLocked<T>(fn) — Completer-based, tránh race GPU/FFI

⚠️ Gecko_256_quant suspicion (12/06/2026):
  Score ranking barely changes across different Vietnamese queries.
  chunk[0] (giới thiệu chung) always top 1.
  Đã giảm thiểu nhờ Hybrid Search BM25 (13/06/2026).
```

### Bm25Service — Chi tiết
```
Implementation: Bm25ServiceImpl
  Database: SQLite FTS5 virtual table (chunks_fts)
  Tokenizer: unicode61 (hỗ trợ tiếng Việt Unicode)
  Ranking: BM25 (hàm bm25() built-in của SQLite)
  Query sanitize: remove FTS5 special chars ( ) * ^ " ~ : +
  Phrase search: wrap multi-word queries trong double quotes
  VERSION=bm25_v1
```

### VectorStoreService — Chi tiết
```
2-step search:
  1. Filter candidates bằng allowedDocumentIds
  2. Pre-topK (200) → cosine similarity → re-rank → topK (50 cho hybrid search)
```

### DocumentUploadQueue — Chi tiết
```
chunkSize=200, overlap=50 (runtime default 12/06/2026)
Gecko Embedding Guard: throw UploadQueueException nếu Gecko chưa ready

Chunk logging (12/06/2026):
  [UploadQueue] Chunks: 4 chunks (chunkSize=200, overlap=50)
  [UploadQueue] chunk[0] chars=752 tokens=301 preview="..."
  Dùng estimateTokens() (cùng estimator với RAG/PromptBuilder)

BM25 Indexing log (13/06/2026):
  📚 [BM25] Indexed 8 chunks into FTS5
```

### MemoryStoreService + SummaryService — Chi tiết
```
Kiến trúc:
  Gemma Session → Recent Messages (15%) → Summary (8%) → User Memories (2%) → RAG Documents

Database tables:
  SessionMemory: sessionId, summary, summaryVersion, msgCount, estTokens, runningTokenCount, updatedAt
  UserMemory: namespace, key, value (composite PK)

MemoryBudgetConfig (dynamic theo context window):
  responseReserve:    25%
  systemBudget:        5%
  summaryBudget:       8% (clamp 100-500)
  userMemoryBudget:    2%
  recentConversation: 15%
  summaryTrigger:     available * 0.65

Auto-Summary Trigger:
  runningTokenCount > availableConversationBudget * 0.65
  → _runAutoSummary()
     ├─ incrementalSummarize(oldSummary, newMessages)
     ├─ saveSessionMemory()
     └─ extractUserMemory() mỗi 5 lần
```

---

## 19. Chat UI Architecture — Auto-scroll

```
_isNearBottom: ListViewObserver.onObserve
_scrollToBottom(): lần đầu vào chat, message mới, streaming (nếu _isNearBottom)
```
