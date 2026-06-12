# Common Pitfalls & Solutions

## Flutter Gemma (Session-Based API)

### Pitfall: GPU crash khi prompt có RAG chunks (MỚI 12/06/2026)
```
Lỗi 1: clEnqueueReadBuffer - Execution status error for events in wait list
Lỗi 2: litert_tensor_buffer.h:748 - tensor allocation error
Pattern: Chỉ crash khi prompt có RAG chunks embedded (=== Reference Documents ===)
         Prompt không RAG luôn chạy OK.
```
```dart
// ❌ Chưa rõ nguyên nhân: prompt size >2500 chars hay nội dung RAG formatting
// Đang điều tra: Test A — prompt ~2500 chars không RAG

// ⚠️ Backend hiện tại: PreferredBackend.gpu
// Hướng xử lý nếu GPU không ổn định: chuyển sang PreferredBackend.cpu
```

### Pitfall: hasActiveSession false dù session object vẫn tồn tại
```dart
// LiteRT LM constaint: Chỉ support 1 session tại 1 thời điểm.
// Legacy generate()/generateStream() gọi _model!.createSession()
// → Session cũ bị invalidate ở FFI, nhưng Dart _session vẫn != null

// ❌ SAI - kiểm tra session nhưng không guard
await _session!.addQueryChunk(...);  // Bad state: Session is closed

// ✅ ĐÚNG - guard trong ChatBloc trước khi generate
if (!_gemmaService.hasActiveSession) {
  log_util.log.i('🔄 [Session] Tạo Gemma session mới...');
  await _createGemmaSessionWithHistory(_currentMessages);
}
```

### Pitfall: Legacy generate() invalidates session chính
```dart
// ❌ SAI - SummaryService dùng generateStream(prompt)
// → FFI session của ChatBloc bị kill

// ✅ ĐÚNG - generate() và generateStream() set _session = null trước createSession()
final savedSession = _session;
_session = null;  // ← báo cho ChatBloc rằng session đã chết
final session = await _model!.createSession();
try {
  // use session
} finally {
  session.close();
  if (savedSession != null) _session = null; // không thể restore
}
```

### Pitfall: Model load blocking UI thread
```dart
// ❌ SAI - block UI
void initState() {
  gemmaService.initialize(path); // UI freezes 10s+
}

// ✅ ĐÚNG - dùng Bloc
add(ModelInitializationRequested(path));
// Trong Bloc handler dùng Future, emit states
```

### Pitfall: Session không được đóng
```dart
// ❌ SAI - memory leak
final session = await model.createSession();
// Quên close()

// ✅ ĐÚNG
final session = await model.createSession();
try {
  // use session
} finally {
  session.close();
}
```

### Pitfall: Dùng sai prompt format
```
// ❌ SAI - ChatGPT format
{"role": "user", "content": "..."}

// ✅ ĐÚNG - Gemma instruct format
<start_of_turn>system
You are AgriAI, an agricultural assistant...
<end_of_turn>

=== Recent Conversation ===
<start_of_turn>user
...<end_of_turn>
<start_of_turn>assistant
...<end_of_turn>

=== Reference Documents ===
[Document 1]
text...

=== Current Question ===
<start_of_turn>user
...<end_of_turn>
<start_of_turn>model
```

### Pitfall: PromptBuilder history bị trùng lặp
```dart
// ❌ SAI (đã fix 12/06/2026) - history trùng lặp assistant intro
// Lịch sử: query → intro assistant → query → intro assistant

// ✅ ĐÚNG (VERSION=dedup_v1) - budget-based truncation
// kMaxHistoryTokens = 300
// Duyệt từ cuối lên đầu, gom messages trong budget
// KHÔNG còn exact-match dedup
```

---

## RAG Pipeline

### Pitfall: matched > 0 nhưng returned = 0 (đã fix 12/06/2026)
```dart
// ❌ SAI - dùng break khi chunk vượt budget
if (chunkToken > effectiveCap) break;  // ← dừng hẳn, bỏ qua chunk ngon phía sau

// ✅ ĐÚNG - try-fit packing (greedy knapsack)
for (final chunk in results) {
  if (chunkCount >= kMaxRagChunks) break;
  if (chunkToken > effectiveCap) continue;  // ← bỏ qua chunk quá lớn, thử chunk tiếp
  if (tokenSum + chunkToken <= effectiveCap) {
    trimmed.add(chunk);
    tokenSum += chunkToken;
    chunkCount++;
    if (tokenSum >= effectiveCap) break;  // safety guard
  }
}
```

### Pitfall: Chunk quá lớn so với budget (đã fix 12/06/2026)
```
Trước: chunkSize=500 → chunk thực tế 782 tokens (do charsPerToken mismatch)
Sau:  chunkSize=250 → chunk thực tế ~380 tokens
Cần:  chunkSize=200 → chunk thực tế ~300 tokens (có thể pack 2 chunks)
```

