# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4-E2B (flutter_gemma ^0.16.4)** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã migrate sang **Session-based API** (không còn prompt-based). Auto Summary + Persistent User Memory đã triển khai. Attached Files + Knowledge Scope + RAG completed-only filter đã triển khai.

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

## Ongoing Issues

- 🔴 **P0 — GPU crash** (`clEnqueueReadBuffer` / `litert_tensor_buffer.h:748`) khi prompt có RAG chunks. Đang điều tra: prompt size vs RAG content formatting. Test A: prompt ~2500 chars không RAG. *(12/06/2026)*
- 🟡 **P1 — Gecko_256_quant discrimination** — score ranking gần như không thay đổi giữa các query tiếng Việt khác nhau (`bón phân` vs `sâu bệnh` vs `hướng dẫn`). chunk[0] luôn top 1 bất kể query. chunkSize đã giảm 500→250→200. Cần test lại sau khi fix GPU crash. *(12/06/2026)*
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

---

## Version Markers (runtime verification)

| File | Marker | Mục đích | Thêm |
|------|--------|---------|------|
| `rag_service_impl.dart` | `VERSION=try_fit_v2` | Verify RAG packing code đang chạy | 12/06/2026 |
| `prompt_builder_service.dart` | `VERSION=dedup_v1` | Verify PromptBuilder code đang chạy | 12/06/2026 |

---

## Constraints quan trọng cần nhớ

- **LiteRT LM:** Chỉ support **1 session tại 1 thời điểm**. Legacy `generate()` / `generateStream()` invalidates session → luôn kiểm tra `hasActiveSession` trước khi gọi `generateWithSession()` (guard tại `chat_bloc.dart:389`).
- **Token budget:** `kGemmaMaxTokens=2048`. Không hardcode budget cũ 8000. Xem ratios trong `architecture.md §13`.
- **chunkSize runtime:** `200`, `overlap=50` — set trong `DocumentUploadQueue`, không phải `ChunkingService` default.
- **estimateTokens:** `chars / 2.5` — single source of truth cho mọi nơi (RAG packing, PromptBuilder, chunk logging).
- **RAG filter:** Chỉ lấy `status=completed`. Documents đang indexing không được đưa vào RAG.
- **ChatBloc scope:** Factory (mỗi session 1 instance). Các Bloc còn lại: LazySingleton.

---

## Performance thực tế (GPU, Gemma 4-E2B)

| Metric | Giá trị |
|--------|---------|
| TTFT (~2500 token prompt) | 5–10 giây |
| Throughput | ~7–8 tok/s |
| Embedding latency (Gecko) | ~850ms/chunk |
| Search latency (4 chunks) | < 100ms |
| Cold start (bao gồm model init) | ~13 giây |

⚠️ GPU crash khi prompt có RAG chunks — đang điều tra (12/06/2026).