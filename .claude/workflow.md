# 🏗️ Workflow Thực Tế - OfflineChat

## 1. Tổng quan Flow (Context Level)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        OFFLINECHAT APP                             │
│                                                                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐     │
│  │ Session   │    │  Chat    │    │Knowledge │    │ Settings  │     │
│  │ List Page │───▶│  Page    │───▶│  Page    │    │  Page    │     │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘     │
│                       │                    (model selector,          │
│                       │              available models, danger zone)  │
│                       ▼                                              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    CORE ENGINE                               │   │
│  │  ┌────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │   │
│  │  │  Qwen2.5/  │  │  Gecko   │  │  BM25    │  │  SQLite  │  │   │
│  │  │  Gemma LLM │  │ Embedding│  │  FTS5    │  │  (drift) │  │   │
│  │  └────────────┘  └──────────┘  └──────────┘  └──────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. App Initialization Flow (updated 14/06/2026)

```
main()
  │
  ├─ WidgetsFlutterBinding.ensureInitialized()
  ├─ SystemChrome.setPreferredOrientations([portraitUp])
  ├─ Global error handlers (FlutterError + PlatformDispatcher)
  │
  ├─ DEVICE CAPABILITY DETECTION
  │    └─ DeviceCapability.detectTier()
  │         ├─ Android: physicalRamSize (MB) → convert GB
  │         └─ iOS: infer từ model name
  │    Log: 📱 [Device] Tier: X, contextWindow: Y
  │
  ├─ FlutterGemma.initialize()            // Load native libs
  ├─ setupLocator()                       // DI Registration
  │    │
  │    ├─ AppDatabase                     // SQLite drift
  │    ├─ ModelManagerService             // Download/load/delete/switch models
  │    ├─ GemmaService                    // LLM wrapper (+ switchModel!)
  │    ├─ GeckoService → GeckoRetryService
  │    ├─ Bm25Service → Bm25ServiceImpl
  │    ├─ VectorStoreService
  │    ├─ RagService → RagServiceImpl
  │    ├─ PromptBuilder → PromptBuilderImpl
  │    ├─ SummaryService + MemoryStoreService
  │    ├─ DocumentUploadQueue
  │    └─ Blocs: ModelBloc (dynamic state), SessionBloc, ChatBloc, KnowledgeBloc
  │
  ├─ GemmaService.initialize(maxTokens: contextWindow)  ← GRACEFUL
  │    └─ Nếu chưa có model: log warning, _model=null (không crash)
  │       ModelBloc sẽ init sau khi download → switchModel()
  │
  └─ runApp(App())
       │
       ├─ MultiBlocProvider (4 singletons: Model, Session, Knowledge, SessionFiles)
       │    └─ ModelBloc dispatch StatusChecked → kiểm tra active model đã download chưa
       ├─ GoRouter (/ → /chat/:id → /knowledge → /settings → /settings/models)
       └─ ModelOnboardingCoordinator → show dialog nếu chưa có LLM model
            └─ Mặc định: Qwen2.5-1.5B (1.5GB) + Gecko (111MB)
```

---

## 3. Chat Flow (Chi tiết từng bước)

```
USER GỬI MESSAGE
  "cách phòng trừ sâu bệnh"
  │
  ▼
1. GUARD CHECKS
    ├─ isClosed? → return
    ├─ _currentSessionId? → return
    ├─ state is ChatStreaming? → return (block double send)
    ├─ _isWaitingForModel? → return
    └─ Gemma isReady?
         ├─ NO → check ModelLoaded:
         │     ├─ Active model downloaded? → subscribe ModelBloc, wait
         │     └─ Active model NOT downloaded? → ChatError(needsModelDownload)
         └─ YES → continue
  │
  ▼
2. SAVE USER MESSAGE → DB → emit ChatThinking
  │
  ▼
3. DYNAMIC BUDGET ALLOCATION [VERSION=dynamic_budget_v3]
    ContextBudget.forQuery("cách phòng trừ sâu bệnh")
      → QueryType.factual
    Allocation: history=205, rag=1188, response=512 (contextWindow=2048)
  │
  ▼
4. HYBRID SEARCH (RAG) [VERSION=hybrid_v1]
    RagService.retrieve(query, tokenBudget=1178, scope, sessionId)
      ├─ Embed → Gecko (947ms)
      ├─ Dense search (topK=50)
      ├─ Sparse search → BM25 FTS5 (topK=50)
      ├─ RRF fusion (k=60) hoặc fallback
      └─ Try-fit packing → RagContext(chunks, tokenCount, bestScore)
  │
  ▼
5. BUILD TURN PAYLOAD [VERSION=session_api_v1]
    PromptBuilder.buildTurnPayload(question, ragContext)
    → "=== Reference Documents ===\n[Document 1]...\n=== Current Question ==="
    (~300-800 chars)
  │
  ▼
6. CHECK SESSION HEALTH
    if (!_gemmaService.hasActiveSession) → _recreateSession()
  │
  ▼
7. STREAM RESPONSE
    GemmaService.generateWithSession(turnPayload)
    → Stream<String> → emit ChatStreaming
  │
  ▼
8. SAVE & COMPLETE
    ├─ Save assistant message → DB
    ├─ _tryTriggerAutoSummary()
    └─ emit ChatLoaded
```

