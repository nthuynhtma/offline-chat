# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4-E2B (flutter_gemma ^0.16.4)** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã migrate sang **Session-based API** (không còn prompt-based). Auto Summary + Persistent User Memory đã triển khai — chat hàng trăm lượt, đóng app mở lại, tiếp tục hội thoại không cần giữ toàn bộ history trong context 2048 tokens. Attached Files + Knowledge Scope + RAG completed-only filter đã triển khai — hiển thị file chips trên input bar, detach/remove file, indexing warning.

---

## Cách dùng tài liệu này
1. Đọc file này trước — tổng quan dự án
2. Đọc `architecture.md` — kiến trúc chi tiết
3. Đọc `coding_conventions.md` — trước khi viết code
4. Tham chiếu `api_contracts.md` — interface contracts
5. Đọc `implementation_examples.md` — code mẫu thực tế
6. Đọc `pitfalls.md` — các lỗi thường gặp và cách tránh

---

## Tech Stack
| Layer | Technology | Version |
|-------|-----------|---------|
| Framework | Flutter | 3.x |
| State Management | flutter_bloc | ^9.1.1 |
| LLM Runtime | flutter_gemma (LiteRT-LM) | **^0.16.4** |
| Embedding | flutter_gemma EmbeddingModel | ^0.16.4 |
| Database | drift (SQLite) | ^2.18.0 |
| Vector Store | SQLite custom (cosine similarity) | — |
| File Parsing | syncfusion_flutter_pdf | ^33.2.10 |
| DI | get_it | ^9.2.1 |
| Navigation | go_router | ^17.3.0 |
| Markdown Rendering | flutter_markdown_plus | ^1.0.7 |
| Scroll Detection | scrollview_observer | ^1.27.0 |

---

## Nguyên tắc tuyệt đối
- ❌ KHÔNG dùng bất kỳ API cloud nào (OpenAI, Firebase, Supabase...)
- ❌ KHÔNG dùng http package để gọi AI endpoint
- ✅ Tất cả inference chạy on-device
- ✅ Offline-first: app hoạt động hoàn toàn khi tắt mạng
- ✅ Mọi state đi qua Bloc, không dùng `setState` ở business logic

---

## Chat Workflow (Luồng từ User gửi → AI trả lời → UI update → Destroy)

### 1. Flow tổng quan
```
User mở ChatPage(sessionId)
  └→ BlocProvider(sl<ChatBloc>()..add(SessionInitialized(sessionId)))
       └→ ChatBloc._onSessionInitialized()
            ├→ emit(ChatLoading)
            ├→ load messages từ SQLite
            ├→ _createGemmaSessionWithHistory(messages)
            │    ├→ GemmaService.createSession(systemInstruction: "You are AgriAI...")
            │    └→ Replay từng message qua addHistoryMessage(role, content)
            │    └→ Chỉ replay messages vừa token budget (35% context, từ mới→cũ)
            └→ emit(ChatLoaded(messages))

User gõ text → nhấn Send
  └→ ChatBloc._onSendMessageRequested(content)
       ├→ [Kiểm tra] isClosed? _currentSessionId? is ChatStreaming? _isWaitingForModel?
       ├→ [Kiểm tra] _gemmaService.isReady? Nếu không:
       │    ├→ Đã download nhưng chưa ready → subscribe ModelBloc, đợi gemmaReady
       │    └→ Chưa download → emit(ChatError(needsModelDownload: true))
       │
       ├→ [1] Save user message → SQLite → emit(ChatThinking)
       ├→ [2] RAG Retrieval → RagService.retrieve(query, tokenBudget)
       │    └→ RagServiceImpl: embed (GeckoService) → vector search (topK:20, threshold:0.7, allowedDocIds chỉ completed) → chunk-level trim → RagContext
       ├→ [3] Build prompt → PromptBuilder.build(question, ragContext, history, sessionSummary, userMemories)
       │    └→ PromptBuilderImpl: system prompt + RAG chunks + summary + user memories + history + question
       ├→ [4] Kiểm tra `_gemmaService.hasActiveSession`
       │    ├→ Nếu `false` (bị invalidate bởi legacy `generate()`) → `_createGemmaSessionWithHistory()`
       │    └→ Guard dòng 389 chat_bloc.dart: `if (!_gemmaService.hasActiveSession) { ... }`
       ├→ [5] Stream response qua Session API
       │    └→ emit.forEach<String>(_gemmaService.generateWithSession(prompt))
       │    │    ├→ GemmaServiceImpl: addQueryChunk(prompt) → getResponseAsync() (timeout 120s)
       │    │    ├→ Mỗi token → emit(ChatStreaming)
       │    │    └→ UI: _LastBubble cập nhật từng token
       ├→ [6] Stream complete
       │    └→ Save assistant message → SQLite → emit(ChatLoaded)
       └→ [Catch] Error handling
            ├→ ModelNotLoadedException → emit(ChatError(needsModelDownload: true))
            ├→ Session lỗi → closeSession() → tạo lại lần sau
            └→ Khác → emit(ChatError(message))

User nhấn Stop ⏹
  └→ ChatBloc._onStreamingCancelled()
       └→ Lưu partial response "_(Đã dừng)_" → SQLite → emit(ChatLoaded)

User pop ChatPage (Destroy)
  └→ BlocProvider dispose ChatBloc
  └→ ChatBloc.close(): cancel ModelBloc subscription, clear accumulated text
```

