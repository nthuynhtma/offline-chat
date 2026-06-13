# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4-E2B (flutter_gemma ^0.16.4)** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã migrate sang **Session-based API** (không còn prompt-based). Auto Summary + Persistent User Memory đã triển khai. Attached Files + Knowledge Scope + RAG completed-only filter đã triển khai.

**13/06/2026 (Evening):** Hoàn thành **2/5 giải pháp tối ưu** + **DeviceCapability**:
- ✅ **Solution 1: Dynamic Budget Allocation** (`VERSION=dynamic_budget_v3`) — Phân bổ context budget động theo **8 loại câu hỏi** (conversational/factual/complex/creative/summarization/translation/mathCoding/multiHop). Hỗ trợ song ngữ Việt-Anh. Query classification bằng heuristics (không dùng model). Session init giữ 35% history riêng.
- ✅ **Solution 2: Hybrid Search BM25** (`VERSION=hybrid_v1`) — Kết hợp dense search (Gecko) + sparse search (BM25 FTS5) + Reciprocal Rank Fusion. Graceful degradation fallback nếu 1 trong 2 nguồn rỗng. topK tăng 20→50.
- ✅ **DeviceCapability** — Tự động detect RAM/thiết bị để điều chỉnh context window: high (≥8GB) = 4096, medium (6GB) = 2048, low (≤4GB) = 1024 tokens.
- ⏸️ **Solution 3: Query Rewriting** — DEFER P2 (lý do: `generate()` destroys active session, TTFT +100%, redundant với hybrid search)
- ⬜ **Solution 4: Contextual Chunking** — Chưa implement
- ⬜ **Solution 5: Multi-Tier Memory** — Chưa implement

---

## Cách dùng tài liệu này
1. **File này** — tổng quan, ongoing issues, fix history
2. `architecture.md` — kiến trúc chi tiết, data flow, service descriptions
3. `coding_conventions.md` — trước khi viết code
4. `api_contracts.md` — interface contracts
5. `implementation_examples.md` — code mẫu thực tế
6. `pitfalls.md` — các lỗi thường gặp và cách tránh

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
| BM25 Search | SQLite FTS5 (virtual table) | Built-in |
| File Parsing | syncfusion_flutter_pdf | ^33.2.10 |
| DI | get_it | ^9.2.1 |
| Navigation | go_router | ^17.3.0 |
| Markdown Rendering | flutter_markdown_plus | ^1.0.7 |
| Scroll Detection | scrollview_observer | ^1.27.0 |
| Device Detection | device_info_plus | ^12.4.0 |

---

## Nguyên tắc tuyệt đối
- ❌ KHÔNG dùng bất kỳ API cloud nào (OpenAI, Firebase, Supabase...)
- ❌ KHÔNG dùng http package để gọi AI endpoint
- ✅ Tất cả inference chạy on-device
- ✅ Offline-first: app hoạt động hoàn toàn khi tắt mạng
- ✅ Mọi state đi qua Bloc, không dùng `setState` ở business logic
- ❌ KHÔNG dùng `GemmaService.generate()` cho query rewriting — nó destroys active session (LiteRT chỉ support 1 session)

---

## Ongoing Issues

- 🔴 **P0 — GPU crash** (`clEnqueueReadBuffer` / `litert_tensor_buffer.h:748`) — **Đã giảm thiểu nhờ Session API fix + turn payload giảm + DeviceCapability low-tier (1024 tokens).** Dynamic Budget giúp factual queries dành 58% budget cho RAG (1188 tokens) mà không crash. Cần test thêm với nhiều chunks hơn. *(13/06/2026)*
- 🟡 **P1 — Gecko_256_quant discrimination** — **Đã giảm thiểu nhờ Hybrid Search BM25.** BM25 boost keyword matching, RRF fusion kết hợp cả semantic + keyword scores. Cần đánh giá định lượng sau khi có dữ liệu test. *(13/06/2026)*
- 🔵 **P2 — RAG packing density** — packed=1 với budget 500 tokens, mỗi chunk ~300 tokens → chỉ fit 1 chunk. packed=2 đạt được ở chunkSize=200 với 4 chunks. Cần đánh giá thêm. *(12/06/2026)*