### Pitfall: Quên hard cap kMaxRagTokens
```dart
// ❌ SAI - tokenBudget từ Context Budget có thể rất lớn (~1300)
final effectiveCap = tokenBudget;  // → 1300 tokens cho RAG, chiếm hết context

// ✅ ĐÚNG - hard cap với kMaxRagTokens
final effectiveCap = tokenBudget < kMaxRagTokens ? tokenBudget : kMaxRagTokens;
// kMaxRagTokens = 500
```

### Pitfall: Short query không nên chạy RAG (đã fix 12/06/2026)
```dart
// ❌ SAI - "chào", "bạn là ai" vẫn chạy RAG

// ✅ ĐÚNG - shouldSkipRag() guard
RagSkipReason? _shouldSkipRag(String query) {
  // tooShort: ≤2 từ, không ?, <15 ký tự
  if (q.split(' ').length <= 2 && !q.contains('?') && q.length < 15) return RagSkipReason.tooShort;
  // greeting: hi/hello/chào/xin chào
  if (RegExp(r'^(hi|hello|hey|chào|xin chào)(\s|$)').hasMatch(q)) return RagSkipReason.greeting;
  // capability: bạn là ai/giúp gì
  if (q.contains('bạn là ai') || q.contains('giúp gì')) return RagSkipReason.capability;
  return null;
}
```

---

## Drift / SQLite

### Pitfall: Quên chạy build_runner sau khi thay đổi table
```bash
# Sau mỗi thay đổi schema:
dart run build_runner build --delete-conflicting-outputs
```

### Pitfall: Cascade delete không hoạt động
```dart
// Phải khai báo trong foreign key
TextColumn get documentId => text().references(
  Documents, #id,
  onDelete: KeyAction.cascade,  // ← BẮT BUỘC
)();
```

### Pitfall: ChunksCompanion thiếu createdAt
```dart
// ❌ SAI - Drift throw InvalidDataException
ChunksCompanion(
  id: Value(uuid.v4()),
  // thiếu createdAt
)

// ✅ ĐÚNG
ChunksCompanion(
  id: Value(uuid.v4()),
  createdAt: Value(DateTime.now()),  // ← BẮT BUỘC
)
```

---

## Vector Store / Embedding

### Pitfall: Float precision khi serialize/deserialize
```dart
// ✅ ĐÚNG - dùng Float32List
final float32 = Float32List.fromList(embedding);
final bytes = float32.buffer.asUint8List(); // giữ nguyên precision
```

### Pitfall: Cosine similarity với zero vector
```dart
// ✅ LUÔN check trước khi tính
if (normA == 0 || normB == 0) return 0.0;
```

### Pitfall: Gecko output chưa normalized
```dart
// Gecko output CÓ THỂ đã normalized, kiểm tra bằng:
double norm = sqrt(embedding.map((v) => v * v).reduce((a, b) => a + b));
// Nếu norm ≈ 1.0 thì đã normalized
```

---

## Embedding / Gecko

### Pitfall: Dùng tflite_flutter Interpreter sai (đã migrate)
```dart
// ❌ SAI - dùng tflite_flutter với Gecko
final interpreter = await Interpreter.fromFile(modelFile);
interpreter.run(input, output); // → sai format tensor

// ✅ ĐÚNG - dùng flutter_gemma EmbeddingModel API
await geckoService.registerModel(
  modelPath: '/path/to/Gecko_256_quant.tflite',
  tokenizerPath: '/path/to/sentencepiece.model',
);
await geckoService.initialize();
final vector = await geckoService.embed(text);
```

### Pitfall: Gecko FIFO lock (race condition GPU/FFI)
```dart
// ❌ SAI - gọi embed() song song
await Future.wait([geckoService.embed(a), geckoService.embed(b)]); // GPU crash

// ✅ ĐÚNG - GeckoServiceImpl._runLocked<T>(fn)
// FIFO: chờ previous lock → set lock mới → fn() → release
```

### Pitfall: Quên registerModel trước khi initialize
```dart
// ❌ SAI - FlutterGemma.getActiveEmbedder() throw StateError
await geckoService.initialize();

// ✅ ĐÚNG
await geckoService.registerModel(modelPath: ..., tokenizerPath: ...);
await geckoService.initialize();
```

### Pitfall: Thiếu tokenizer file
```dart
// Gecko model cần tokenizer SentencePiece (~4MB) đi kèm
// Download cả 2 files:
await modelManager.downloadGecko();          // .tflite file
await modelManager.downloadGeckoTokenizer(); // .model file (SentencePiece)
```

---

## Context Budget / Token Estimator

### Pitfall: CharsPerToken mismatch giữa chunker và estimator
```
Chunker:  charsPerToken = 4   → chunkSize=500 → 2000 chars
Estimator: kCharsPerToken = 2.5 → 2000 chars / 2.5 = 800 tokens (thực tế gấp 1.6x)
Kết quả: Chunk vượt kMaxRagTokens (500) bị continue
```

### Pitfall: Hardcode totalBudget=8000 không còn dùng
```dart
// ❌ SAI - constants cũ (đã xóa khỏi app_constants.dart)
const int totalBudget = 8000;
const int ragBudget = 4000;

// ✅ ĐÚNG - ratio-based dynamic
kGemmaMaxTokens = 2048
historyBudgetRatio = 0.35 (≈717)
responseBudgetRatio = 0.25 (≈512)
systemBudgetRatio = 0.10 (≈205)
ragBudget = max(0, 2048 - history - response - system - question)
```

