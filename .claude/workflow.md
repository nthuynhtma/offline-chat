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
│                       │                                              │
│                       ▼                                              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    CORE ENGINE                               │   │
│  │  ┌────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │   │
│  │  │  Gemma LLM │  │  Gecko   │  │  BM25    │  │  SQLite  │  │   │
│  │  │  (4-E2B)   │  │ Embedding│  │  FTS5    │  │  (drift) │  │   │
│  │  └────────────┘  └──────────┘  └──────────┘  └──────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. App Initialization Flow

```
main()
  │
  ├─ FlutterGemma.initialize()            // Load native libs
  │
  ├─ setupLocator()                       // DI Registration
  │    │
  │    ├─ AppDatabase                     // SQLite drift
  │    ├─ ModelManagerService             // Download/load models
  │    ├─ GemmaService                    // LLM wrapper
  │    ├─ GeckoService → GeckoRetryService
  │    ├─ Bm25Service → Bm25ServiceImpl    // [NEW] FTS5 search
  │    ├─ VectorStoreService              // Cosine similarity
  │    ├─ RagService → RagServiceImpl     // Hybrid search
  │    ├─ PromptBuilder → PromptBuilderImpl
  │    ├─ SummaryService                  // Auto-summary
  │    ├─ MemoryStoreService              // User memory
  │    ├─ DocumentUploadQueue             // File processing pipeline
  │    └─ Blocs: ModelBloc, SessionBloc, ChatBloc, KnowledgeBloc
  │
  └─ runApp(App())
       │
       ├─ MultiBlocProvider (4 singletons: Model, Session, Knowledge, SessionFiles)
       ├─ GoRouter (/ → /chat/:id → /knowledge → /settings/models)
       └─ ModelOnboardingCoordinator      // Check & prompt download
```

---