### 2. Kiến trúc UI - Tối ưu rebuild (Refactored 11/06/2026)
```
ChatView (StatefulWidget) — lib/features/chat/views/chat_page.dart (167 dòng)
  ├── AppBar
  │    ├── ScopeSelector (PopupMenuButton, KnowledgeScope selector)
  │    └── ClearButton (BlocBuilder riêng, buildWhen: streaming/thinking state change)
  └── Column
       ├── ModelNotInstalledBanner (BlocBuilder riêng)
       ├── Expanded → ChatBody (BlocBuilder, buildWhen: trừ ChatThinking→ChatThinking)
       │    └── MessageList (StatefulWidget, ScrollController + ListViewObserver)
       │         ├── MessageBubble (messages từ DB, dùng MarkdownBody cho AI)
       │         ├── LastBubble (BlocBuilder riêng, buildWhen: streamingText change)
       │         │    ├── ChatThinking → ThinkingBubble (3 chấm animation)
       │         │    └── ChatStreaming → MessageBubble(isStreaming: true)
       │         └── ScrollToBottomButton (AnimatedOpacity + AnimatedSlide, "Mới nhất")
       ├── AttachedFilesBar (StatefulWidget, BlocBuilder<SessionFilesCubit>)
       │    └── FileChip (icon trạng thái + tên + progress % + popup menu Retry/Remove)
       └── ChatInputBar (BlocListener → setState local _isStreaming)

Tất cả widgets con đã được tách vào lib/features/chat/widgets/:
  - model_not_installed_banner.dart
  - scope_selector.dart (+ ScopeOption)
  - clear_button.dart
  - chat_body.dart
  - error_banner.dart
  - message_list.dart
  - scroll_to_bottom_button.dart
  - last_bubble.dart
  - thinking_bubble.dart
  - attached_files_bar.dart (+ FileChip)
  - chat_input_bar.dart

Lợi ích: Code giảm 85% (1223→167 dòng), mỗi widget có trách nhiệm rõ ràng, dễ test, tái sử dụng.
```

### 3. Auto-scroll mechanism
```
MessageList (lib/features/chat/widgets/message_list.dart):
  - _isNearBottom: phát hiện qua ListViewObserver.onObserve
  - _scrollToBottom(): method tái sử dụng
  - initState(): addPostFrameCallback → _scrollToBottom() (lần đầu vào chat)
  - didUpdateWidget(): if _isNearBottom → _scrollToBottom() (message mới)
  - build(): addPostFrameCallback → if _isNearBottom → _scrollToBottom() (streaming)
```

---

## Knowledge Management

### Session-specific + Global Knowledge
Ứng dụng hỗ trợ 2 cấp độ knowledge:

- **Global KB** — Tài liệu dùng chung cho mọi session (`sessionId = null`)
- **Session KB** — Tài liệu upload trong từng chat (`sessionId = abc123`)

```
documents:
  ├── id (text, PK)
  ├── name, path, sizeBytes, mimeType
  ├── sessionId (nullable, FK→sessions.id ON DELETE CASCADE)
  ├── status (enum IndexStatus: pending=0, processing=1, completed=2, failed=3)
  ├── progress (real 0.0→1.0)
  ├── errorMessage (nullable)
  ├── retryCount (int, default=0)
  └── lastProcessedAt (datetime nullable)

sessions:
  └── knowledgeScope (int: 0=attachedOnly, 1=globalOnly, 2=attachedAndGlobal)

session_document_refs (junction table — attach global docs vào session):
  ├── sessionId (FK→sessions.id ON DELETE CASCADE)
  ├── documentId (FK→documents.id ON DELETE CASCADE)
  └── attachedAt (datetime)
  PK: (sessionId, documentId)
```

### KnowledgeScope enum (lib/core/constants/document_constants.dart)
```dart
enum KnowledgeScope {
  attachedOnly,        // Chỉ file upload trong session này
  globalOnly,          // Chỉ Global KB
  attachedAndGlobal,   // Cả hai (default)
}
```

