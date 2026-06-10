# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4-E2B (flutter_gemma ^0.16.4)** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã migrate sang **Session-based API** (không còn prompt-based). Auto Summary + Persistent User Memory đã triển khai — chat hàng trăm lượt, đóng app mở lại, tiếp tục hội thoại không cần giữ toàn bộ history trong context 2048 tokens.

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
       │    └→ RagServiceImpl: embed (GeckoService) → vector search (topK:20, threshold:0.7) → chunk-level trim → RagContext
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

### 2. Kiến trúc UI - Tối ưu rebuild
```
ChatView (StatefulWidget)
  ├── AppBar → _ClearButton (BlocBuilder riêng, buildWhen: streaming/thinking state change)
  └── Column
       ├── _ModelNotInstalledBanner (BlocBuilder riêng)
       ├── Expanded → _ChatBody (BlocBuilder, buildWhen: trừ ChatThinking→ChatThinking)
       │    └── _MessageList (StatefulWidget, ScrollController + ListViewObserver)
       │         ├── MessageBubble (messages từ DB, dùng MarkdownBody cho AI)
       │         └── _LastBubble (BlocBuilder riêng, buildWhen: streamingText change)
       │              ├── ChatThinking → _ThinkingBubble (3 chấm animation)
       │              └── ChatStreaming → MessageBubble(isStreaming: true)
       ├── _ScrollToBottomButton (AnimatedOpacity + AnimatedSlide, "Mới nhất")
       └── ChatInputBar (BlocListener → setState local _isStreaming)
```

### 3. Auto-scroll mechanism
```
_MessageListState:
  - _isNearBottom: phát hiện qua ListViewObserver.onObserve
  - _scrollToBottom(): method tái sử dụng
  - initState(): addPostFrameCallback → _scrollToBottom() (lần đầu vào chat)
  - didUpdateWidget(): if _isNearBottom → _scrollToBottom() (message mới)
  - build(): addPostFrameCallback → if _isNearBottom → _scrollToBottom() (streaming)
```

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
  - ChatBloc có guard tại dòng 389: tự động recreate session nếu `!hasActiveSession`.

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
  });
}

RagContext:
  - chunks: List<SearchResult> (đã trim chunk-level, removeLast())
  - tokenCount: int (tổng token của chunks)
  - bestScore: double? (top-1 score, null nếu không có chunks)
  - hasContext: bool (getter: chunks.isNotEmpty)

RagServiceImpl:
  1. Embed query → GeckoService
  2. Vector search → VectorStoreService (topK: 20, threshold: 0.7)
  3. Chunk-level trim → break khi vượt tokenBudget
  4. Log RagTelemetry
  5. Return RagContext

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
└── StorageException               → error, log
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
```

---

## Cấu trúc thư mục
```
lib/
├── core/
│   ├── constants/
│   │   └── model_constants.dart   ← kGemmaMaxTokens = 2048, ratio constants
│   ├── errors/                    ← app_exception.dart (ModelTimeoutException)
│   └── utils/
│       └── token_estimator.dart   ← estimateTokens(), estimateMessageTokens()
├── features/
│   ├── chat/
│   │   ├── bloc/                  ← chat_bloc.dart (session-based, token budget dynamic)
│   │   ├── models/
│   │   ├── repositories/
│   │   └── views/                 ← chat_page.dart, message_bubble.dart, rag_sources_widget.dart
│   ├── session/
│   ├── knowledge/
│   └── model_manager/
├── services/
│   ├── gemma/                     ← gemma_service.dart (session-based + legacy)
│   ├── gecko/
│   ├── vectorstore/
│   ├── rag/                       ← rag_service, rag_context, rag_service_impl (RAG pipeline interface)
│   ├── memory_store/              ← memory_store_service, summary_service, memory_prompt_formatter
│   ├── context/                   ← context_manager_service.dart (@Deprecated)
│   ├── prompt/                    ← prompt_builder_service.dart (interface PromptBuilder + PromptBuilderImpl)
│   │                                (hiện đã dùng lại trong ChatBloc thay vì inline logic)
│   └── parser/
├── database/
│   ├── app_database.dart
│   ├── daos/
│   └── tables/
└── injection/
    └── service_locator.dart
