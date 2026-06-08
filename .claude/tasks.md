# Tasks - Implementation Roadmap

## Trạng thái
- [ ] = Chưa làm
- [~] = Đang làm
- [x] = Hoàn thành

---

## Phase 1 - Foundation ✅ (Hoàn thành)
> Mục tiêu: App chạy được, chat với Gemma, stream response, lưu session

### Setup
- [x] Tạo Flutter project: `flutter create offline_chat --org com.offlinechat`
- [x] Cấu hình `pubspec.yaml` theo `coding_conventions.md` mục Dependencies
- [x] Tạo `analysis_options.yaml`
- [x] Tạo cấu trúc thư mục theo `CLAUDE.md` mục "Cấu trúc thư mục bắt buộc"

### Database
- [x] Tạo Drift tables: `sessions_table.dart`, `messages_table.dart`
- [x] Tạo `app_database.dart` với schema version 1
- [x] Tạo `sessions_dao.dart` và `messages_dao.dart`
- [x] Chạy `dart run build_runner build` để generate `.g.dart` files

### Dependency Injection
- [x] Cài `get_it`
- [x] Tạo `injection/service_locator.dart` với đủ registrations Phase 1

### Services - Phase 1
- [x] `GemmaService` - implement `initialize()`, `isReady`, `generateStream()`
- [x] `PromptBuilderService` - implement `build(BuiltContext)`

### Repositories - Phase 1
- [x] `SessionRepositoryImpl`
- [x] `MessageRepositoryImpl`

### Blocs - Phase 1
- [x] `SessionBloc` - đủ events: Loaded, Created, Selected, Deleted
- [x] `ChatBloc` - đủ events: SessionInitialized, SendMessageRequested, StreamingCancelled, MessagesCleared

### UI - Phase 1
- [x] `SessionListPage` - danh sách sessions, nút tạo mới, empty state, error state
- [x] `ChatPage` + `ChatView`
- [x] `MessageBubble` widget - user vs assistant style khác nhau
- [x] `StreamingMessageBubble` - hiển thị text đang stream (trong MessageBubble)
- [x] `ChatInputBar` - text field + send button, disabled khi streaming
- [x] `ModelNotReadyBanner` - hiển thị khi model chưa load

### Navigation
- [x] Cấu hình `GoRouter` với routes:
  - `/` → SessionListPage
  - `/chat/:sessionId` → ChatPage
  - `/knowledge` → KnowledgePage
  - `/settings` → SettingsPlaceholderPage
  - `/settings/models` → ModelPlaceholderPage

### Code Quality
- [x] `flutter analyze` - 0 errors, chỉ còn info/warnings (pre-existing)
- [x] Review & fix theo coding_conventions và api_contracts

---

## Phase 2 - Embedding & Vector Store ✅ (Hoàn thành)
> Mục tiêu: Gecko embed text, VectorStore hoạt động, test search

### Database
- [x] Tạo `documents_table.dart`, `chunks_table.dart`, `vectors_table.dart`
- [x] Tạo DAOs tương ứng
- [x] Update `app_database.dart` thêm tables, DAOs
- [x] Tạo `core/utils/embedding_serializer.dart`

### Services - Phase 2
- [x] `GeckoService` - implement `initialize()`, `embed()`, `embedBatch()`
- [x] `VectorStoreService` - implement `insert()`, `insertBatch()`, `search()`, `deleteByChunkIds()`
- [x] `ChunkingService` - implement `chunk()` với sliding window

### Testing
- [x] Unit test `ChunkingService` với text tiếng Việt và tiếng Anh (8 tests)
- [x] Unit test `VectorStoreService.search()` với mock vectors (9 tests)
- [x] Integration test embed → store → search cycle

---

## Phase 3 - RAG Pipeline ✅ (Hoàn thành)
> Mục tiêu: Import PDF/DOCX, tự động chunk+embed, search khi chat

### Services - Phase 3
- [x] `DocumentParserService` - implement `parse()` cho:
  - `.pdf` dùng `syncfusion_flutter_pdf`
  - `.docx` dùng `archive` (ZIP) + XML parsing
  - `.txt`, `.md` đọc thẳng file
- [x] `ContextManagerService` - implement `buildContext()`:
  - Lấy recent messages (limit 20)
  - Đếm token xấp xỉ
  - Trim history nếu vượt budget
  - Trim RAG chunks nếu vượt budget
- [x] `PromptBuilderService` - hỗ trợ RAG context (SearchResult)