Lưu theo conversation, persist qua session — không mất khi restart app.

### RAG Filter Architecture (2-step: filter trước ranking, chỉ lấy completed)
```
Search:
  1. Xác định allowedDocumentIds theo KnowledgeScope (CHỈ lấy status=completed)
     - attachedOnly: getCompletedDocumentIdsBySessionId + getCompletedDocumentIdsByIds(refDocIds)
     - globalOnly: getCompletedGlobalDocumentIds()
     - attachedAndGlobal: global completed + session completed + ref completed
  2. Nếu allowedDocIds rỗng → early return (RagContext.empty) — không embed, không search
  3. Pre-topK (200 candidates) → cosine similarity
  4. Re-rank → topK (20)
```

**Nguyên tắc:** Mọi document đi vào RAG đều phải có `status == completed`. Không ngoại lệ.
- Session-uploaded docs: filter `sessionId + completed`
- Referenced global docs: filter `id IN refDocIds + completed`
- Global docs: filter `sessionId IS NULL + completed`

**Fix logic:** Filter trước ranking, không filter sau topK (tránh mất kết quả hợp lệ).

### DocumentUploadQueue — FIFO Upload Pipeline (SINGLE pipeline cho mọi entry point)
```
Upload file → ChatPage 📎
  └→ FilePicker (pdf, docx, txt, md, allowMultiple)
       └→ insertDocument(status=pending)
            └→ DocumentUploadQueue.enqueue(job)

Import file → Knowledge Page
  └→ FilePicker
       └→ DocumentRepositoryImpl.importDocumentWithProgress()
            ├→ Copy file + insert metadata
            └→ DocumentUploadQueue.enqueue(job)   ← MERGED 11/06/2026

FIFO _processNext() (Future chain, không lock phức tạp)
  └→ _processJob():
       Parse    0.00 → 0.10
       Chunk    0.10 → 0.20
       Embed    0.20 → 0.95  (per chunk, progressive %)
       Insert   0.95 → 1.00  (chunks + vectors)
       Complete 1.00          (status=completed)

Granular progress (hiển thị realtime trên SessionFilesPanel + _AttachedFilesBar):
  contract.pdf  [████████░░] 82%

Gecko Embedding Guard (defensive — UI gate trước):
  UI layer (ChatInputBar):
    - context.watch<ModelBloc>().state → isGeckoReady
    - Nếu Gecko chưa ready: nút 📎 disabled, tooltip "Preparing AI models..."
    - Khi ModelBloc emit ModelLoaded(geckoReady: true) → rebuild → 📎 enabled ngay
  
  Service layer (defensive — nếu bypass UI qua deep link, test, dev tool):
    if (!_gecko.isReady) {
      throw UploadQueueException('Embedding model chưa sẵn sàng...');
    }
    → Log: Gecko guard triggered: isReady=...
    → Single catch block xử lý: update status=failed + incrementRetryCount
    → Không update DB trước khi throw (tránh duplicate write)
  
  Trong luồng sử dụng bình thường, service guard không bao giờ chạy
  — UI đã chặn từ đầu. Guard chỉ là safety net.

Retry (khi status=failed):
  SessionFilesPanel → Refresh button
    └→ DocumentUploadQueue.retry(documentId)
         ├→ Check status == failed
         ├→ Reset status=pending, retryCount=0
         └→ enqueuePriority() — đầu queue, xử lý ngay

Gecko Embedding Lock (tránh race condition GPU/FFI):
  GeckoServiceImpl._runLocked<T>(fn):
    await _lock;        // chờ previous lock
    _lock = completer;  // set lock mới
    try { return fn(); }
    finally { completer.complete(); } // release

  Hiệu quả: FIFO trên embed/embedBatch, không cần thêm dependencies.

Chunks + Vectors:
  - Tạo ChunksCompanion (uuid.v4 id, documentId, chunkIndex, chunkText, tokenCount)
  - insertChunks batch → getChunksByDocument (Drift auto-generate)
  - VectorEntry(chunkId, embedding) → insertBatch
  - updateChunkCount, updateDocumentStatus(completed), resetRetryCount

SessionFilesCubit (Bloc):
  - Subscribes: watchAllDocuments() + queue.resultStream + queue.stateStream
  - Filter theo sessionId → SessionFileItem(name, status, progress, errorMessage, retryCount)
  - Emit: SessionFilesLoaded(files, queueState, pendingCount)
  - Method: detachDocument(documentId) — ownership-based delete/detach
  - Method: hasProcessingFiles(files) — kiểm tra pending/processing
```