## 3. Chat Flow (Chi tiết từng bước)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ USER GỬI MESSAGE                                                               │
│                                                                                 │
│  "cách phòng trừ sâu bệnh"                                                     │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 1. GUARD CHECKS                                                                 │
│                                                                                 │
│    ├─ isClosed? → return                                                        │
│    ├─ _currentSessionId? → return                                               │
│    ├─ state is ChatStreaming? → return (block double send)                      │
│    ├─ _isWaitingForModel? → return                                              │
│    └─ Gemma isReady?                                                            │
│         ├─ NO → subscribe ModelBloc, _isWaitingForModel=true, return            │
│         └─ YES → continue                                                       │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 2. SAVE USER MESSAGE → DB                                                       │
│                                                                                 │
│    Log: 💾 [SendMessage] Đã lưu user message vào DB (id=xxx)                    │
│    Emit: ChatThinking (messages)                                                │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 3. DYNAMIC BUDGET ALLOCATION  [VERSION=dynamic_budget_v1]                      │
│                                                                                 │
│    ContextBudget.forQuery("cách phòng trừ sâu bệnh")                            │
│      │                                                                          │
│      ├─ "cách phòng trừ sâu bệnh" → _classifyQuery()                           │
│      │                                                                          │
│      │  Query Classification (heuristics, không dùng model):                    │
│      │  ┌──────────────────────────────────────────────────────────────────┐    │
│      │  │ regex: ^(hi|hello|chào) → greeting → conversational             │    │
│      │  │ chứa: "bạn là ai", "giúp gì" → capability → conversational      │    │
│      │  │ length < 15 ký tự → conversational                               │    │
│      │  │ chứa: "phân tích", "tại sao" → complex                           │    │
│      │  │ default → factual                                                │    │
│      │  └──────────────────────────────────────────────────────────────────┘    │
│      │                                                                          │
│      └─ Kết quả: QueryType.factual                                             │
│                                                                                 │
│    Budget Allocation (2048 tokens):                                             │
│    ┌──────────────┬────────┬────────┬─────────┬──────┬──────────┬───────┐      │
│    │ Query Type   │ System │ Memory │ History │ RAG  │ Response │ Total │      │
│    ├──────────────┼────────┼────────┼─────────┼──────┼──────────┼───────┤      │
│    │ conversational│ 205    │ 102    │ 922     │ 307  │ 512      │ 2048  │      │
│    │ factual      │ 102    │ 41     │ 205     │ 1188 │ 512      │ 2048  │      │
│    │ complex      │ 102    │ 102    │ 410     │ 922  │ 512      │ 2048  │      │
│    └──────────────┴────────┴────────┴─────────┴──────┴──────────┴───────┘      │
│                                                                                 │
│    questionTokens = 10 (ước lượng)                                              │
│    ragBudget = 1188 - 10 = 1178 tokens                                          │
│                                                                                 │
│    Log: 📊 [Budget] VERSION=dynamic_budget_v1                                   │
│         queryType=factual, actualHistory=15/205, rag=1178/1188                  │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 4. HYBRID SEARCH (RAG)  [VERSION=hybrid_v1]                                    │
│                                                                                 │
│    RagService.retrieve(query, tokenBudget=1178, scope, sessionId)               │
│      │                                                                          │
│      ├─ 4a. EARLY EXIT GUARD                                                   │
│      │    ├─ tooShort: ≤2 từ, không ?, <15 ký tự? → NO                         │
│      │    ├─ greeting: hi/hello/chào? → NO                                     │
│      │    └─ capability: bạn là ai? → NO                                       │
│      │    → continue                                                           │
│      │                                                                          │
│      ├─ 4b. EMBED QUERY                                                        │
│      │    GeckoService.embed("cách phòng trừ sâu bệnh")                         │
│      │    → List<double>[768] (947ms)                                           │
│      │                                                                          │
│      ├─ 4c. FILTER DOCUMENTS BY SCOPE                                          │
│      │    KnowledgeScope.attachedAndGlobal                                      │
│      │    → getCompletedGlobalDocumentIds()                                     │
│      │    → getCompletedDocumentIdsBySessionId(sessionId)                       │
│      │    → getDocumentIdsBySession(sessionId)                                  │
│      │    → allowedDocIds = {doc1, doc2, doc3} (15 chunks)                      │
│      │                                                                          │
│      ├─ 4d. DENSE SEARCH (Gecko)                                               │
│      │    VectorStoreService.search(queryVector, topK=50, threshold=0.7)        │
│      │    → 2-step: filter → preTopK(200) → cosine → re-rank → topK(50)       │
│      │    → denseResults = [chunkA(0.855), chunkB(0.823), ...]                 │
│      │                                                                          │
│      ├─ 4e. SPARSE SEARCH (BM25)  [VERSION=bm25_v1]                            │
│      │    Bm25Service.search(query, allowedDocIds, topK=50)                     │
│      │      ├─ sanitize: "cách phòng trừ sau bệnh" → ""cách phòng trừ sau      │
│      │      │            bệnh"" (phrase search)                                 │
│      │      ├─ FTS5 MATCH query                                                 │
│      │      ├─ BM25 ranking + filter by document_id                             │
│      │      └─ sparseResults = [...] (nếu có)                                   │
│      │    Log: 🔍 [BM25] Searching: query="..." sanitized="..."                 │
│      │                                                                          │
│      │    ⚠️ Graceful Degradation:                                              │
│      │    ├─ Cả 2 rỗng → skip RAG                                               │
│      │    ├─ Dense rỗng → fallback sparse                                       │
│      │    ├─ Sparse rỗng → fallback dense          ← Trường hợp này            │
│      │    └─ Cả 2 có → RRF fusion                                                │
│      │                                                                          │
│      ├─ 4f. RECIPROCAL RANK FUSION (nếu cả 2 có kết quả)                       │
│      │    RRF(denseResults, sparseResults, k=60):                               │
│      │    ┌────────────────────────────────────────────────────────────────┐    │
│      │    │ score(chunk) = Σ 1/(k + rank_dense + 1) + 1/(k + rank_sparse+1)│    │
│      │    │ Sort desc → fusedResults                                         │    │
│      │    └────────────────────────────────────────────────────────────────┘    │
│      │    Log: [RAG] VERSION=hybrid_v1 dense=1 sparse=0 fused=1                │
│      │                                                                          │
│      └─ 4g. TRY-FIT PACKING  [VERSION=try_fit_v2]                              │
│           effectiveCap = min(tokenBudget=1178, kMaxRagTokens=500) = 500         │
│           labelTokenOverhead = ~4 tokens                                        │
│           ┌─────────────────────────────────────────────────────────────┐       │
│           │ for (chunk in results sorted by score desc):                │       │
│           │   if (chunkCount >= kMaxRagChunks=3) break                  │       │
│           │   if (chunkToken > effectiveCap) continue  // skip oversized│       │
│           │   if (tokenSum + chunkToken <= effectiveCap):               │       │
│           │     trimmed.add(chunk)                                      │       │
│           │     tokenSum += chunkToken                                   │       │
│           │     chunkCount++                                             │       │
│           │     if (tokenSum >= effectiveCap) break                     │       │
│           └─────────────────────────────────────────────────────────────┘       │
│           Log: [RAG] packing matched=1 packed=1 tokens=94 cap=500               │
│                                                                                 │
│    Return: RagContext(chunks=[phong_tru_sau_benh], tokenCount=94, bestScore=0.855)
│                                                                                 │
│    Total retrieval time: 1033ms (embed 947ms + search 86ms)                     │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 5. BUILD TURN PAYLOAD  [VERSION=session_api_v1]                                 │
│                                                                                 │
│    PromptBuilder.buildTurnPayload(                                              │
│      question: "cách phòng trừ sâu bệnh",                                       │
│      ragContext: RagContext(1 chunk, 94 tokens)                                 │
│    )                                                                            │
│      │                                                                          │
│      └─ Kết quả (313 chars):                                                   │
│         ┌────────────────────────────────────────────────────────────┐          │
│         │ === Reference Documents ===                               │          │
│         │                                                           │          │
│         │ [Document 1]                                              │          │
│         │ PHÒNG TRỪ SÂU BỆNH                                        │          │
│         │                                                           │          │
│         │ 1. Kiểm tra vườn thường xuyên                             │          │
│         │ 2. Sử dụng giống kháng bệnh                               │          │
│         │ 3. Bón phân hợp lý                                        │          │
│         │ 4. Sử dụng thuốc bảo vệ thực vật                          │          │
│         │ 5. Vệ sinh vườn sạch sẽ                                   │          │
│         │                                                           │          │
│         │ === Current Question ===                                  │          │
│         │ cách phòng trừ sau bệnh                                   │          │
│         └────────────────────────────────────────────────────────────┘          │
│                                                                                 │
│    Log: 🔨 [PromptBuilder] Turn payload built (313 chars, hasRAG=true)          │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 6. CHECK SESSION HEALTH                                                         │
│                                                                                 │
│    if (!_gemmaService.hasActiveSession) → _recreateSession()                    │
│      ├─ Build system instruction (từ summary hoặc default)                      │
│      ├─ createSession(systemInstruction)                                        │
│      └─ Replay history (35% budget)                                             │
│                                                                                 │
│    Session OK → continue                                                       │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 7. STREAM RESPONSE                                                              │
│                                                                                 │
│    GemmaService.generateWithSession(turnPayload=313 chars)                      │
│      │                                                                          │
│      ├─ [FfiInferenceModelSession/perf] time-to-first-chunk (prefill): 6691ms  │
│      │                                                                          │
│      ├─ Log: prompt head (500 chars)                                            │
│      │                                                                          │
│      ├─ token[1]  = "Chào"          (22:01:49.044)                             │
│      ├─ token[2]  = " bạn"          (22:01:49.445)                             │
│      ├─ token[3]  = ","             (22:01:49.453)                             │
│      ├─ token[4]  = " để"           (22:01:49.455)                             │
│      ├─ token[5]  = " phòng"        (22:01:49.668)                             │
│      ├─ ...                                                                     │
│      ├─ token[20] = "1"             (22:01:51.262)                             │
│      │                                                                          │
│      ├─ [FfiInferenceModelSession/perf] generation total: 26218ms              │
│      │   (prefill 6691ms + decode 19527ms over 167 chunks, ~8.5 chunks/sec)    │
│      │                                                                          │
│      └─ Log: [Gemma] generateWithSession hoàn tất: 167 tokens                  │
│                                                                                 │
│    Emit: ChatStreaming (messages, streamingText, streamingId, ragResults)       │
└───────────────────────────┬─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 8. SAVE & COMPLETE                                                              │
│                                                                                 │
│    ├─ Save assistant message → DB                                               │
│    ├─ updateSessionTimestamp()                                                  │
│    ├─ _tryTriggerAutoSummary()                                                  │
│    │    └─ Kiểm tra runningTokenCount > summaryTrigger?                        │
│    │         ├─ YES → unawaited(_runAutoSummary())                              │
│    │         └─ NO → updateRunningTokenCount()                                  │
│    ├─ Emit: ChatLoaded (finalMessages)                                          │
│    └─ Log: ✅ [SendMessage] Hoàn tất: 2 messages                                │
│         Assistant response: "Chào bạn, để phòng trừ sâu bệnh..."               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Streaming Cancelled Flow

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

