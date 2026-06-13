# Architecture Document

## 1. Tổng quan kiến trúc

```
Flutter App
│
├── Presentation Layer  (Widgets, Pages)
├── Bloc Layer          (Business Logic + State Management)
├── Service Layer       (AI, RAG, Parsing, VectorStore, Memory, BM25)
└── Data Layer          (Drift/SQLite — DAOs, Tables)
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
  ├── FlutterGemma.initialize()
  ├── await setupLocator()     // DI registration (GetIt)
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

---

## 3. App Widget Tree

```
app.dart — _AppState
  ├── GlobalKey<NavigatorState> _navigatorKey
  ├── GoRouter (navigatorKey)
  │    ├── /            → SessionListPage
  │    ├── /chat/:id    → ChatPage(sessionId)  [BlocProvider<ChatBloc>(key)]
  │    ├── /knowledge   → KnowledgePage
  │    ├── /settings    → SettingsPage
  │    └── /settings/models → ModelManagerPage
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
  int? contextWindow,
})
```

### SendMessage Full Flow (Session API + Dynamic Budget, updated 13/06/2026)
```
1. Guard checks: isClosed? _currentSessionId? is ChatStreaming? _isWaitingForModel?
2. If gemma not ready: subscribe ModelBloc, _isWaitingForModel=true, return
3. Save user message → DB → emit ChatThinking
4. [NEW] Dynamic Budget: ContextBudget.forQuery(content) → phân bổ tokens
   - conversational: history 45% (922), rag 15% (307)
   - factual: history 10% (205), rag 58% (1188)
   - complex: history 20% (410), rag 45% (922)
5. RAG retrieval → RagService.retrieve(query, tokenBudget, scope, sessionId)
   - [NEW] Hybrid search: Dense (Gecko) + Sparse (BM25) + RRF fusion
6. Build turn payload → PromptBuilder.buildTurnPayload(question, ragContext)
   (KHÔNG chứa system, history — chỉ RAG + question, ~300-800 chars)
7. Ensure Gemma session exists (recreate via _recreateSession() if lost)
   (Session đã tạo ở init, KHÔNG recreate mỗi turn, KHÔNG addHistoryMessage ở đây)
8. Stream → emit.forEach(gemmaService.generateWithSession(turnPayload))
   - Each token → emit ChatStreaming
   - Complete → save assistant msg → emit ChatLoaded
   - Error → closeSession → emit ChatError
```

### Session Initialization Flow (Session API, updated 13/06/2026)
```
SessionInitialized(sessionId)
  ├→ emit ChatLoading
  ├→ load messages từ SQLite
  ├→ hydrate KnowledgeScope từ session DB
  ├→ Kiểm tra SessionMemory (summary)
  │    ├→ Có summary → MemoryPromptFormatter.build(summary, memories)
  │    │              → createSession(systemInstruction=summarized)
  │    └→ Không summary → PromptBuilder.buildSystemInstruction(memories)
  │                       → createSession(systemInstruction)
  │
  ├→ [CHỈ 1 LẦN] Replay history (token-based, 35% context — kSessionInitHistoryRatio)
  │    → addHistoryMessage(role, content) MỘT LẦN DUY NHẤT
  │    → KHÔNG addHistoryMessage ở turn tiếp theo
  │
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
  [NEW] Index BM25         → Bm25Service.indexChunks() → FTS5 chunks_fts table
  Complete 1.00            status=completed, chunkCount updated

Granular progress stream → SessionFilesPanel + AttachedFilesBar
  contract.pdf  [████████░░] 82%

Gecko Embedding Guard (defensive):
  if (!_gecko.isReady) throw UploadQueueException('...')
  → status=failed, incrementRetryCount

Chunk logging (thêm 12/06/2026):
  [UploadQueue] Chunks: 4 chunks (chunkSize=200, overlap=50)
  [UploadQueue] chunk[0] chars=752 tokens=301 preview="..."
  Dùng estimateTokens() (cùng estimator với RAG/PromptBuilder)

BM25 Indexing log (thêm 13/06/2026):
  📚 [BM25] Indexed 8 chunks into FTS5