### detachDocument() — Ownership-based Delete/Detach
```
detachDocument(documentId):
  ├→ doc = getDocumentById(documentId)
  ├→ if doc.sessionId == sessionId:
  │    └→ documentsDao.deleteDocument(documentId) // cascade chunks + vectors
  └→ else:
       └→ refsDao.detachDocument(sessionId, documentId) // chỉ xoá session_document_refs

TODO: Khi owner session xoá document, kiểm tra còn session refs khác không.
Nếu có → convert sang global document hoặc yêu cầu confirm.
```

### Cascade Delete
```
Delete Session
  → Sessions ON DELETE CASCADE
    → Documents (sessionId)
      → Chunks (documentId, đã cascade)
        → Vectors (xoá thủ công qua DAO)
```

### Key files:
- `lib/core/constants/document_constants.dart` — Enums (KnowledgeScope, IndexStatus, DocumentScope)
- `lib/database/tables/documents_table.dart` — Schema (sessionId, status, progress, errorMessage, retryCount, lastProcessedAt)
- `lib/database/tables/sessions_table.dart` — Schema (knowledgeScope)
- `lib/database/tables/session_document_refs_table.dart` — Junction table (sessionId, documentId, attachedAt)
- `lib/database/daos/documents_dao.dart` — Queries: +getCompletedDocumentIdsBySessionId, +getCompletedDocumentIdsByIds, +getCompletedGlobalDocumentIds; existing: getDocumentsBySessionId, getDocumentIdsByScope, updateDocumentProgress, getDocumentsByRetryNeeded, incrementRetryCount, resetRetryCount
- `lib/database/daos/session_document_refs_dao.dart` — CRUD cho attached refs
- `lib/services/rag/rag_service.dart` — retrieve(scope, sessionId)
- `lib/services/rag/rag_service_impl.dart` — Scope-based document filter (chỉ completed) + early return khi rỗng
- `lib/services/vectorstore/vector_store_service.dart` — 2-step search: filter→preTopK→re-rank
- `lib/services/chunker/document_upload_queue.dart` — FIFO queue + retry + granular progress + Gecko guard (UploadQueueException)
- `lib/services/gecko/gecko_service.dart` — FIFO lock (Completer) + logging registerModel/initialize
- `lib/features/chat/bloc/chat_bloc.dart` — KnowledgeScopeChanged event, load scope từ session
- `lib/features/session/models/session_model.dart` — knowledgeScope field
- `lib/features/knowledge/bloc/session_files_cubit.dart` — File list cubit (watch DB + queue) + detachDocument() + hasProcessingFiles()
- `lib/features/knowledge/bloc/knowledge_bloc.dart` — Subscribe queue result stream, _QueueResultArrived handler
- `lib/features/knowledge/views/session_files_panel.dart` — Bottom sheet UI (status, progress %, retry button)
- `lib/features/knowledge/repositories/document_repository.dart` — importDocumentWithProgress enqueue vào queue (merge pipeline 11/06/2026)
- `lib/features/chat/views/chat_page.dart` — 📎 Attach button + file picker + attach menu + _AttachedFilesBar + _FileChip
- `lib/features/model_manager/bloc/model_bloc.dart` — +logging _onStatusChecked (gemmaDownloaded, geckoDownloaded, init results)
- `lib/injection/service_locator.dart` — Register DocumentUploadQueue + SessionFilesCubit + KnowledgeBloc (với queue)

---

## Các Service Chính

### GemmaService (flutter_gemma 0.16.4)
```
API model: turn-based chat — SESSION-BASED (không còn dùng prompt-based ở ChatBloc)
  createSession(systemInstruction) → addHistoryMessage(role, content) → generateWithSession(userMessage)

ChatBloc dùng session-based:
  → _createGemmaSessionWithHistory() khi SessionInitialized
  → generateWithSession() mỗi turn
  → hasActiveSession, closeSession() khi lỗi

maxTokens: 2048 (kGemmaMaxTokens trong model_constants.dart)
Timeout: 120s
Exceptions: ModelNotLoadedException, ModelTimeoutException

Legacy generateStream(prompt) / generate(prompt) vẫn tồn tại — dùng bởi SummaryService.

⚠️ **LiteRT LM constraint (critical):** Chỉ support 1 conversation session tại 1 thời điểm.
  - Legacy `generate()`/`generateStream()` gọi `_model!.createSession()` sẽ invalidate session chính ở FFI.
  - **Fix:** `generate()` và `generateStream()` set `_session = null` trước `createSession()`.
  - Hậu quả nếu không fix: `hasActiveSession` vẫn `true` ở Dart, nhưng FFI session đã chết → `Bad state: Session is closed`.
  - ChatBloc có guard: tự động recreate session nếu `!hasActiveSession`.

Token estimator (lib/core/utils/token_estimator.dart):
  - estimateTokens(text): cho RAG chunks, question, summary (heuristic chars/2.5)
  - estimateMessageTokens(text): cho history replay (estimateTokens + 5 role overhead)
  - Dùng kCharsPerToken = 2.5 cho tiếng Việt (conservative)
```