## 5. Session Init Flow

```
ChatPage mount(sessionId)
  │
  ▼
SessionInitialized(sessionId)
  │
  ├─ emit ChatLoading
  ├─ load messages từ SQLite
  ├─ hydrate KnowledgeScope từ DB
  │
  ├─ Kiểm tra SessionMemory (summary)
  │    ├─ Có summary → MemoryPromptFormatter.build(summary, memories)
  │    │              → createSession(systemInstruction)
  │    └─ Không summary → PromptBuilder.buildSystemInstruction(memories)
  │                       → createSession(systemInstruction)
  │
  ├─ Replay history (MỘT LẦN DUY NHẤT)
  │    ├─ Budget: kSessionInitHistoryRatio = 35% = 717 tokens
  │    ├─ Duyệt messages từ cuối lên, fit trong budget
  │    └─ addHistoryMessage(role, content) cho từng message
  │
  └─ emit ChatLoaded(messages)
```

---

## 6. Document Upload Flow (RAG Ingestion)

```
User chọn file (PDF/DOCX/TXT/MD)
  │
  ▼
FilePicker (allowMultiple)
  │
  ▼
DocumentRepository.insertDocument(status=pending)
  │
  ▼
DocumentUploadQueue.enqueue(job)
  │
  ▼
_processNext() → _processJob()
  │
  ├── Step 1: PARSE (0.00 → 0.10)
  │    DocumentParserService.parse(file) → rawText
  │    Log: 💡 [UploadQueue] Processing: filename.pdf
  │
  ├── Step 2: CHUNK (0.10 → 0.20)
  │    ChunkingService.chunk(rawText, chunkSize=200, overlap=50)
  │    Log: Chunks: 8 chunks
  │    Log: chunk[0] chars=751 tokens=301 preview="..."
  │
  ├── Step 3: EMBED (0.20 → 0.95)  [Progressive per chunk]
  │    for each chunk:
  │      _gecko.embed(chunk) → vector[768]
  │      progress = 0.20 + 0.75 * (i/total)
  │
  │    ⚠️ Guard: if (!_gecko.isReady) → throw UploadQueueException
  │
  ├── Step 4a: INSERT DB (0.95 → 1.00)
  │    ├─ Tạo ChunksCompanion (UUID ids)
  │    ├─ _chunksDao.insertChunks()
  │    ├─ _vectorStore.insertBatch()
  │    └─ Log: [UploadQueue] Completed: 8 chunks, 8 vectors
  │
  ├── [NEW] Step 4b: INDEX BM25
  │    _bm25Service.indexChunks(chunks)
  │    Log: 📚 [BM25] Indexed 8 chunks into FTS5
  │
  └── Step 5: FINALIZE
       ├─ _docsDao.updateChunkCount()
       ├─ _docsDao.updateDocumentStatus(completed)
       └─ _resultController.add(success)
```