---

## 4. Multi-Model Operation Flow (NEW 14/06/2026)

### Switch Model
```
User selects model in ModelManagerPage (radio) or SettingsPage (dropdown)
  │
  ▼
ActiveModelChanged(fileName)
  │
  ├─ _modelManager.setActiveLlmModel(fileName)  // Persist to SharedPreferences
  │
  ├─ isModelDownloaded(fileName)?
  │    ├─ YES → getModelPath() → _gemmaService.switchModel(path)
  │    │           ├─ _closeSessionInternal()
  │    │           ├─ _model = null
  │    │           ├─ FlutterGemma.installModel().fromFile(path).install()
  │    │           ├─ FlutterGemma.getActiveModel(maxTokens, gpu)
  │    │           └─ _model ready → gemmaReady = true
  │    │
  │    └─ NO → _gemmaService.closeSession() (chỉ close, không switch)
  │              → gemmaReady = false (model chưa tải)
  │
  ├─ emit ModelLoaded(activeLlmFileName: fileName, gemmaReady)
  └─ Log: [ModelBloc] ActiveModelChanged: fileName
```

### Download Model
```
ModelDownloadRequested(fileName)
  │
  ├─ ModelManagerService.downloadModel(fileName)
  │    └─ _startDownload() → progress stream → _ProgressUpdate events
  │
  └─ Khi download xong:
       ├─ ModelBloc._onProgressUpdate()
       │    └─ activeModel.status == downloaded → _tryInitializeActiveModel()
       │         └─ GemmaService.switchModel(path) → init
       └─ emit ModelLoaded(gemmaReady: true)
```

### Delete Model
```
ModelDeleted(fileName)
  │
  ├─ wasActive = (fileName == activeLlmFileName)?
  │    ├─ YES → _gemmaService.closeSession()
  │    └─ NO → skip
  │
  ├─ ModelManagerService.deleteModel(fileName)
  │    └─ Xoá file + reset status
  │
  ├─ if wasActive:
  │    ├─ setActiveLlmModel(kDefaultModelFileName)  // Fallback về Qwen2.5
  │    └─ if default downloaded → switchModel(defaultPath)
  │
  └─ emit ModelLoaded(activeLlmFileName: default, gemmaReady)
```

---

## 5. Streaming Cancelled Flow

```
User nhấn Stop
  │
  ▼
StreamingCancelled event
  │
  ├─ state is ChatStreaming? → YES
  ├─ _gemmaService.closeSession()       // Fix Bug C
  ├─ _accumulatedText.isEmpty?
  │    ├─ KHÔNG → Lưu partial response + "(Đã dừng)" → DB
  │    └─ CÓ → Không lưu
  └─ Emit: ChatLoaded (messages)
```

---

## 6. Session Init Flow

```
ChatPage mount(sessionId)
  │
  ▼
SessionInitialized(sessionId)
  │
  ├─ emit ChatLoading
  ├─ load messages từ SQLite
  ├─ hydrate KnowledgeScope từ DB
  ├─ Nếu !gemmaService.isReady → skip session creation, emit ChatLoaded(messages)
  │
  ├─ Kiểm tra SessionMemory (summary)
  │    ├─ Có summary → MemoryPromptFormatter.build(summary, memories)
  │    └─ Không summary → PromptBuilder.buildSystemInstruction(memories)
  │    → createSession(systemInstruction)
  │
  ├─ Replay history (MỘT LẦN, 35% budget)
  └─ emit ChatLoaded(messages)
```

---

## 7. Document Upload Flow (RAG Ingestion)

```
User chọn file (PDF/DOCX/TXT/MD)
  │
  ▼
FilePicker (allowMultiple)
  → DocumentRepository.insertDocument(status=pending)
  → DocumentUploadQueue.enqueue(job)
  │
  ▼
_processNext() → _processJob()
  ├── Step 1: PARSE (0.00 → 0.10)
  ├── Step 2: CHUNK (0.10 → 0.20)  [chunkSize=200, overlap=50]
  ├── Step 3: EMBED (0.20 → 0.95)  [Progressive per chunk]
  │    ⚠️ Guard: if (!_gecko.isReady) → throw UploadQueueException
  ├── Step 4a: INSERT DB (0.95 → 1.00)
  │    └─ ChunksCompanion + Vector insert batch
  ├── Step 4b: INDEX BM25
  │    └─ _bm25Service.indexChunks(chunks) → FTS5
  └── Step 5: FINALIZE
       └─ status=completed, chunkCount updated
```