### GeckoService (flutter_gemma EmbeddingModel)
```
Flow: registerModel(modelPath, tokenizerPath) → initialize() → embed(text) / embedBatch(texts)
- Embedding dimension: 768
- TaskType.retrievalQuery cho query
- TaskType.retrievalDocument cho document indexing

Logging (added 11/06/2026):
  registerModel: model=..., tokenizer=... → success/failed
  initialize: calling FlutterGemma.getActiveEmbedder() → success/null
```

### VectorStoreService (SQLite Cosine Search)
```
- Lưu vector dạng Float32List serialize → BLOB trong SQLite
- Search: brute-force cosine similarity, topK, threshold
- Đủ dùng cho < 50,000 chunks
```

### ContextManagerService (Token Budget) — KHÔNG dùng trong ChatBloc
```
Giữ lại cho session cycling trong tương lai.
Budget hiện tại đã chuyển sang ratio-based dynamic (trong chat_bloc.dart):
  kGemmaMaxTokens = 2048
  historyBudgetRatio = 0.35 (≈717 tok)
  responseBudgetRatio = 0.25 (≈512 tok)
  systemBudgetRatio = 0.10 (≈205 tok)
  questionTokens = estimateTokens(userMessage)
  ragBudget = max(0, phần còn lại)

Các constants cũ (totalBudget=8000, ragBudget=4000, historyBudget=3000)
đã bị xoá khỏi app_constants.dart do không còn phản ánh runtime thực tế.
```

### MemoryStoreService + SummaryService — Auto Summary + User Memory

```
Session API + Auto Summary + Persistent User Memory + RAG ≈ 95% production-ready.

Kiến trúc:
  Gemma Session
      │
      ▼
  Recent Messages (token-based ~15% context)
      │
      ▼
  Conversation Summary (incremental, session-specific, lưu DB)
      │
      ▼
  Persistent User Memory (cross-session, namespace.key=value)
      │
      ▼
  RAG Documents

Database tables:
  - SessionMemory: sessionId, summary, summaryVersion, msgCount, estTokens, runningTokenCount, updatedAt
  - UserMemory: namespace, key, value, updatedAt (composite PK: namespace+key)

MemoryBudgetConfig (dynamic theo context window):
  - responseReserve = 25%
  - systemBudget = 5%
  - summaryBudget = 8%, clamp(100, 500)
  - userMemoryBudget = 2%
  - recentConversationBudget = 15%
  - availableConversationBudget = contextWindow - response - system - summary - memory
  - summaryTrigger = availableConversationBudget * 0.65

Flow khi mở session:
  1. Kiểm tra SessionMemory.summary
  2. Nếu có → inject summary + user memory vào system instruction + replay recent messages (token-based)
  3. Nếu không → replay history bình thường (35% context budget)

Flow auto-summary (sau mỗi response):
  1. _tryTriggerAutoSummary(): tính runningTokenCount, nếu > summaryTrigger → unawaited(_runAutoSummary())
  2. _runAutoSummary(): lock _isSummarizing, incremental summarize (old summary + new messages)
  3. Sau summarize: runningTokenCount = summaryTokens + actualRecentTokens
  4. Extract user memory mỗi kUsersMemoryExtractInterval = 5 lần summarize

Key files:
  - lib/core/constants/model_constants.dart — MemoryBudgetConfig class
  - lib/services/memory_store/memory_store_service.dart — CRUD SessionMemory + UserMemory
  - lib/services/memory_store/summary_service.dart — Incremental summarize + extract user memory
  - lib/services/memory_store/memory_prompt_formatter.dart — Build system instruction
  - lib/features/chat/bloc/chat_bloc.dart — Inject summary, trigger summarize, _isSummarizing lock
  - lib/database/tables/session_memory_table.dart — Table definition
  - lib/database/tables/user_memory_table.dart — Table definition

ContextManagerService: @Deprecated — giữ lại để tránh break build, sẽ cleanup sau.
```

