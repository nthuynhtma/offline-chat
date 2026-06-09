# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4-E2B (flutter_gemma ^0.16.4)** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã migrate sang **Session-based API** (không còn prompt-based). Gemma session được tạo khi vào chat, history được replay, mỗi turn chỉ gửi user message mới + RAG context. ChatBloc không còn phụ thuộc ContextManagerService/PromptBuilderService.

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
            └→ emit(ChatLoaded(messages))

User gõ text → nhấn Send
  └→ ChatBloc._onSendMessageRequested(content)
       ├→ [Kiểm tra] isClosed? _currentSessionId? is ChatStreaming? _isWaitingForModel?
       ├→ [Kiểm tra] _gemmaService.isReady? Nếu không:
       │    ├→ Đã download nhưng chưa ready → subscribe ModelBloc, đợi gemmaReady
       │    └→ Chưa download → emit(ChatError(needsModelDownload: true))
       │
       ├→ [1] Save user message → SQLite → emit(ChatThinking)
       ├→ [2] RAG Retrieval (nếu Gecko ready)
       │    └→ _geckoService.embed(content) → queryVector[768]
       │    └→ _vectorStore.search(queryVector, topK:5, threshold:0.7)
       ├→ [3] Build user message với RAG context
       │    └→ Inject RAG chunks vào user message:
       │         "[Tài liệu tham khảo...] [Tài liệu 1]... [Câu hỏi của người dùng:]..."
       │    └→ Nếu >800 tokens → tự động trim RAG chunks
       ├→ [4] Đảm bảo session tồn tại (nếu lỗi → tạo lại)
       ├→ [5] Stream response qua Session API
       │    └→ emit.forEach<String>(_gemmaService.generateWithSession(userMessageForModel))
       │    │    ├→ GemmaServiceImpl: addQueryChunk(userMessage) → getResponseAsync() (timeout 120s)
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

Legacy generateStream(prompt) / generate(prompt) vẫn tồn tại nhưng không dùng trong ChatBloc.
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
Budget hiện tại (chưa cập nhật, chỉ tham khảo):
  totalBudget = 8000 tokens (sai với runtime 2048)
  ragBudget = 4000, historyBudget = 3000, questionBudget = 1000, summaryBudget = 500
```

### PromptBuilderService — KHÔNG dùng trong ChatBloc
```
Đã bị loại bỏ khỏi ChatBloc khi migrate sang session-based API.
Giữ lại code để tham khảo hoặc dùng cho mục đích khác.
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

ChatBloc constructor (đã cleanup):
  messageRepo, sessionRepo, gemmaService, geckoService, vectorStore, modelBloc
  (KHÔNG còn: contextManager, promptBuilder)
```

---

## Cấu trúc thư mục
```
lib/
├── core/
│   ├── constants/
│   │   └── model_constants.dart   ← kGemmaMaxTokens = 2048
│   ├── errors/                    ← app_exception.dart (ModelTimeoutException)
│   └── utils/
├── features/
│   ├── chat/
│   │   ├── bloc/                  ← chat_bloc.dart (session-based)
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
│   ├── context/                   ← context_manager_service.dart (async summarize, chưa dùng)
│   ├── prompt/                    ← prompt_builder_service.dart (không dùng trong ChatBloc)
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
| Duplicate user message trong prompt | Skip last history message nếu trùng với question (trong prompt-based, đã deprecated) |
| Không có thinking indicator khi AI xử lý | Thêm `ChatThinking` state + `_ThinkingBubble` (3 dots animation) |
| `scrollable_positioned_list` không maintained | Migrate sang `scrollview_observer: ^1.27.0` |
| AI response chỉ là plain text | Tích hợp `flutter_markdown_plus: ^1.0.7` dùng `MarkdownBody` cho AI bubble |
| Không scroll khi streaming | Thêm `addPostFrameCallback` trong `build()` + bỏ block `ChatStreaming→ChatStreaming` trong `buildWhen` |
| Không scroll về cuối khi vào chat | Thêm `_scrollToBottom()` trong `initState()` với `addPostFrameCallback` |
| RenderBox not laid out với Markdown | Dùng `MarkdownBody` (không dùng `Markdown` widget có ListView lồng) |

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