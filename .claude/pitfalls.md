# Common Pitfalls & Solutions

## Flutter Gemma

### Pitfall: Model load blocking UI thread
```dart
// ❌ SAI - block UI
void initState() {
  gemmaService.initialize(path); // UI freezes
}

// ✅ ĐÚNG - dùng Bloc
add(ModelInitializationRequested(path));
// Trong Bloc handler dùng Future, emit states
```

### Pitfall: Session không được đóng
```dart
// ❌ SAI - memory leak
final session = await InferenceModel.createSession(model);
final stream = session.getResponseAsync(prompt);
// Quên close()

// ✅ ĐÚNG
final session = await InferenceModel.createSession(model);
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

// ✅ ĐÚNG - Gemma format
<start_of_turn>user
...
<end_of_turn>
<start_of_turn>model
```

---

## Drift / SQLite

### Pitfall: Quên chạy build_runner sau khi thay đổi table
```bash
# Sau mỗi thay đổi schema:
dart run build_runner build --delete-conflicting-outputs
```

### Pitfall: Truy cập DB trên main isolate với data lớn
```dart
// ❌ SAI - load toàn bộ 50k vectors trên main thread
final vectors = await vectorsDao.getAllVectors();

// ✅ ĐÚNG - dùng NativeDatabase.createInBackground()
// Đã config trong app_database.dart, tự động xử lý
```

### Pitfall: Cascade delete không hoạt động
```dart
// Phải khai báo trong foreign key
TextColumn get documentId => text().references(
  Documents, #id,
  onDelete: KeyAction.cascade,  // ← BẮT BUỘC
)();
```

---

## Vector Store / Embedding

### Pitfall: Float precision khi serialize/deserialize
```dart
// ❌ SAI - dùng List<double> serialize thủ công
final bytes = embedding.map((v) => v.toInt()).toList(); // MẤT precision!

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
// Nếu không, cần normalize trước khi store
```

---

## Embedding / Gecko

### Pitfall: Dùng tflite_flutter Interpreter sai format
```dart
// ❌ SAI - interpreter.run() với List<List<String>> không phải tensor hợp lệ
final input = texts.map((t) => [t]).toList();
final output = List.generate(texts.length, (_) => List<double>.filled(768, 0.0));
interpreter.run(input, output); // → Bad state: failed precondition

// ✅ ĐÚNG - dùng flutter_gemma EmbeddingModel API
// flutter_gemma tự xử lý tokenizer (SentencePiece) + correct tensor shapes
final model = await FlutterGemma.getActiveEmbedder();
final vectors = await model.generateEmbeddings(texts, taskType: TaskType.retrievalDocument);
```

### Pitfall: Quên registerModel trước khi initialize
```dart
// ❌ SAI - FlutterGemma.getActiveEmbedder() sẽ throw StateError
// nếu chưa có active embedding model
await geckoService.initialize();

// ✅ ĐÚNG - gọi registerModel trước
await geckoService.registerModel(
  modelPath: '/path/to/model.tflite',
  tokenizerPath: '/path/to/sentencepiece.model',
);
await geckoService.initialize();
```

### Pitfall: Thiếu tokenizer file
```dart
// Gecko model cần tokenizer SentencePiece (~4MB) đi kèm
// flutter_gemma yêu cầu cả model + tokenizer để install embedder
// Nếu thiếu tokenizer → FlutterGemma.installEmbedder() sẽ fail

// ✅ Giải pháp: download cả 2 files trước khi register
await modelManager.downloadGecko();          // .tflite file
await modelManager.downloadGeckoTokenizer(); // .model file (SentencePiece)
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
// ❌ SAI - Dart dùng reference equality
class ChatLoaded extends ChatState {
  final List<MessageModel> messages;
  // Không override ==, 2 ChatLoaded với cùng messages vẫn khác nhau
}

// ✅ ĐÚNG - implement Equatable
class ChatLoaded extends ChatState with EquatableMixin {
  final List<MessageModel> messages;
  @override
  List<Object?> get props => [messages];
}
```

### Pitfall: GetIt Singleton + BlocProvider → Bad state (quan trọng!)
```dart
// Root cause: GetIt giữ singleton, BlocProvider dispose bloc khi page pop.
// Lần sau context.read<Bloc>() dùng instance đã dispose → StateError (Bad state)

// ❌ SAI: mỗi page tự tạo BlocProvider với GetIt singleton
class ModelManagerPage extends StatelessWidget {
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ModelBloc>()..add(const StatusChecked()),  // ← GetIt singleton
      child: _View(),
    );
  }
}
// → Khi page pop, BlocProvider dispose ModelBloc.
// → GetIt vẫn giữ reference đến instance đã dispose.
// → Lần sau vào trang lại, sl<ModelBloc>() trả về instance đã chết → Bad state

// ✅ ĐÚNG: Gom singleton bloc vào MultiBlocProvider ở app.dart
// Các page chỉ context.read<T>() mà không tạo BlocProvider
// app.dart:
@override
Widget build(BuildContext context) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ModelBloc>(create: (_) => sl<ModelBloc>()..add(const StatusChecked())),
      BlocProvider<SessionBloc>(create: (_) => sl<SessionBloc>()..add(const SessionsLoaded())),
      BlocProvider<KnowledgeBloc>(create: (_) => sl<KnowledgeBloc>()..add(const DocumentsLoaded())),
    ],
    child: MaterialApp.router(...),
  );
}

// Các page chỉ cần:
class ModelManagerPage extends StatelessWidget {
  const ModelManagerPage({super.key});
  Widget build(BuildContext context) {
    return const _ModelManagerView(); // context.watch<ModelBloc>() tự tìm lên trên
  }
}

// Ngoại lệ: ChatBloc (factory pattern) — mỗi session 1 instance riêng
// Giữ BlocProvider ở ChatPage với key để Flutter tự dispose
class ChatPage extends StatelessWidget {
  final String sessionId;
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey('chat_$sessionId'),  // ← quan trọng: mới khi session đổi
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: ChatView(sessionId: sessionId),
    );
  }
}
```