---

## 8. Clear All Data Flow (NEW 14/06/2026)

```
SettingsPage → "Xoá tất cả dữ liệu" → confirm dialog
  │
  ▼
_executeClearAllData()
  │
  ├─ _gemmaService.closeSession()
  ├─ Raw SQL: DELETE FROM vectors, chunks, messages, session_document_refs,
  │           session_memory, user_memory, documents, sessions, chunks_fts
  ├─ SharedPreferences.remove('active_llm_model', 'hasSeenModelOnboarding')
  ├─ Log success
  ├─ Refresh: ModelBloc.StatusChecked, SessionBloc.SessionsLoaded,
  │           KnowledgeBloc.DocumentsLoaded
  └─ SnackBar "Đã xoá toàn bộ dữ liệu"
```

---

## 9. Reindex Flow (NEW 14/06/2026)

```
SettingsPage → "Đánh chỉ mục lại" → confirm dialog
  │
  ▼
_executeReindex()
  │
  ├─ DELETE vectors, chunks, chunks_fts
  ├─ UPDATE documents SET status = pending, progress = 0
  ├─ Enqueue all documents → DocumentUploadQueue
  └─ SnackBar "Đã bắt đầu đánh chỉ mục lại N documents"
```

---

## 10. Error Handling Map

```
┌─────────────────────────────────────────────────────────────────┐
│                    ERROR HANDLING MAP                           │
│                                                                  │
│  ModelNotLoadedException → needsModelDownload=true → Download UI│
│  ModelTimeoutException → ChatError → Thử lại                    │
│  DocumentParseException → SnackBar error                         │
│  EmbeddingException → error log + retry                          │
│  StorageException → error log                                    │
│  UploadQueueException → status=failed, retry button              │
│                                                                  │
│  GemmaService.initialize() fail → GRACEFUL: log + _model=null   │
│  GemmaService.switchModel() fail → ModelNotLoadedException      │
│                                                                  │
│  ⚠️ Session closed (Bad state)                                  │
│     → Guard hasActiveSession → _recreateSession()                │
│                                                                  │
│  ⚠️ BM25 search error                                           │
│     → Graceful degradation → fallback dense search              │
│                                                                  │
│  ⚠️ GPU crash (clEnqueueReadBuffer)                             │
│     → Đã giảm thiểu: turn payload 300-800 chars (vs 2500)       │
│     → App restart required                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. Data Flow Diagram (Tổng thể)

```
┌─────────┐    ┌──────────────┐    ┌───────────────┐    ┌──────────┐
│  USER   │───▶│   ChatBloc    │───▶│  RagService   │───▶│ Gecko    │
│  Input  │    │              │    │ (hybrid_v1)   │    │ Embed    │
└─────────┘    │ sendMessage() │    │               │    └────┬─────┘
               │              │    │ retrieve()    │         │
               │              │    │               │         ▼
               │              │    │          ┌──────────┐
               │              │    │          │ Vector   │
               │              │    │          │ Store    │
               │              │    │          │ (dense)  │
               │              │    │          └────┬─────┘
               │              │    │               │
               │              │    │          ┌──────────┐
               │              │    │          │ Bm25     │
               │              │    │          │ (sparse) │
               │              │    │          └────┬─────┘
               │              │    └───────────────┼─────────┘
               │              │                    │
               │              │              ┌─────▼──────┐
               │              │              │   RRF      │
               │              │              │   Fusion   │
               │              │              └─────┬──────┘
               │              │                    │
               │              │              ┌─────▼──────┐
               │              │              │ Try-fit    │
               │              │              │ Packing    │
               │              │              └─────┬──────┘
               │              │                    │
               │              │              RagContext
               │              │                    │
               │              ├────────────────────┘
               │              │
               │    ┌─────────▼──────────┐
               │    │ PromptBuilder       │
               │    │ buildTurnPayload()  │
               │    │ (RAG + question)    │
               │    └─────────┬──────────┘
               │              │
               │    ┌─────────▼──────────┐
               │    │ GemmaService        │
               │    │ generateWithSession │
               │    │ → Stream<String>    │
               │    └─────────┬──────────┘
               │              │
               │    ┌─────────▼──────────┐
               │    │   Streaming UI     │
               │    │   (token by token) │
               └───▶│                    │
                     │ ChatStreaming emit  │
                     │ Markdown render    │
                     └────────────────────┘