```

---

## 6. Data Flow — RAG Retrieval

```
RagService.retrieve(query, tokenBudget, scope, sessionId):
  0. Early exit guard: _shouldSkipRag() → RagSkipReason enum
     - tooShort: ≤2 từ, không ?, <15 ký tự
     - greeting: hi/hello/chào/xin chào
     - capability: bạn là ai/giúp gì/what can you do
  1. Embed query → GeckoService.embed(query)
  2. Filter document IDs theo KnowledgeScope (CHỈ status=completed)
     - attachedOnly: getCompletedDocumentIdsBySessionId + refDocIds
     - globalOnly: getCompletedGlobalDocumentIds()
     - attachedAndGlobal: global + session + ref (all completed)
  3. Nếu allowedDocIds rỗng → early return RagContext.empty
  4. [NEW] Dense search → VectorStoreService.search(topK:50, threshold:0.7, allowedDocIds)
     (topK tăng từ 20 lên 50 cho hybrid search)
  5. [NEW] Sparse search → Bm25Service.search(query, allowedDocIds, topK:50)
     - Sanitize query (remove FTS5 special chars)
     - BM25 ranking với FTS5 unicode61 tokenizer
     - Filter kết quả theo allowedDocumentIds
  6. [NEW] Reciprocal Rank Fusion (RRF, k=60):
     - Fallback: nếu 1 trong 2 nguồn rỗng → dùng nguồn còn lại
     - Nếu cả 2 rỗng → skip RAG
  7. Log candidates: VERSION=hybrid_v1 dense=N sparse=M fused=K
  8. Try-fit packing (VERSION=try_fit_v2):
     - Hard caps: kMaxRagChunks=3, kMaxRagTokens=500
     - effectiveCap = min(tokenBudget, kMaxRagTokens)
     - continue nếu chunk > effectiveCap
     - add nếu còn budget (greedy knapsack)
     - safety guard khi đầy
  9. Log packing: matched, packed, tokens, cap
  10. Log RagTelemetry

Return: RagContext(chunks, tokenCount, bestScore)
```

---

## 7. Data Flow — Prompt Building (updated 13/06/2026)

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
    [Document 1] chunkText
    [Document 2] chunkText

  === Current Question ===
  user question (KHÔNG turn markers — generateWithSession tự wrap)
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

maxTokens: 2048 (kGemmaMaxTokens)
Backend: PreferredBackend.gpu (CPU fallback đang debug)
Timeout: 120s

Legacy API (dùng bởi SummaryService):
  generateStream(prompt) — tạo session mới mỗi lần
  generate(prompt) — tương tự, Future<String>

⚠️ LiteRT LM constraint: Chỉ support 1 session tại 1 thời điểm.
  Legacy generate() invalidates session → hasActiveSession guard ở ChatBloc.
  generate()/generateStream() set _session=null trước createSession().
  ⚠️ KHÔNG dùng generate() cho query rewriting — destroys active session.

P0 Logging (12/06/2026):
  generateWithSession: sessionActive, promptLength, maxTokens, sessionHash
  prompt head (500 chars), prompt tail (500 chars)
  token[1..20] (first 20 tokens)
  response preview (200 chars), total tokens
  error log + closeSession
```

### GeckoService (flutter_gemma EmbeddingModel)
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

### VectorStoreService (SQLite Cosine Search)
```
Lưu vector dạng Float32List serialize → BLOB
Search: brute-force cosine similarity
Đủ dùng cho < 50,000 chunks

2-step search:
  1. Filter candidates bằng allowedDocumentIds
  2. Pre-topK (200) → cosine similarity → re-rank → topK (50 cho hybrid search)
```

### Bm25Service (SQLite FTS5 — NEW 13/06/2026)
```
Interface:
  search(query, allowedDocumentIds, topK) → List<SearchResult>
  indexChunk(chunkId, documentId, chunkText) → void
  indexChunks(chunks) → void
  deleteByChunkIds(chunkIds) → void

Implementation: Bm25ServiceImpl
  Database: SQLite FTS5 virtual table (chunks_fts)
  Tokenizer: unicode61 (hỗ trợ tiếng Việt Unicode)
  Ranking: BM25 (hàm bm25() built-in của SQLite)
  Query sanitize: remove FTS5 special chars ( ) * ^ " ~ : +
  Phrase search: wrap multi-word queries trong double quotes

  VERSION=bm25_v1
```

### ChunkingService
```
Interface: chunk(text, {chunkSize=500, overlap=100}) → List<String>
Runtime default: chunkSize=200, overlap=50 (set trong DocumentUploadQueue)

charsPerToken = 4 (chunker) vs 2.5 (estimator)
Cố gắng cắt tại word boundary (space)
```