---

## Các vấn đề đã fix gần đây

| Vấn đề | Fix | Ngày |
|--------|-----|------|
| **Hai pipeline indexing song song** | Merge pipeline: import → chỉ enqueue, queue xử lý parse/chunk/embed/completed | 11/06/2026 |
| **ChatPage 1223 dòng** | Tách 11 widget con, giảm 85% code | 11/06/2026 |
| **Gecko guard không log chi tiết** | Thêm logging ModelBloc, GeckoServiceImpl, queue guard | 11/06/2026 |
| **RAG matched=2 returned=0** | Try-fit packing (continue oversized, greedy knapsack) | 12/06/2026 |
| **Chunk đầu quá lớn (782 tokens)** | chunkSize: 500→250→200, overlap=50, estimateTokens logging | 12/06/2026 |
| **PromptBuilder history duplication** | Exact-match dedup → budget-based truncation (kMaxHistoryTokens=300) | 12/06/2026 |
| **"Laptop" response bug** | P0 logging: sessionActive, prompt head/tail, first 20 tokens, response preview, error | 12/06/2026 |
| **Gemma GPU crash** | Đang điều tra: prompt size vs RAG content formatting | 12/06/2026 |
| **Double-nested prompt (Bug Laptop root cause)** | Refactor Session API: `createSession()` chỉ system instruction, `generateWithSession()` chỉ turn payload, PromptBuilder tách 2 methods. Loại bỏ hoàn toàn double-nesting. | 13/06/2026 |
| **Stop không dừng (Bug C)** | Thêm `_gemmaService.closeSession()` trong `_onStreamingCancelled` để dừng stream thực sự | 13/06/2026 |
| **Bug A temp fix (recreate session cho RAG)** | Xóa — không còn cần sau refactor Session API | 13/06/2026 |
| **Dynamic Budget Allocation** | Thêm `budget_allocation.dart` (QueryType, ContextBudget, BudgetAllocation). Sửa `chat_bloc.dart`: phân bổ budget động theo loại câu hỏi. Session init giữ 35% riêng (`kSessionInitHistoryRatio`). | 13/06/2026 |
| **Hybrid Search BM25** | Thêm `bm25_service.dart` + `bm25_service_impl.dart` (FTS5 + RRF). Sửa `rag_service_impl.dart`: hybrid search pipeline (dense→sparse→RRF→try-fit). Sửa `document_upload_queue.dart`: BM25 indexing step. DB schemaVersion 4→5. | 13/06/2026 |
| **Dynamic contextWindow theo thiết bị** | Thêm `device_capability.dart` (3-tier: 4096/2048/1024). Sửa `main.dart` + `service_locator.dart`. Dùng `device_info_plus` để detect RAM. | 13/06/2026 |

---

## Version Markers (runtime verification)

| File | Marker | Mục đích | Thêm |
|------|--------|---------|------|
| `rag_service_impl.dart` | `VERSION=try_fit_v2` | Verify RAG packing code đang chạy | 12/06/2026 |
| `rag_service_impl.dart` | `VERSION=hybrid_v1` | Verify hybrid search (dense+sparse+RRF) đang chạy | 13/06/2026 |
| `prompt_builder_service.dart` | `VERSION=session_api_v1` | Verify PromptBuilder code mới (buildSystemInstruction + buildTurnPayload) | 13/06/2026 |
| `budget_allocation.dart` | `VERSION=dynamic_budget_v3` | Verify Dynamic Budget Allocation code đang chạy (8 query types) | 13/06/2026 |
| `bm25_service_impl.dart` | `VERSION=bm25_v1` | Verify BM25 FTS5 implementation đang chạy | 13/06/2026 |
| `chat_bloc.dart` | `VERSION=dynamic_budget_v3` (log) | Verify budget phân bổ động trong log | 13/06/2026 |
| `device_capability.dart` | — | Log: 📱 [Device] Tier: high/medium/low, contextWindow: N | 13/06/2026 |

