# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4B (flutter_gemma ^0.16.4)** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã fix lỗi `NoSuchMethodError` do API `flutter_gemma` cũ (0.13.x → 0.16.4) - `getResponseAsync` không còn nhận prompt làm tham số, chuyển sang turn-based API với `addQueryChunk(Message)`.

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
            └→ emit(ChatLoaded(messages))

User gõ text → nhấn Send
  └→ ChatBloc._onSendMessageRequested(content)
       ├→ [Kiểm tra] isClosed? _currentSessionId? is ChatStreaming? _isWaitingForModel?
       ├→ [Kiểm tra] _gemmaService.isReady? Nếu không:
       │    ├→ Đã download nhưng chưa ready → subscribe ModelBloc, đợi gemmaReady
       │    └→ Chưa download → emit(ChatError(needsModelDownload: true))
       │
       ├→ [1] Save user message → SQLite → emit(ChatLoaded)
       ├→ [2] RAG Retrieval (nếu Gecko ready)
       │    └→ _geckoService.embed(content) → queryVector[768]
       │    └→ _vectorStore.search(queryVector, topK:5, threshold:0.7)
       ├→ [3] Context Manager
       │    └→ ContextManagerService.buildContext(...)
       │    │    ├→ Trim RAG theo ragBudget (4000 tokens)
       │    │    ├→ Kiểm tra cache summary:
       │    │    │    ├→ Có cache → dùng ngay
       │    │    │    └→ Chưa có → chạy _summarizeHistory() background (unawaited), không block
       │    │    └→ Trim history theo historyBudget (3000 tokens)
       ├→ [4] Prompt Builder
       │    └→ PromptBuilderService.build(context)
       │    │    → Gemma format: <start_of_turn>system + [RAG] + [Summary] + history + question + <start_of_turn>model
       ├→ [5] Stream response
       │    └→ emit.forEach<String>(_gemmaService.generateStream(prompt))
       │    │    ├→ GemmaServiceImpl: tạo session → addQueryChunk → getResponseAsync() (timeout 120s)
       │    │    ├→ Mỗi token → emit(ChatStreaming)
       │    │    └→ UI: _StreamingBubble cập nhật từng token
       ├→ [6] Stream complete
       │    └→ Save assistant message → SQLite → emit(ChatLoaded)
       └→ [Catch] Error handling
            ├→ ModelNotLoadedException → emit(ChatError(needsModelDownload: true))
            └→ Khác → emit(ChatError(message))

User nhấn Stop ⏹
  └→ ChatBloc._onStreamingCancelled()
       └→ Lưu partial response "_(Đã dừng)_" → SQLite → emit(ChatLoaded)

User pop ChatPage (Destroy)
  └→ BlocProvider dispose ChatBloc
  └→ ChatBloc.close(): cancel ModelBloc subscription, clear accumulated text
  └→ ChatInputBar.dispose(): giải phóng TextEditingController
  └→ Session tự close trong finally block của generateStream()
```

### 2. Kiến trúc UI - Tối ưu rebuild
```
ChatView (StatefulWidget)
  ├── AppBar → _ClearButton (BlocBuilder riêng, buildWhen: streaming state change)
  └── Column
       ├── _ModelNotInstalledBanner (BlocBuilder riêng)
       ├── Expanded → _ChatBody (BlocBuilder riêng, buildWhen: state TYPE change)
       │    └── _MessageList (ListView.builder)
       │         ├── MessageBubble (messages từ DB)
       │         └── _StreamingBubble (BlocBuilder riêng, buildWhen: streamingText change)
       └── ChatInputBar (BlocListener → setState local _isStreaming)
```

---

## Các Service Chính

### GemmaService (flutter_gemma 0.16.4)
```
API model: turn-based chat
  createSession() → addQueryChunk(Message) → getResponseAsync() (no args)

Hỗ trợ 2 chế độ:
1. Legacy (prompt-based): generateStream(prompt) / generate(prompt)
   → Tạo session mới, inject full prompt vào addQueryChunk, close session

2. Session-based (mới): createSession() + addHistoryMessage() + generateWithSession()
   → Giữ session dài hạn, chỉ add user message mới mỗi turn
   → replayHistory() để load history từ DB khi mở chat page
   → hasActiveSession, closeSession()

Timeout: 120s cho cả generate stream và generate sync
Exceptions: ModelNotLoadedException, ModelTimeoutException
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

### ContextManagerService (Token Budget)
```
totalBudget = 8000 tokens
  ├─ ragBudget = 4000
  ├─ historyBudget = 3000
  ├─ questionBudget = 1000
  └─ summaryBudget = 500

Cơ chế summarize: async (unawaited), lần đầu trim history tạm thời,
lần sau dùng summary từ cache. Không block inference chính.
summaryThreshold = 3000 tokens
```

### PromptBuilderService (Gemma Format)
```
<start_of_turn>system
[System instruction]
[Relevant context from documents (RAG)]
[Conversation summary (nếu có)]
<end_of_turn>
<start_of_turn>user
[History messages...]
<end_of_turn>
<start_of_turn>user
[Current question]
<end_of_turn>
<start_of_turn>model\n
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
ChatInitial → ChatLoading → ChatLoaded | ChatStreaming → ChatLoaded | ChatError
                                                          ↑ Stop
                                                          StreamingCancelled → ChatLoaded

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
```

---

## Cấu trúc thư mục
```
lib/
├── core/
│   ├── constants/
│   ├── errors/                   ← app_exception.dart (ModelTimeoutException)
│   └── utils/
├── features/
│   ├── chat/
│   │   ├── bloc/                 ← chat_bloc.dart
│   │   ├── models/
│   │   ├── repositories/
│   │   └── views/                ← chat_page.dart (tối ưu rebuild)
│   ├── session/
│   ├── knowledge/
│   └── model_manager/
├── services/
│   ├── gemma/                    ← gemma_service.dart (session-based + legacy)
│   ├── gecko/
│   ├── vectorstore/
│   ├── context/                  ← context_manager_service.dart (async summarize)
│   ├── prompt/                   ← prompt_builder_service.dart
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
| Mỗi request tạo session mới, không dùng KV-cache | Thêm session-based API: `createSession()` + `generateWithSession()` |

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