### Repositories - Phase 3
- [x] `DocumentRepositoryImpl` - `importDocument()` orchestrate:
  1. Copy file vào app documents dir
  2. Save document metadata
  3. Parse → rawText
  4. Chunk text
  5. Embed từng chunk với batch processing + progress (nếu Gecko ready)
  6. Store vectors
  7. Update chunk count
- [x] `DocumentRepositoryImpl` - thêm `importDocumentWithProgress()` hỗ trợ callback progress với documentId

### Blocs - Phase 3
- [x] `KnowledgeBloc` - đủ events: DocumentsLoaded, ImportRequested, DeleteRequested, ReindexRequested
  - Emit `KnowledgeIndexing` với progress khi import
- [x] `ChatBloc` - đã tích hợp RAG retrieval:
  - Dùng `GeckoService` + `VectorStoreService` để search
  - Graceful degradation khi embedding fail
  - Pass `ragResults` vào `ChatStreaming` state

### UI - Phase 3
- [x] `KnowledgePage` - danh sách documents
- [x] `_DocumentCard` - hiển thị name, size, chunk count, delete confirm
- [x] Import button (AppBar + empty state)
- [x] `_IndexingProgressView` - progress bar + label động khi indexing
- [ ] `RAG sources` hiển thị trong ChatView khi response có context (optional - Phase 5)

### DI - Phase 3
- [x] Inject `GeckoService` vào `DocumentRepositoryImpl` và `ChatBloc`
- [x] Inject `VectorStoreService` vào `ChatBloc`

---

## Phase 4 - Model Manager & Polish ✅ (Hoàn thành)
> Mục tiêu: Download model từ trong app, context manager hoàn chỉnh, UX tốt

### Services - Phase 4
- [x] `ModelManagerService`:
  - Download Gemma từ Hugging Face hoặc custom URL
  - Hỗ trợ resume download (`allowPause: true`, check partial file)
  - Verify kích thước file sau download (~1MB tolerance)
  - Theo dõi progress (bytes downloaded / total) qua `onProgress` callback
  - Notification background download (built-in background_downloader)
  - Hủy download đang chạy
- [x] Update `ContextManagerService` - thêm summary memory:
  - Nếu history > 3000 tokens → summarize bằng Gemma (generate non-stream)
  - Cache summary theo sessionId (tối đa 10 entries, LRU)
  - Graceful degradation nếu summarize fail → fallback về trim thường
  - Chỉ giữ 4 messages gần nhất khi đã có summary

### Blocs - Phase 4
- [x] `ModelBloc` - đủ events: StatusChecked, GemmaDownloadStarted, GeckoDownloadStarted, DownloadCancelled
  - Lắng nghe progress stream từ ModelManagerService qua `_ProgressUpdate` internal event

### UI - Phase 4
- [x] `ModelManagerPage` - hiển thị status Gemma + Gecko với các trạng thái:
  - Not Downloaded → nút "Tải xuống"
  - Downloading → progress bar + cancel button
  - Ready → icon check + "Sẵn sàng sử dụng"
  - Error → message lỗi
- [x] `DownloadProgressCard` - LinearProgressIndicator + phần trăm + cancel
- [x] `SettingsPage` - cấu hình chunk size, chunk overlap, history limit, similarity threshold
  - Link tới ModelManagerPage
  - Danger Zone: xoá tất cả dữ liệu + re-index
- [x] `MemoryWarningDialog` - dialog cảnh báo RAM không đủ, gợi ý giải pháp

### Error Handling Polish
- [x] Global error handler trong `main.dart`:
  - `FlutterError.onError` bắt Flutter errors
  - `PlatformDispatcher.instance.onError` bắt async errors ngoài Flutter
- [ ] Retry mechanism cho embedding failures (chưa làm - sẽ làm nếu cần)
- [x] Graceful degradation khi VectorStore search fail (✅ đã làm ở Phase 3)

---

## Phase 5 - Advanced Features
> Sau MVP, làm khi Phase 1-4 stable

- [ ] Multi-document Knowledge Base với filter theo document
- [ ] Citation nguồn - hiển thị chunk nào được dùng trong response
- [ ] Semantic cache - cache embedding của queries giống nhau
- [ ] Background indexing khi import document lớn
- [ ] Export session thành text/PDF
- [ ] Dark mode
- [ ] Widget tests cho toàn bộ UI
- [ ] Integration tests end-to-end
- [ ] Retry mechanism cho embedding failures

---

## Code Review Status (06/08/2026)