---

## 7. Hybrid Search Pipeline (Chi tiết)

```
                    ┌─────────────────────────┐
                    │   User Query            │
                    │  "bón phân NPK"         │
                    └───────────┬─────────────┘
                                │
                                ▼
              ┌─────────────────────────────────┐
              │   shouldSkipRag()               │
              │   - tooShort? → NO              │
              │   - greeting? → NO              │
              │   - capability? → NO            │
              │   → CONTINUE                    │
              └─────────────────────────────────┘
                                │
                                ▼
              ┌─────────────────────────────────┐
              │   GeckoService.embed(query)     │
              │   → 768-dim vector              │
              │   Latency: ~947ms               │
              └───────────┬─────────────────────┘
                          │
                          ▼
     ┌─────────────────────────────────────────────────────┐
     │                  SPLIT                               │
     │                                                      │
     │  ┌─────────────────┐     ┌─────────────────┐        │
     │  │ DENSE SEARCH     │     │ SPARSE SEARCH   │        │
     │  │ (Gecko)          │     │ (BM25 FTS5)     │        │
     │  │                  │     │                  │        │
     │  │ topK=50          │     │ topK=50          │        │
     │  │ threshold=0.7    │     │ query sanitize   │        │
     │  │ cosine sim       │     │ BM25 ranking     │        │
     │  │ preTopK=200      │     │ filter by docId  │        │
     │  │                  │     │                  │        │
     │  │ denseResults     │     │ sparseResults    │        │
     │  │ [50 candidates]  │     │ [50 candidates]  │        │
     │  └────────┬─────────┘     └────────┬─────────┘        │
     │           │                        │                   │
     └───────────┼────────────────────────┼───────────────────┘
                 │                        │
                 ▼                        ▼
     ┌──────────────────────────────────────────┐
     │           RRF FUSION                     │
     │                                          │
     │  score(chunk) = Σ 1/(k + rank + 1)      │
     │  k = 60                                  │
     │  Sort desc                               │
     │                                          │
     │  ⚠️ Graceful Degradation:                │
     │  ├─ Cả 2 rỗng → skip RAG                │
     │  ├─ Dense rỗng → dùng sparse            │
     │  ├─ Sparse rỗng → dùng dense            │
     │  └─ Cả 2 có → RRF                       │
     └──────────────────┬───────────────────────┘
                        │
                        ▼
     ┌──────────────────────────────────────────┐
     │        TRY-FIT PACKING                   │
     │                                          │
     │  effectiveCap = min(budget, 500)         │
     │  maxChunks = 3                           │
     │  greedy knapsack                         │
     │                                          │
     │  Kết quả: RagContext                     │
     │  ├─ chunks: [top chunks]                 │
     │  ├─ tokenCount: tổng tokens              │
     │  └─ bestScore: highest score             │
     └──────────────────────────────────────────┘
```