### RagService — RAG Pipeline Interface
```
abstract interface class RagService {
  Future<RagContext> retrieve({
    required String query,
    required int tokenBudget,
    required KnowledgeScope scope,
    String? sessionId,
  });
}

RagContext:
  - chunks: List<SearchResult> (đã trim chunk-level, removeLast())
  - tokenCount: int (tổng token của chunks)
  - bestScore: double? (top-1 score, null nếu không có chunks)
  - hasContext: bool (getter: chunks.isNotEmpty)

RagServiceImpl pipeline:
  1. Embed query → GeckoService
  2. Filter document IDs theo KnowledgeScope (chỉ lấy completed):
     - attachedOnly: getCompletedDocumentIdsBySessionId + getCompletedDocumentIdsByIds(refDocIds)
     - globalOnly: getCompletedGlobalDocumentIds()
     - attachedAndGlobal: global completed + session completed + ref completed
  3. Nếu allowedDocIds rỗng → early return RagContext.empty (không embed, không search)
  4. Vector search → VectorStoreService (topK: 20, threshold: 0.7, allowedDocumentIds)
  5. Chunk-level trim → break khi vượt tokenBudget
  6. Log RagTelemetry
  7. Return RagContext

VectorStoreService 2-step search:
  - Step 1: Filter candidates bằng allowedDocumentIds (WHERE documentId IN ...)
  - Step 2: Pre-topK (200) → cosine similarity → re-rank → topK (20)

Graceful degradation: nếu Gecko chưa ready hoặc search lỗi → RagContext rỗng
```

### RagTelemetry + RagTelemetryAggregator — Retrieval Observability
```
RagTelemetry (immutable, computed getters cho derived state):
  query, embeddingTimeMs, searchTimeMs, retrievalTimeMs
  topScores: List<double> (tối đa kTelemetryTopScoresCount=5)
  bestScore / bestScoreGap / worstScore (computed từ topScores)
  matchedChunks, trimmedChunks, returnedChunks
  ragTokenCount, ragTokenBudget
  state (computed): empty / weak / normal (dựa trên kWeakScoreThreshold=0.75)
  toLogString() format log

RagTelemetryAggregator:
  record(telemetry) → ghi nhận từng query
  retrievalSuccessRate, weakRetrievalPercent, emptyRetrievalPercent
  avgRetrievalTimeMs, maxRetrievalTimeMs
  averageBestScore, avgBestScore, averageBestScoreGap, averageLatencyMs
  avgTrimmedChunks, avgReturnedChunks, avgMatchedChunks
  scoreDistribution: Map<ScoreBucket, int> (histogram)
  toReportString() → health report

Key files:
  - lib/services/rag/rag_telemetry.dart
  - lib/services/rag/rag_telemetry_aggregator.dart
  - lib/core/constants/model_constants.dart → kTelemetryTopScoresCount, kWeakScoreThreshold
```

### PromptBuilder — Prompt Pipeline
```
abstract interface class PromptBuilder {
  Future<String> build({
    required String question,
    required RagContext ragContext,
    required List<MessageModel> history,
    String? sessionSummary,
    List<UserMemory> userMemories,
  });
}

PromptBuilderImpl ordering (ưu tiên RAG sát question):
  <start_of_turn>system
    System Prompt (AgriAI)
    === User Memory ===        (cross-session persona)
    === Session Summary ===     (conversation state)
  <end_of_turn>
    === Recent Conversation === (history turns)
    === Reference Documents === (RAG chunks — sát question nhất)
    === Current Question ===
  <start_of_turn>user
    question
  <start_of_turn>model

Lưu ý: Delimiter (=== ... ===) giúp Gemma ổn định hơn.
RAG nằm giữa History và Question để model nhỏ không bị loãng context.
```

---

## Các Exception
```
AppException (base)
├── ModelNotLoadedException        → needsModelDownload: true
├── ModelTimeoutException (mới)    → timeout 120s quá lâu
├── InsufficientMemoryException    → warning dialog
├── DocumentParseException         → error snackbar
├── EmbeddingException             → error, allow retry
├── StorageException               → error, log
└── UploadQueueException (mới)     → Gecko chưa ready, file upload fail với message rõ ràng
```

### Runtime errors (non-AppException)
```
Bad state: Session is closed → FFI session bị invalidate bởi legacy `generate()` (SummaryService).
  → Guarded bởi `hasActiveSession` check tại ChatBloc dòng 389 — tự động recreate session.
```

---

## ChatBloc States
```
ChatInitial → ChatLoading → ChatLoaded | ChatThinking | ChatStreaming → ChatLoaded | ChatError
                                                    ↑ Stop
                                                    StreamingCancelled → ChatLoaded

ChatThinking: messages (hiển thị 3 dots animation, emit sau khi save user msg, trước khi stream)
ChatStreaming: messages, streamingText, streamingId, ragResults
ChatLoaded: messages
ChatError: message, needsModelDownload, messages
```

---