```

---

## Các vấn đề đã fix gần đây

| Vấn đề | Fix |
|--------|-----|
| `getResponseAsync(prompt)` không khớp API mới | Chuyển sang `addQueryChunk(Message)` + `getResponseAsync()` không tham số |
| `dynamic` dispatch che giấu lỗi compile | Dùng `InferenceModel` type-safe |
| `add()` trong `stream.listen()` gây race condition | Bọc trong `Future.microtask()` |
| Model treo → UI block vô hạn | Thêm `.timeout(Duration(seconds: 120))` + `ModelTimeoutException` |
| BlocBuilder rebuild toàn bộ UI mỗi token | Tách 5 widget con với `buildWhen` riêng |
| Summarize block inference → TTFT bị trễ | Chạy background với `unawaited()`, dùng cache cho request sau |
| **maxTokens=1024 → lỗi tràn token (1073 >= 1024)** | Tăng `kGemmaMaxTokens = 2048` trong `model_constants.dart` |
| **Prompt quá dài do build toàn bộ history mỗi lần** | Chuyển sang **Session-based API**: `createSession` + `generateWithSession` |
| **History replay không giới hạn + RAG hardcode 800 token** | Token-budget based history replay (35% context, duyệt từ mới→cũ) + Dynamic RAG budget (`max(0, context - history - reserves - question)`) + ratio-based constants scale theo `kGemmaMaxTokens` |
| Duplicate user message trong prompt | Skip last history message nếu trùng với question (trong prompt-based, đã deprecated) |
| Không có thinking indicator khi AI xử lý | Thêm `ChatThinking` state + `_ThinkingBubble` (3 dots animation) |
| `scrollable_positioned_list` không maintained | Migrate sang `scrollview_observer: ^1.27.0` |
| AI response chỉ là plain text | Tích hợp `flutter_markdown_plus: ^1.0.7` dùng `MarkdownBody` cho AI bubble |
| Không scroll khi streaming | Thêm `addPostFrameCallback` trong `build()` + bỏ block `ChatStreaming→ChatStreaming` trong `buildWhen` |
| Không scroll về cuối khi vào chat | Thêm `_scrollToBottom()` trong `initState()` với `addPostFrameCallback` |
| RenderBox not laid out với Markdown | Dùng `MarkdownBody` (không dùng `Markdown` widget có ListView lồng) |
| **Không chat được hàng trăm lượt do context 2048 token giới hạn** | **Auto Summary + Persistent User Memory**: incremental summary (old + new messages) → lưu DB, inject summary + user memory vào system instruction khi mở session, trigger dựa trên runningTokenCount > 65% availableConversationBudget, UserMemory cross-session (namespace.key=value) |
| **Xoá session để lại orphan SessionMemory data** | Thêm `onDelete: KeyAction.cascade` + `onUpdate: KeyAction.cascade` vào foreign key trong `session_memory_table.dart` |
| **RAG logic inline trong ChatBloc + chunk substring trimming** | Tách **RagService** (interface + impl) + **PromptBuilder** (interface + impl) + **RagContext** model. ChatBloc chỉ còn orchestration. Chunk trimming: `removeLast()` thay vì `substring()`. |
| **PromptBuilder ordering sai (RAG trước History) + thiếu delimiter** | Sửa thành: System → Memories → Summary → `<end_of_turn>` → History → RAG (sát question) → Question. Thêm delimiter `=== ... ===` cho mỗi section. |
| **Thiếu observability cho RAG pipeline — không biết retrieval quality** | Thêm **RagTelemetry** (timing, scores, chunks, budget, state) + **RagTelemetryAggregator** (health report, score histogram). Log mỗi query. |
| **Bad state: Session is closed sau Auto Summary — không chat được lần 2** | `generate()` set `_session = null` trước `_model!.createSession()` — tránh dirty state. LiteRT LM chỉ support 1 session, legacy API invalidate session cũ. ChatBloc có guard recreate session (`if (!hasActiveSession) → _createGemmaSessionWithHistory()`). |

---

## Token Budget Architecture

```
kGemmaMaxTokens = 2048 (model_constants.dart)
        |
        ├── History Budget (35%) = ~717 tok
        │     Duyệt từ message mới→cũ, dùng estimateMessageTokens()
        │     Dừng khi historyTokenSum > historyBudget
        │
        ├── Response Reserve (25%) = ~512 tok
        │
        ├── System Reserve (10%) = ~205 tok
        │
        ├── Question Tokens = estimateTokens(userMessage)
        │
        └── RAG Budget = max(0, phần còn lại)
              Trim chunks bằng estimateTokens() thay vì hardcode 800
```

### Key files:
- `lib/core/constants/model_constants.dart` — `kGemmaMaxTokens`, ratio constants
- `lib/core/utils/token_estimator.dart` — `estimateTokens()`, `estimateMessageTokens()`
- `lib/features/chat/bloc/chat_bloc.dart` — History replay + Dynamic RAG budget
- `lib/core/constants/app_constants.dart` — Đã xoá context budget constants cũ (sai với runtime 2048)

---

## Performance Targets
| Metric | Target |
|--------|--------|
| TTFT (Time to First Token) | < 2 giây |
| Token/s | 10-25 token/s |
| Embedding latency | < 200ms/chunk |
| Search latency (10k chunks) | < 100ms |
| App cold start | < 3 giây |

Device target: Snapdragon 8 Gen 2, Apple A17 Pro trở lên.