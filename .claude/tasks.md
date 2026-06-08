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
  - Wrap flutter_gemma package (v0.13.6 API: FlutterGemma.getActiveModel)
  - Throws `ModelNotLoadedException` nếu file không tồn tại
- [x] `PromptBuilderService` - implement `build(BuiltContext)`
  - Dùng Gemma chat template format (start_of_turn/end_of_turn)

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
  - `/settings` → SettingsPlaceholderPage
  - `/settings/models` → ModelPlaceholderPage

### Code Quality
- [x] `flutter analyze` - 0 errors
- [x] Review & fix theo coding_conventions và api_contracts

---

## Phase 2 - Embedding & Vector Store
> Mục tiêu: Gecko embed text, VectorStore hoạt động, test search

### Database
- [x] Tạo `documents_table.dart`, `chunks_table.dart`, `vectors_table.dart`
- [x] Tạo DAOs tương ứng
- [x] Update `app_database.dart` thêm tables, DAOs
- [x] Tạo `core/utils/embedding_serializer.dart`

### Services - Phase 2 ✅
- [x] `GeckoService` - implement `initialize()`, `embed()`, `embedBatch()`
  - Wrap tflite_flutter
  - Path model: `getApplicationDocumentsDirectory()/models/gecko-110m.tflite`
  - Output vector: 768 dimensions, normalized
- [x] `VectorStoreService` - implement `insert()`, `insertBatch()`, `search()`, `deleteByChunkIds()`
  - Brute-force cosine similarity
  - Filter by threshold 0.7
  - Sort by score desc, return top K
- [x] `ChunkingService` - implement `chunk()` với sliding window

### Testing ✅
- [x] Unit test `ChunkingService` với text tiếng Việt và tiếng Anh (8 tests)
- [x] Unit test `VectorStoreService.search()` với mock vectors (9 tests)
- [x] Integration test embed → store → search cycle

---

## Phase 3 - RAG Pipeline
> Mục tiêu: Import PDF/DOCX, tự động chunk+embed, search khi chat

### Services - Phase 3
- [ ] `DocumentParserService` - implement `parse()` cho:
  - `.pdf` dùng `syncfusion_flutter_pdf`
  - `.docx` dùng `docx_to_text` hoặc parse XML thủ công
  - `.txt`, `.md` đọc thẳng file
- [x] `ContextManagerService` - implement `buildContext()`:
  - Lấy recent messages (limit 20)
  - Đếm token xấp xỉ
  - Trim history nếu vượt budget
- [x] `PromptBuilderService` - hỗ trợ RAG context (SearchResult)

### Repositories - Phase 3
- [ ] `DocumentRepositoryImpl` - `importDocument()` orchestrate:
  1. Copy file vào app documents dir
  2. Save document metadata
  3. Parse → rawText
  4. Chunk text
  5. Embed từng chunk (show progress)
  6. Store vectors
  7. Update chunk count

### Blocs - Phase 3
- [ ] `KnowledgeBloc` - đủ events: DocumentsLoaded, ImportRequested, DeleteRequested, ReindexRequested
  - Emit `KnowledgeIndexing` với progress khi import
- [x] `ChatBloc` - đã dùng `ContextManagerService` (sẵn sàng cho RAG)

### UI - Phase 3
- [ ] `KnowledgePage` - danh sách documents
- [ ] `DocumentCard` - hiển thị name, size, chunk count
- [ ] `ImportDocumentButton` - mở file picker, trigger import
- [ ] `IndexingProgressBar` - hiển thị progress khi indexing
- [ ] Trong `ChatView`: hiển thị RAG source khi response có context

---

## Phase 4 - Model Manager & Polish
> Mục tiêu: Download model từ trong app, context manager hoàn chỉnh, UX tốt

### Services - Phase 4
- [ ] `ModelManagerService`:
  - Download Gemma từ Hugging Face hoặc custom URL
  - Hỗ trợ resume download (check partial file)
  - Verify checksum sau download
  - Theo dõi progress (bytes downloaded / total)
- [ ] Update `ContextManagerService` - thêm summary memory:
  - Nếu history > 3000 tokens → summarize bằng Gemma
  - Cache summary, dùng thay cho toàn bộ history cũ

### Blocs - Phase 4
- [ ] `ModelBloc` - đủ events: StatusChecked, GemmaDownloadStarted, GeckoDownloadStarted, Cancelled

### UI - Phase 4
- [ ] `ModelManagerPage` - hiển thị status Gemma + Gecko
- [ ] `DownloadProgressCard` - progress bar + cancel button
- [ ] `SettingsPage` - cấu hình chunk size, history limit, similarity threshold
- [ ] Cải thiện `ChatInputBar` - disabled khi model chưa load
- [ ] `MemoryWarningDialog` - hiển thị khi RAM không đủ

### Error Handling Polish
- [ ] Global error handler trong MaterialApp
- [ ] Retry mechanism cho embedding failures
- [ ] Graceful degradation khi VectorStore search fail (chat vẫn hoạt động không có RAG)

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

---

## Code Review Status (15/04/2025)

### 1. Coding Conventions
- ✅ File naming: snake_case toàn bộ
- ✅ Bloc Pattern: Event/State naming đúng, emit.forEach dùng cho stream
- ✅ Model classes: có fromDbRow và copyWith
- ✅ Error handling: AppException hierarchy, catch đúng cách
- ⚠️ `app_database.dart` & table files: dùng relative imports thay vì package imports (vi phạm `always_use_package_imports`)
- ⚠️ `message_bubble.dart`: `StreamingIndicator` dùng animation, nhưng import không có vấn đề
- ⚠️ `chat_page.dart` line 69: unnecessary cast warning (pre-existing)
- ⚠️ `chat_page.dart` line 75, 218, 256 & `message_bubble.dart` line 73: `withOpacity` deprecated, nên dùng `.withValues()`

### 2. Bloc States vs Api Contracts
- ✅ `ChatBloc`: 5 states đúng, 4 events đúng
- ✅ `SessionBloc`: 4 states đúng, 5 events đúng
- ✅ Không có emit sai state

### 3. Cloud API / Offline Principle
- ✅ **100% offline**: tất cả inference đều on-device
- ✅ flutter_gemma, tflite_flutter: local AI runtime
- ✅ drift/SQLite: local database
- ✅ background_downloader: download model file từ URL (không phải AI API)
- ✅ Không có http package, không có Firebase/Supabase/OpenAI

### 4. Business Logic trong Widgets
- ✅ Widgets chỉ dispatch events và render state
- ✅ `ChatInputBar._onSend()`: UI event handler (acceptable)
- ❌ Bug nhỏ: `context_manager_service.dart` - `estimatedTokens` được tính TRƯỚC khi trim history, nên giá trị trả về không chính xác (báo tổng pre-trim thay vì post-trim)

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