### 1. Coding Conventions
- ✅ File naming: snake_case toàn bộ
- ✅ Bloc Pattern: Event/State naming đúng, emit.forEach dùng cho stream
- ✅ Model classes: có fromDbRow và copyWith
- ✅ Error handling: AppException hierarchy, catch đúng cách
- ⚠️ Phase 1 pre-existing: `app_database.dart` & table files dùng relative imports (vi phạm `always_use_package_imports`)
- ⚠️ Phase 1 pre-existing: `chat_page.dart` line 69: unnecessary cast warning
- ⚠️ Phase 1 pre-existing: `withOpacity` deprecated ở `chat_page.dart` & `message_bubble.dart`
- ✅ Phase 3: Import order violation trong `knowledge_page.dart` — **đã fix**

### 2. Bloc States vs Api Contracts
- ✅ `ChatBloc`: 5 states đúng, 4 events đúng — Phase 3 thêm optional `ragResults` vào `ChatStreaming` (mở rộng hợp lý, không break contract)
- ✅ `SessionBloc`: 4 states đúng, 5 events đúng
- ✅ `KnowledgeBloc`: 5 states đúng, 4 events đúng — thêm field `documentId` + `documentName` vào `KnowledgeIndexing` (mở rộng hợp lý)
- ✅ Không có emit sai state

### 3. Cloud API / Offline Principle
- ✅ **100% offline**: tất cả inference đều on-device
- ✅ flutter_gemma, tflite_flutter: local AI runtime
- ✅ drift/SQLite: local database
- ✅ syncfusion_flutter_pdf, archive: local file parsing
- ✅ background_downloader: download model file từ URL (không phải AI API)
- ✅ **KHÔNG có** `http`, `Firebase`, `Supabase`, `OpenAI` — xác nhận toàn bộ lib/

### 4. Business Logic trong Widgets
- ✅ Widgets chỉ dispatch events và render state
- ✅ `ChatInputBar._onSend()`: UI event handler (acceptable)
- ✅ `_pickAndImportFile`, `_confirmDelete`, `_formatSize`, `_getIcon`, `_progressLabel`: UI handler hoặc pure format helpers
- ✅ **Không có** business logic nào nằm trong Widget

### 5. Bugs đã fix trong Phase 3
- ✅ `estimatedTokens` trong `ContextManagerService` tính pre-trim thay vì post-trim — **đã fix**
- ✅ `SearchResult` duplicate class (cả `prompt_builder_service.dart` và `vector_store_service.dart`) — **đã cleanup**
- ✅ `_progressLabel` trong `knowledge_page.dart` dùng field `progress` thay vì parameter `p` — **đã fix**

### 6. flutter analyze
- ✅ **0 errors** từ code Phase 3
- ✅ **0 errors** từ code Phase 4
- ✅ Tổng cộng 34 issues (toàn info/warnings pre-existing từ Phase 1-2)

### 7. Phase 4 Code Review
- ✅ `ModelManagerService` - đúng api_contracts.md: gọi `FileDownloader().start()`, dùng `onProgress`/`onStatus` callbacks, có `tapOpensFile: false`, `requiresWiFi: false`
- ✅ `ModelBloc` - đúng coding_conventions: Event/State naming, không emit trực tiếp từ stream listener (dùng internal event `_ProgressUpdate`)
- ✅ `ContextManagerService` - summary memory: cache LRU, graceful degradation, inject GemmaService optional
- ✅ `PromptBuilderService` - thêm `summary` field vào BuiltContext, chèn vào prompt template
- ✅ `SettingsPage` + `ModelManagerPage` - không business logic trong Widget
- ✅ **100% offline**: background_downloader chỉ download model files, không gửi dữ liệu user

---

## Ghi chú quan trọng

### Model files
```
Gemma 4B IT:  ~2.8GB  → download từ Hugging Face: google/gemma-3-4b-it
Gecko 110M:   ~440MB  → download từ Google MediaPipe models
```

### Paths on device
```dart
final dir = await getApplicationDocumentsDirectory();
final gemmaPath = '${dir.path}/models/gemma4b-it.litertlm';
final geckoPath = '${dir.path}/models/gecko-110m.tflite';
```

### iOS Build Settings cần thêm
```xml
<!-- ios/Runner/Info.plist -->
<key>NSDocumentPickerUsageDescription</key>
<string>Cần truy cập file để import tài liệu</string>
```

### Android Build Settings cần thêm
```groovy
// android/app/build.gradle
android {
    defaultConfig {
        minSdkVersion 24  // Minimum cho flutter_gemma
    }
}