---

## Bloc

### Pitfall: Emit after close
```dart
// ❌ SAI - stream có thể tiếp tục sau khi Bloc bị dispose
_gemmaService.generateStream(prompt).listen((token) {
  emit(ChatStreaming(...)); // Bloc có thể đã dispose!
});

// ✅ ĐÚNG - dùng emit.forEach, tự cancel khi Bloc dispose
await emit.forEach(
  _gemmaService.generateStream(prompt),
  onData: (token) => ChatStreaming(...),
);
```

### Pitfall: State không rebuild vì equality
```dart
// ✅ ĐÚNG - extend Equatable hoặc override props
class ChatStreaming extends ChatState {
  final List<MessageModel> messages;
  final String streamingText;
  @override
  List<Object?> get props => [messages, streamingText];
}
```

### Pitfall: GetIt Singleton + BlocProvider → Bad state
```dart
// Root cause: GetIt giữ singleton, BlocProvider dispose bloc khi page pop.

// ❌ SAI: mỗi page tạo BlocProvider với GetIt singleton
// → Page pop → BlocProvider dispose → GetIt reference đã chết

// ✅ ĐÚNG: Gom singleton bloc vào MultiBlocProvider ở app.dart
// BlocProvider<ModelBloc>(create: (_) => sl<ModelBloc>()..add(const StatusChecked())),
// BlocProvider<SessionBloc>(create: (_) => sl<SessionBloc>()..add(const SessionsLoaded())),
// BlocProvider<KnowledgeBloc>(create: (_) => sl<KnowledgeBloc>()..add(const DocumentsLoaded())),
// BlocProvider<SessionFilesCubit>(create: (_) => sl<SessionFilesCubit>()),

// Ngoại lệ: ChatBloc (factory) — giữ BlocProvider ở ChatPage với key
BlocProvider(
  key: ValueKey('chat_$sessionId'),
  create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
  child: const ChatView(),
);
```

---

## iOS / Android Specific

### iOS: File access permission
```xml
<!-- ios/Runner/Info.plist -->
<key>NSDocumentPickerUsageDescription</key>
<string>Cần truy cập để import tài liệu</string>
<key>UIFileSharingEnabled</key>
<true/>
```

### Android: Large model files
```groovy
android {
  defaultConfig {
    minSdkVersion 24
  }
  aaptOptions {
    noCompress "litertlm", "tflite"
  }
}
```

### Lưu model ngoài assets (KHUYẾN NGHỊ)
```dart
// Model download runtime, không bundle
// Lưu vào: getApplicationDocumentsDirectory()
// Lý do: APK/IPA sẽ quá lớn (~3GB)
```

---

## Performance

### Pitfall: Embed từng chunk tuần tự khi import
```dart
// ❌ CHẬM - O(n) round trips
for (final chunk in chunks) {
  final vector = await geckoService.embed(chunk);
}

// ✅ NHANH HƠN - batch embed
final vectors = await geckoService.embedBatch(chunks); // 1 round trip
```

### Pitfall: Rebuild toàn bộ MessageList khi stream (đã fix 11/06/2026)
```dart
// ✅ ĐÚNG - tách LastBubble riêng với buildWhen
// LastBubble chỉ rebuild khi streamingText thay đổi
// ChatBody dùng buildWhen trừ ChatThinking→ChatThinking
// Tổng cộng 11 widget con, giảm 85% code chat_page.dart
```

### Pitfall: GPU allocation error với prompt dài
```
LiteRT LM trên GPU backend có thể crash khi:
- Prompt > 2500 chars + RAG chunks (đang điều tra)
- Session bị reuse qua nhiều turn

Giải pháp tạm thời: closeSession() + createSession() mỗi turn
Giải pháp lâu dài: PreferredBackend.cpu nếu GPU không ổn định
```

---

## background_downloader - Large Model Files

### Pitfall: WorkManager bị kill cho file >2GB
```dart
// File 2.8GB Gemma ở 5Mbps = ~75 phút → bị terminate

// ✅ ĐÚNG - allowPause: true
final task = DownloadTask(
  url: url,
  filename: filename,
  allowPause: true,   // ← tự pause khi sắp hết thời gian
  retries: 3,
);

// Android 14+: priority: 0 → User Initiated Data Transfer
```

### Pitfall: Không request notification permission Android 13+
```dart
await Permission.notification.request();
```

### Pitfall: Lưu file vào sai directory
```dart
// ✅ ĐÚNG - BaseDirectory.applicationDocuments
// Path: getApplicationDocumentsDirectory()/models/
```

### Pitfall: Thêm flutter_local_notifications cùng background_downloader
```
// ✅ ĐÚNG - dùng configureNotification() built-in
FileDownloader().configureNotification(
  running: const TaskNotification('Đang tải', '{progress}%'),
  complete: const TaskNotification('Hoàn thành', 'Model sẵn sàng'),
);
// KHÔNG cần thêm package notification khác