## DI Pattern
```
GetIt — quản lý dependency graph (singleton services, repositories)
MultiBlocProvider ở app.dart — lifecycle của singleton blocs
ChatBloc — Factory pattern, mỗi session tạo mới, BlocProvider ở ChatPage với key

ChatBloc constructor:
  messageRepo, sessionRepo, gemmaService, modelBloc,
  memoryStore, summaryService, ragService, promptBuilder, contextWindow
  (KHÔNG còn: geckoService, vectorStore, contextManager, promptBuilder cũ)
  (MỚI: ragService, promptBuilder)

KnowledgeBloc (singleton, 2 tham số từ 11/06/2026):
  DocumentRepository + DocumentUploadQueue
  → subscribe queue.resultStream để cập nhật UI khi indexing hoàn tất

SessionFilesCubit — registerLazySingleton, inject documentsDao + refsDao + uploadQueue
```

---

## Cấu trúc thư mục
```
lib/
├── core/
│   ├── constants/
│   │   └── model_constants.dart   ← kGemmaMaxTokens = 2048, ratio constants
│   ├── errors/                    ← app_exception.dart (+UploadQueueException)
│   └── utils/
│       └── token_estimator.dart   ← estimateTokens(), estimateMessageTokens()
├── features/
│   ├── chat/
│   │   ├── bloc/                  ← chat_bloc.dart (session-based, token budget dynamic)
│   │   ├── models/
│   │   ├── repositories/
│   │   ├── views/                 ← chat_page.dart (167 dòng, refactored 11/06/2026), message_bubble.dart, rag_sources_widget.dart
│   │   └── widgets/               ← Tách từ chat_page.dart (11/06/2026)
│   │       ├── model_not_installed_banner.dart
│   │       ├── scope_selector.dart
│   │       ├── clear_button.dart
│   │       ├── chat_body.dart
│   │       ├── error_banner.dart
│   │       ├── message_list.dart
│   │       ├── scroll_to_bottom_button.dart
│   │       ├── last_bubble.dart
│   │       ├── thinking_bubble.dart
│   │       ├── attached_files_bar.dart
│   │       └── chat_input_bar.dart
│   ├── session/
│   ├── knowledge/
│   │   ├── bloc/
│   │   │   ├── knowledge_bloc.dart  ← subscribe queue result stream (11/06/2026)
│   │   │   └── session_files_cubit.dart
│   │   └── views/
│   │       └── session_files_panel.dart
│   └── model_manager/
│       └── bloc/
│           └── model_bloc.dart      ← logging StatusChecked (11/06/2026)
├── services/
│   ├── gemma/                     ← gemma_service.dart (session-based + legacy)
│   ├── gecko/
│   │   ├── gecko_service.dart     ← FIFO lock + logging registerModel/initialize (11/06/2026)
│   │   └── gecko_retry_service.dart
│   ├── vectorstore/
│   ├── chunker/
│   │   ├── chunking_service.dart
│   │   └── document_upload_queue.dart ← FIFO queue + Gecko guard logging (11/06/2026)
│   ├── rag/
│   ├── memory_store/
│   ├── context/
│   ├── prompt/
│   └── parser/
├── database/
│   ├── app_database.dart
│   ├── daos/
│   │   ├── documents_dao.dart
│   │   ├── session_document_refs_dao.dart
│   │   ├── chunks_dao.dart
│   │   └── ...
│   └── tables/
└── injection/
    └── service_locator.dart
```

---

## Model Onboarding Coordinator (ModelOnboardingCoordinator)