### MemoryStoreService + SummaryService — Auto Summary
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
```

### PromptBuilder (VERSION=session_api_v1, updated 13/06/2026)
```
2 methods riêng biệt:
  buildSystemInstruction({sessionSummary?, userMemories?})
    → System prompt + memories + summary (có <start_of_turn>system<end_of_turn>)
    → Dùng cho createSession()
    → KHÔNG chứa history

  buildTurnPayload({question, ragContext})
    → RAG context + question (KHÔNG turn markers)
    → Dùng cho generateWithSession()
    → KHÔNG chứa system/history

Method cũ build() (VERSION=dedup_v1) giữ cho SummaryService legacy.
```

### DocumentUploadQueue — FIFO Pipeline
```
chunkSize=200, overlap=50 (runtime default 12/06/2026)
Gecko Embedding Guard: throw UploadQueueException nếu Gecko chưa ready
Chunk logging: chars, tokens (estimateTokens), preview (safe substring min 60)
[NEW 13/06/2026] BM25 indexing: sau khi insert chunks/vectors, index vào FTS5
```

---

## 9. Error Handling

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
  Bad state: Session is closed → FFI session invalidated by legacy generate()
    → Guarded bởi hasActiveSession check tại ChatBloc dòng 389
  BM25 search error → graceful degradation, fallback về dense search
```

---

## 10. Chat UI Architecture

```
ChatPage (167 dòng, refactored 11/06/2026)
  └── AppBar (ScopeSelector + ClearButton)
  └── Column
       ├── ModelNotInstalledBanner (BlocBuilder riêng)
       ├── ChatBody (BlocBuilder)
       │    └── MessageList (ScrollController + ListViewObserver)
       │         ├── MessageBubble (MarkdownBody cho AI)
       │         └── LastBubble (BlocBuilder riêng, buildWhen: streamingText)
       │              ├── ChatThinking → ThinkingBubble (3 chấm)
       │              └── ChatStreaming → MessageBubble(isStreaming: true)
       └── AttachedFilesBar + ChatInputBar

Widgets tách riêng (11 files):
  model_not_installed_banner, scope_selector, clear_button, chat_body,
  error_banner, message_list, scroll_to_bottom_button, last_bubble,
  thinking_bubble, attached_files_bar, chat_input_bar
```

### Auto-scroll
```
_isNearBottom: ListViewObserver.onObserve
_scrollToBottom(): lần đầu vào chat, message mới, streaming (nếu _isNearBottom)
```

---

## 11. Model Onboarding Coordinator

```
ModelOnboardingCoordinator (StatefulWidget) — App level
  BlocListener<ModelBloc>: show confirm dialog khi model chưa download
  listenWhen: !_promptCompleted && !_isDialogVisible && !_hasSeenOnboarding
             && curr is ModelLoaded && gemmaInfo.status == notDownloaded

Flow:
  1. Confirm dialog → "Gemma (2.6GB) + Gecko (111MB)"
  2. Dispatch cả GemmaDownloadStarted + GeckoDownloadStarted (song song)
  3. Progress dialog (2 progress bars)
  4. Hoàn tất → SnackBar "Model AI đã sẵn sàng!"
  5. Lỗi → [Để sau] / [Thử lại]

SharedPreferences: hasSeenModelOnboarding (set true khi dialog hiển thị)
Navigator: Dùng GlobalKey<NavigatorState> truyền từ App
```

---

## 12. Token Estimation

```
File: lib/core/utils/token_estimator.dart

estimateTokens(text): chars / 2.5 (heuristic cho tiếng Việt)
estimateMessageTokens(text): estimateTokens(text) + 5 (role overhead)

Dùng bởi:
  - RAG packing (try-fit)
  - PromptBuilder history truncation
  - Context Budget calculation (static + dynamic)
  - UploadQueue chunk logging
```

---

## 13. Context Budget (Runtime Dynamic)

### Static Budget (legacy, dùng cho MemoryBudgetConfig)
```
kGemmaMaxTokens = 2048
kHistoryBudgetRatio  = 0.35 (≈717 tok)
kResponseBudgetRatio = 0.25 (≈512 tok)
kSystemBudgetRatio   = 0.10 (≈205 tok)
kSessionInitHistoryRatio = 0.35 (dùng cho session init)

KHÔNG dùng hardcode totalBudget=8000 cũ.
```

