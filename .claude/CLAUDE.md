# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng **Gemma 4-E2B (flutter_gemma ^0.16.4)** hoặc **Qwen2.5-1.5B** làm LLM và **Gecko 110M** làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response, context management với token budget.

**Trạng thái hiện tại:** Đã migrate sang **Session-based API** (không còn prompt-based). Auto Summary + Persistent User Memory đã triển khai. Attached Files + Knowledge Scope + RAG completed-only filter đã triển khai.

**14/06/2026 (Morning):** Hoàn thành **Full Multi-Model Support**:
- ✅ **Multi-Model:** Hỗ trợ Qwen2.5-1.5B (mặc định) + Gemma 4E2B. User có thể chọn/tải/xoá model từ Settings hoặc ModelManagerPage.
- ✅ **switchModel():** `GemmaService.switchModel(path)` — dispose old → install new → init.
- ✅ **ModelBloc dynamic:** State dùng `List<ModelInfo> llmModels` thay `gemmaInfo` đơn. Events mới: `ModelDownloadRequested`, `ActiveModelChanged`, `ModelDeleted`.
- ✅ **SettingsPage cleanup:** Xoá dead UI (Cấu hình RAG, Cấu hình Chat). Thêm default model selector + available models list. "Xoá tất cả dữ liệu" và "Đánh chỉ mục lại" implement thật.
- ✅ **GemmaService graceful init:** `initialize()` không throw khi chưa có model — chỉ log + set `_model = null`. `ModelBloc` sẽ init sau khi download.
- ✅ **UI overflow fix:** Tên model dài (Qwen2.5) được xử lý với `TextOverflow.ellipsis`.

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

## Multi-Model Support (NEW 14/06/2026)

### Available LLM Models
| Model | File | Size | Default |
|-------|------|------|---------|
| Qwen2.5-1.5B Instruct | `Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm` | 1.49 GB | **Mặc định** |
| Gemma 4E2B IT | `gemma-4-E2B-it.litertlm` | 2.59 GB | |

### Model Registry
**File:** `lib/core/constants/model_constants.dart`
```dart
const List<AvailableModelInfo> kAvailableLlmModels = [
  AvailableModelInfo(name: 'Qwen2.5-1.5B Instruct (mặc định)', ...),
  AvailableModelInfo(name: 'Gemma 4E2B IT', ...),
];
```

### ModelManagerService (mở rộng)
**File:** `lib/services/model_manager/model_manager_service.dart`
```dart
abstract interface class ModelManagerService {
  List<ModelInfo> get allLlmModels;      // Dynamic list
  ModelInfo? get activeLlmModel;         // Active model
  String get activeLlmFileName;          // Persisted in SharedPreferences
  Future<void> setActiveLlmModel(String fileName);
  Future<void> downloadModel(String fileName);  // Generic download
  Future<void> deleteModel(String fileName);    // Delete file + reset status
}
```

### GemmaService — switchModel()
**File:** `lib/services/gemma/gemma_service.dart`
```dart
abstract interface class GemmaService {
  Future<void> switchModel({required String modelPath, int maxTokens});
}
```
Implementation: dispose old model → `FlutterGemma.installModel()` → `FlutterGemma.getActiveModel()`.

### ModelBloc — Dynamic State
```dart
class ModelLoaded extends ModelState {
  final List<ModelInfo> llmModels;           // Thay vì gemmaInfo đơn
  final ModelInfo geckoInfo;
  final bool gemmaReady;
  final bool geckoReady;
  final String activeLlmFileName;            // Mới
}
```
Events mới: `ModelDownloadRequested(fileName)`, `ActiveModelChanged(fileName)`, `ModelDeleted(fileName)`.

### GemmaService.initialize() — Graceful Degradation
```dart
try {
  _model = await FlutterGemma.getActiveModel(...);
} catch (e) {
  log_util.log.w('⚠️ [GemmaService] No model available yet: $e');
  _model = null;  // Không throw — ModelBloc sẽ init sau
}
```

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
| **Full Multi-Model Support** | Thêm Qwen2.5-1.5B, `switchModel()` trong GemmaService, `ModelBloc` dynamic state, `ModelManagerPage` dynamic LLM list + radio active. | **14/06/2026** |
| **SettingsPage cleanup** | Xoá dead UI (Cấu hình RAG, Chat). Thêm default model selector + available models. Implement "Xoá tất cả dữ liệu" + "Đánh chỉ mục lại" thật. | **14/06/2026** |
| **ModelOnboardingCoordinator** | Qwen2.5 default, dùng `ModelDownloadRequested` thay `GemmaDownloadStarted`. | **14/06/2026** |
| **ModelNotLoadedException crash** | `GemmaService.initialize()` graceful degradation — không throw khi chưa có model. `main.dart` wrap try-catch. | **14/06/2026** |

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
| `model_manager_service.dart` | — | Multi-model: `allLlmModels`, `activeLlmFileName`, `downloadModel()`, `deleteModel()` | **14/06/2026** |
| `gemma_service.dart` | — | `switchModel()` — dispose old → install new → init | **14/06/2026** |
| `model_bloc.dart` | — | Dynamic state: `List<ModelInfo> llmModels` + `activeLlmFileName` | **14/06/2026** |

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
- **Multi-Model:** User có thể tải/xoá/chuyển đổi LLM models. Active model persist qua SharedPreferences (`active_llm_model` key). Model mặc định: Qwen2.5-1.5B.
- **`GemmaService.initialize()` không throw:** Khi chưa có model, chỉ log + `_model = null`. ModelBloc sẽ init sau khi download.
- **ModelDeleted fallback:** Nếu xoá active model, tự động chuyển về default (`kDefaultModelFileName`). Nếu default đã download → switch ngay.
- **Qwen2.5 file:** `Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm` (~1.49 GB). Download từ HuggingFace litert-community repo.

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