---

## Constraints quan trọng cần nhớ

- **LiteRT LM:** Chỉ support **1 session tại 1 thời điểm**. Legacy `generate()` / `generateStream()` invalidates session → luôn kiểm tra `hasActiveSession` trước khi gọi `generateWithSession()` (guard tại `chat_bloc.dart:389`).
- **`GemmaService.generate()` DESTROYS active session** — KHÔNG dùng cho query rewriting hoặc bất kỳ mục đích nào khi đang chat. Nếu cần generate tạm, dùng `createSession()` + `generateWithSession()` + `closeSession()` riêng.
- **Token budget:** Mặc định `kGemmaMaxTokens=2048`. Thực tế được detect từ thiết bị: high=4096, medium=2048, low=1024. Lưu trong `DeviceCapabilityHolder.contextWindow`.
- **Dynamic Budget (v3):** Budget được phân bổ động theo **8** `QueryType`: conversational, factual, complex, creative, summarization, translation, mathCoding, multiHop. Hỗ trợ song ngữ Việt-Anh. Session init dùng `kSessionInitHistoryRatio=0.35` riêng. File: `lib/core/constants/budget_allocation.dart`.
- **chunkSize runtime:** `200`, `overlap=50` — set trong `DocumentUploadQueue`, không phải `ChunkingService` default.
- **estimateTokens:** `chars / 2.5` — single source of truth cho mọi nơi (RAG packing, PromptBuilder, chunk logging).
- **RAG filter:** Chỉ lấy `status=completed`. Documents đang indexing không được đưa vào RAG.
- **ChatBloc scope:** Factory (mỗi session 1 instance). Các Bloc còn lại: LazySingleton.
- **Session API usage đúng cách:** `createSession()` chỉ nhận system instruction (system + memories + summary). `generateWithSession()` chỉ nhận turn payload (RAG context + question). History được replay qua `addHistoryMessage()` MỘT LẦN lúc init session. **KHÔNG gửi full prompt** qua `generateWithSession()` — tránh double-nesting.
- **PromptBuilder 2 methods:** `buildSystemInstruction()` → cho `createSession()`. `buildTurnPayload()` → cho `generateWithSession()`. KHÔNG dùng `build()` cũ cho chat turns (chỉ dùng cho SummaryService legacy).
- **Turn payload size:** RAG + question ≈ ~300-800 chars (thay vì ~2500-3300 chars trước đây). Giảm áp lực GPU.
- **Hybrid Search Fallback:** Nếu BM25 không tìm thấy kết quả, tự động fallback về dense search. Nếu cả 2 rỗng → skip RAG.
- **DeviceCapability:** Detect device tier từ physical RAM (Android) hoặc model name (iOS). Chạy 1 lần ở `main()`.
- **`_recreateSession()`:** Fallback khi session bị mất giữa chừng (hiếm). Tạo session mới + replay history.

---

## Performance thực tế (GPU, Gemma 4-E2B, verified 13/06/2026)

| Metric | Không RAG (34 chars) | Có RAG (313 chars) |
|--------|---------------------|--------------------|
| TTFT (prefill) | **1.2 giây** 🚀 | **6.7 giây** |
| Total generation | 27.5 giây (188 tok) | 26.2 giây (167 tok) |
| Throughput | ~7.1 tok/s | **~8.5 tok/s** 🚀 |
| Embedding latency | — | ~947ms |
| Search latency | — | ~86ms |

| Metric | Giá trị |
|--------|---------|
| GPU crash rate (tested) | **~0%** (0 crash / 2 queries + 4 file uploads) ✅ |
| Cold start (bao gồm model init) | ~13 giây |
| Device tiers | high=4096, medium=2048, low=1024 |

⚠️ GPU crash khi prompt có RAG chunks — đã giảm thiểu nhờ turn payload giảm + dynamic budget + device-aware context window, nhưng vẫn cần theo dõi thêm.