### Dynamic Budget Allocation (NEW 13/06/2026)
```
File: lib/core/constants/budget_allocation.dart

Query classification (heuristics, không dùng model):
  - conversational: greeting, câu <15 ký tự, "bạn là ai"
  - factual: thông tin cụ thể (default)
  - complex: "phân tích", "tại sao", "như thế nào"

Budget ratios theo query type:

| Type | System | Memory | History | RAG | Response | Total |
|------|--------|--------|---------|-----|----------|-------|
| conversational | 10% | 5% | 45% | 15% | 25% | 100% |
| factual | 5% | 2% | 10% | 58% | 25% | 100% |
| complex | 5% | 5% | 20% | 45% | 25% | 100% |

Session init luôn dùng kSessionInitHistoryRatio=0.35 (không dynamic).

VERSION=dynamic_budget_v1
```

---

## 14. Knowledge Management

### KnowledgeScope
```dart
enum KnowledgeScope { attachedOnly, globalOnly, attachedAndGlobal }
```
Lưu theo conversation, persist qua session.

### RAG Filter (chỉ completed)
```
Filter trước ranking, không filter sau topK:
  attachedOnly: getCompletedDocumentIdsBySessionId + getCompletedDocumentIdsByIds(refDocIds)
  globalOnly: getCompletedGlobalDocumentIds()
  attachedAndGlobal: global + session + ref (all completed)
```

### Ownership-based Delete/Detach
```
detachDocument(documentId):
  if doc.sessionId == sessionId → deleteDocument (cascade chunks + vectors)
  else → refsDao.detachDocument (chỉ xoá session_document_refs)
```

### Cascade Delete
```
Delete Session → Sessions ON DELETE CASCADE
  → Documents (sessionId) → Chunks (documentId) → Vectors (xoá thủ công qua DAO)
```

---

## 15. Version Markers (Runtime Verification)

| File | Marker | Purpose | Added |
|------|--------|---------|-------|
| `rag_service_impl.dart` | `VERSION=try_fit_v2` | Verify RAG packing code đang chạy | 12/06/2026 |
| `rag_service_impl.dart` | `VERSION=hybrid_v1` | Verify hybrid search (dense+sparse+RRF) đang chạy | **13/06/2026** |
| `prompt_builder_service.dart` | `VERSION=session_api_v1` | Verify PromptBuilder code mới | 13/06/2026 |
| `budget_allocation.dart` | `VERSION=dynamic_budget_v1` | Verify Dynamic Budget Allocation | **13/06/2026** |
| `bm25_service_impl.dart` | `VERSION=bm25_v1` | Verify BM25 FTS5 implementation | **13/06/2026** |

---

## 16. Performance Observations (thực tế từ runtime, verified 13/06/2026)

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

⚠️ GPU crash khi prompt có RAG chunks — đã giảm thiểu nhờ turn payload giảm + dynamic budget.

---

## 17. Database Schema Highlights

```sql
-- Documents
documents: id TEXT PK, name, path, sizeBytes, mimeType,
           sessionId TEXT? FK→sessions, status INT (IndexStatus),
           progress REAL, errorMessage TEXT?, retryCount INT,
           lastProcessedAt DATETIME?

-- Sessions
sessions: id TEXT PK, knowledgeScope INT (0/1/2)

-- Session Document Refs (junction)
session_document_refs: sessionId FK, documentId FK, attachedAt
                       PK: (sessionId, documentId)

-- Chunks
chunks: id TEXT PK, documentId FK, chunkIndex INT,
        chunkText TEXT, tokenCount INT, createdAt

-- Vectors
vectors: id TEXT PK ('v_' + chunkId), chunkId FK, embedding BLOB, createdAt

-- Messages
messages: id TEXT PK, sessionId FK, role TEXT, content TEXT, createdAt

-- Session Memory
session_memory: sessionId PK FK, summary TEXT, summaryVersion INT,
                msgCount INT, estTokens INT, runningTokenCount INT, updatedAt

-- User Memory
user_memory: namespace TEXT, key TEXT, value TEXT, updatedAt
             PK: (namespace, key)

-- [NEW 13/06/2026] FTS5 Virtual Table for BM25 search
chunks_fts: VIRTUAL TABLE (FTS5)
  - chunk_id UNINDEXED TEXT
  - document_id UNINDEXED TEXT
  - chunk_text (full-text indexed)
  - tokenize='unicode61'
  - Tạo bằng raw SQL trong migration (schemaVersion 5)
  - KHÔNG có Drift table class (virtual table)
  - SQL: CREATE VIRTUAL TABLE chunks_fts USING fts5(...)