### Kiến trúc
```
ModelOnboardingCoordinator (StatefulWidget) — App level
├── Nhận navigatorKey từ App._navigatorKey (GlobalKey<NavigatorState>)
├── BlocListener<ModelBloc> lắng nghe state tại App level
├── listenWhen: !_promptCompleted && !_isDialogVisible && !_hasSeenOnboarding
│              && curr is ModelLoaded && curr.gemmaInfo.status == notDownloaded
└── listener: postFrameCallback → _showConfirmDialog()

Luồng:
  1. Chờ ModelBloc emit ModelLoaded & gemma chưa download
  2. Show Confirm dialog → "Gemma (2.6GB) + Gecko (111MB)"
  3. User bấm [Tải xuống] → dispatch cả GemmaDownloadStarted() + GeckoDownloadStarted() (song song)
  4. Progress dialog: BlocBuilder hiển thị 2 progress bar riêng (Gemma + Gecko)
  5. Cả 2 hoàn tất → đóng dialog + SnackBar "Model AI đã sẵn sàng!"
  6. Lỗi → [Để sau] / [Thử lại] (retry cả 2)
  7. "Để sau" → _promptCompleted = true, banner ChatPage fallback

SharedPreferences:
  hasSeenModelOnboarding:
    - Set = true NGAY khi confirm dialog hiển thị lần đầu
    - Đọc để quyết định có show onboarding ở lần mở app tiếp theo
    - Nếu true → bỏ qua, banner ChatPage chịu trách nhiệm nhắc nhở

### Navigation context handling
  Dùng GlobalKey<NavigatorState> truyền từ App xuống coordinator.
  showDialog() dùng context từ navigatorKey.currentContext (thay vì context của BlocListener)
  → tránh lỗi "Navigator operation requested with a context that does not include a Navigator"

Sửa đổi kiến trúc App thành StatefulWidget:
  - GlobalKey<NavigatorState> _navigatorKey — dùng cho cả GoRouter + Coordinator
  - GoRouter(navigatorKey: _navigatorKey)
  - MaterialApp.router(builder: (context, child) => ModelOnboardingCoordinator(navigatorKey: ..., child: child!))

Key files:
  - lib/features/model_manager/widgets/model_onboarding_coordinator.dart
  - lib/app.dart (StatefulWidget)
  - lib/core/utils/logger.dart — prefix [Onboarding] cho debug logs

### Các vấn đề đã fix gần đây

| Vấn đề | Fix |
|--------|-----|
| **Onboarding dialog không show khi lần đầu mở app** | Tạo `ModelOnboardingCoordinator` — BlocListener trigger khi model chưa download |
| **No MaterialLocalizations found khi showDialog từ BlocListener ngoài MaterialApp** | Dùng `builder` parameter của `MaterialApp.router` thay vì wrap ngoài |
| **Navigator not found — builder context không có Navigator** | Dùng `GlobalKey<NavigatorState>` + `GoRouter.navigatorKey` + showDialog qua `navigatorKey.currentContext` |
| **Banner ChatPage không hiển thị khi model chưa tải** | `ModelNotInstalledBanner` đọc từ `ModelBloc` thay vì `ChatBloc` |
| **Chỉ tải Gemma, không tải Gecko** | Dispatch cả `GemmaDownloadStarted()` + `GeckoDownloadStarted()` song song |
| **Dialog không có lối thoát khi lỗi** | Error dialog thêm [Để sau] + [Thử lại] |
| **SharedPreferences semantics sai: set sau dialog xuất hiện** | `hasSeenModelOnboarding` set true ngay khi dialog hiển thị lần đầu |
| **Trigger condition sai khi ModelLoading chưa hoàn tất** | `listenWhen` check `curr is ModelLoaded && gemmaInfo.status == notDownloaded` |
| `getResponseAsync(prompt)` không khớp API mới | Chuyển sang `addQueryChunk(Message)` + `getResponseAsync()` không tham số |
| `dynamic` dispatch che giấu lỗi compile | Dùng `InferenceModel` type-safe |
| `add()` trong `stream.listen()` gây race condition | Bọc trong `Future.microtask()` |
| Model treo → UI block vô hạn | Thêm `.timeout(Duration(seconds: 120))` + `ModelTimeoutException` |
| BlocBuilder rebuild toàn bộ UI mỗi token | Tách 5 widget con với `buildWhen` riêng |
| **ChatPage quá nhiều code UI (1223 dòng)** | **Refactor 11/06/2026**: Tách 11 widget con, giảm 85% code |
| **Hai pipeline indexing song song — Knowledge Page không qua queue** | **Merge pipeline 11/06/2026**: `importDocumentWithProgress()` chỉ copy + insert metadata + enqueue. Queue xử lý parse/chunk/embed/completed. Cả Knowledge Page và Chat Attach dùng chung pipeline. |
| **Knowledge Page import không set status=completed → RAG luôn rỗng** | Đã fix qua pipeline merge — queue luôn set `completed` status. |
| **DocumentRepositoryImpl compile error `_vectorStore` không tồn tại** | Sửa thành `_db.vectorsDao.deleteVectorsByChunkIds()` |
| **KnowledgeBloc không thoát khỏi KnowledgeIndexing state khi queue hoàn tất** | Thêm `_QueueResultArrived` event + handler. Subscribe `queue.resultStream`. |
| **Gecko chưa ready — queue fail không có log chi tiết** | Thêm logging: ModelBloc.StatusChecked (gemmaDownloaded, geckoDownloaded, init results), GeckoServiceImpl.registerModel/initialize, queue guard trigger. |
| **ChunksCompanion thiếu `createdAt` → `InvalidDataException`** | Thêm `createdAt: Value(DateTime.now())` khi tạo `ChunksCompanion` trong `DocumentUploadQueue._processJob()`. |
| **`isModelFileValid()` không log chi tiết — khó debug tokenizer** | Log đầy đủ: file, path, exists, size, expected, valid. |
| **Tokenizer validation fail — `geckoReady=false`** | Đang điều tra P1: cần chạy debug mode, tìm dòng `[ModelManager] Validation: file=sentencepiece.model ...` để xác định tokenizer missing/corrupt/path sai. |