---

## 8. Memory System

```
┌──────────────────────────────────────────────────────────────────┐
│                     MEMORY HIERARCHY                             │
│                                                                  │
│  Tier 1: WORKING MEMORY (Session API KV cache)                  │
│  ├─ Recent 3-5 turns                                             │
│  └─ Tự động quản lý bởi Gemma Session                           │
│                                                                  │
│  Tier 2: SESSION SUMMARY (~160 tokens, 8%)                       │
│  ├─ Lưu trong session_memory table                               │
│  ├─ Auto-summarize khi runningTokenCount > trigger               │
│  └─ Dùng MemoryPromptFormatter.build() khi mở session            │
│                                                                  │
│  Tier 3: USER MEMORY (~40 tokens, 2%)                            │
│  ├─ Lưu trong user_memory table (namespace:key:value)            │
│  ├─ Extract mỗi 5 lần summarize                                  │
│  └─ Dùng buildSystemInstruction() khi tạo session               │
│                                                                  │
│  Tier 4: EPISODIC MEMORY (DB only, chưa implement)               │
│  └─ Full history, search on-demand (P2)                          │
└──────────────────────────────────────────────────────────────────┘

Auto-Summary Trigger:
  runningTokenCount > availableConversationBudget * 0.65
  → _runAutoSummary()
     ├─ incrementalSummarize(oldSummary, newMessages)
     ├─ saveSessionMemory()
     └─ extractUserMemory() mỗi 5 lần
```

---

## 9. Error Handling

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

## 10. Data Flow Diagram (Tổng thể)

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