---

## iOS / Android Specific

### iOS: File access permission
```xml
<!-- ios/Runner/Info.plist -->
<key>NSDocumentPickerUsageDescription</key>
<string>Cần truy cập để import tài liệu vào knowledge base</string>
<key>UIFileSharingEnabled</key>
<true/>
```

### Android: Large model files
```groovy
// android/app/build.gradle
android {
  defaultConfig {
    minSdkVersion 24
  }
  // Nếu bundle model trong assets (không khuyến nghị vì quá lớn)
  aaptOptions {
    noCompress "litertlm", "tflite"
  }
}
```

### Lưu model ngoài assets (KHUYẾN NGHỊ)
```dart
// Model nên download runtime, không bundle trong app
// Lưu vào: getApplicationDocumentsDirectory()
// Lý do: APK/IPA sẽ quá lớn (~3GB) nếu bundle model
```

---

## Performance

### Pitfall: Embed từng chunk tuần tự khi import
```dart
// ❌ CHẬM - O(n) round trips
for (final chunk in chunks) {
  final vector = await geckoService.embed(chunk); // mỗi lần 1 round trip
}

// ✅ NHANH HƠN - batch embed
final vectors = await geckoService.embedBatch(chunks); // 1 round trip
```

### Pitfall: Rebuild toàn bộ MessageList khi stream
```dart
// ❌ SAI - rebuild toàn bộ list mỗi token
BlocBuilder<ChatBloc, ChatState>(
  builder: (_, state) => ListView.builder(
    itemCount: state.messages.length,
    itemBuilder: (_, i) => MessageBubble(state.messages[i]),
  ),
);

// ✅ ĐÚNG - chỉ rebuild bubble đang stream
// Dùng buildWhen hoặc tách StreamingMessageBubble ra ngoài ListView
```

### Memory: Unload model khi app background (optional)
```dart
// Trong AppLifecycleObserver:
if (state == AppLifecycleState.paused) {
  // Consider unloading model nếu cần RAM
}
```

---

## background_downloader - Large Model Files

### Pitfall: Dùng WorkManager mặc định cho file >2GB
```dart
// ❌ SAI - WorkManager bị kill sau 9 phút trên Android
// File 2.8GB ở 5Mbps = ~75 phút → sẽ bị terminate

// ✅ ĐÚNG - Config Foreground Service TRƯỚC khi download
await FileDownloader().configure(
  globalConfig: [(Config.runInForeground, Config.always)],
);
```

### Pitfall: Không set allowPause = true → mất resume + bị kill sau 9 phút
```dart
// ❌ SAI - trên Android, WorkManager kill task sau 9 phút
// File 2.8GB ở 5Mbps = ~75 phút → bị terminate, mất toàn bộ progress
final task = DownloadTask(url: url, filename: filename);

// ✅ ĐÚNG - allowPause: true là giải pháp chính thức
// Khi 9-min limit gần đến, task tự pause và tự resume → eventually complete
final task = DownloadTask(
  url: url,
  filename: filename,
  allowPause: true,   // ← giải quyết Android 9-min WorkManager limit
  retries: 3,
);

// Android 14+ thêm option: priority 0 → User Initiated Data Transfer
// không bị 9-min limit, không cần pause/resume cycle
// final task = DownloadTask(..., priority: 0);
```

### Pitfall: Không request notification permission trên Android 13+
```dart
// ✅ Request permission khi bắt đầu download
final status = await Permission.notification.request();
if (status.isDenied) {
  // User sẽ không thấy download progress khi app background
  // Vẫn chạy được nhưng UX kém
}
```

### Pitfall: Lưu file vào sai directory
```dart
// ❌ SAI - external storage có thể không accessible
BaseDirectory.temporary  // bị xóa bởi OS

// ✅ ĐÚNG - application documents directory, persistent
BaseDirectory.applicationDocuments
// Path thực: getApplicationDocumentsDirectory()/models/
```

### Pitfall: Thêm flutter_local_notifications cùng background_downloader
```
// ❌ KHÔNG CẦN - background_downloader có built-in notification
// Thêm flutter_local_notifications sẽ conflict notification channel

// ✅ ĐÚNG - dùng configureNotification() của background_downloader
FileDownloader().configureNotification(
  running: const TaskNotification('Đang tải', '{progress}%'),
  complete: const TaskNotification('Hoàn thành', 'Model sẵn sàng'),
);
// Không cần thêm bất kỳ package notification nào khác
```
