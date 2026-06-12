# Implementation Examples

## 1. GeckoService (flutter_gemma EmbeddingModel)

```dart
// services/gecko/gecko_service.dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_chat/core/errors/app_exception.dart';

abstract interface class GeckoService {
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  });
  Future<void> initialize();
  bool get isReady;
  Future<void> dispose();
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
}

class GeckoServiceImpl implements GeckoService {
  EmbeddingModel? _embeddingModel;
  bool _registered = false;

  /// FIFO lock: tránh race condition GPU/FFI khi gọi embed() song song
  Future<void>? _lock;

  @override
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    if (_registered) return;
    await FlutterGemma.installEmbedder()
        .modelFromFile(modelPath)
        .tokenizerFromFile(tokenizerPath)
        .install();
    _registered = true;
  }

  @override
  Future<void> initialize() async {
    if (_embeddingModel != null) return;
    _embeddingModel = await FlutterGemma.getActiveEmbedder();
  }

  @override
  Future<List<double>> embed(String text) async {
    return _runLocked(() async {
      final model = _embeddingModel;
      if (model == null) throw const ModelNotLoadedException();
      return model.generateEmbedding(text, taskType: TaskType.retrievalQuery);
    });
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return _runLocked(() async {
      final model = _embeddingModel;
      if (model == null) throw const ModelNotLoadedException();
      return model.generateEmbeddings(texts, taskType: TaskType.retrievalDocument);
    });
  }

  /// FIFO lock implementation
  Future<T> _runLocked<T>(Future<T> Function() fn) async {
    await _lock;        // chờ previous lock
    final completer = Completer<void>();
    _lock = completer.future;
    try { return await fn(); }
    finally { completer.complete(); }
  }
}
```

**GeckoRetryService** là decorator wrapping GeckoServiceImpl với retry logic (max 3 lần, exponential backoff).

---

## 2. GemmaService (Session-Based API, flutter_gemma 0.16.4)

```dart
// services/gemma/gemma_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

abstract interface class GemmaService {
  Future<void> initialize({String? modelPath, int maxTokens = kGemmaMaxTokens});
  bool get isReady;
  Future<void> dispose();

  // Legacy prompt-based API
  Stream<String> generateStream(String prompt);
  Future<String> generate(String prompt);

  // Session-based API (turn-based)
  Future<void> createSession({String? systemInstruction});
  Future<void> addHistoryMessage(String role, String content);
  Stream<String> generateWithSession(String userMessage);
  Future<void> closeSession();
  bool get hasActiveSession;
}

class GemmaServiceImpl implements GemmaService {
  InferenceModel? _model;
  InferenceModelSession? _session;

  @override
  bool get isReady => _model != null;
  @override
  bool get hasActiveSession => _session != null;

  @override
  Future<void> initialize({String? modelPath, int maxTokens = kGemmaMaxTokens}) async {
    if (modelPath != null) {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(modelPath).install();
    }
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,  // ⚠️ GPU crash đang điều tra
    );
    log_util.log.i('🚀 [GemmaService] Model initialized with maxTokens=$maxTokens');
  }

  // ─── Legacy API (dùng bởi SummaryService) ────────────────────────────
  // ⚠️ LiteRT LM chỉ support 1 session tại 1 thời điểm.
  // Legacy generate() tạo session mới → invalidate session chính.
  // Fix: set _session = null trước createSession(), báo ChatBloc recreate.

  @override
  Stream<String> generateStream(String prompt) async* {
    if (_model == null) throw const ModelNotLoadedException();
    final savedSession = _session;
    _session = null;  // báo ChatBloc rằng session đã chết
    final session = await _model!.createSession();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      await for (final response in session.getResponseAsync().timeout(
        const Duration(seconds: 120),
        onTimeout: (sink) { sink.addError(const ModelTimeoutException()); sink.close(); },
      )) { yield response; }
    } finally {
      session.close();
      if (savedSession != null) _session = null;
    }
  }

  @override
  Future<String> generate(String prompt) async {
    if (_model == null) throw const ModelNotLoadedException();
    final savedSession = _session;
    _session = null;
    final session = await _model!.createSession();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      return await session.getResponse().timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw const ModelTimeoutException(),
      );
    } finally {
      session.close();
      if (savedSession != null) _session = null;
    }
  }

  // ─── Session-based API ───────────────────────────────────────────────

  @override
  Future<void> createSession({String? systemInstruction}) async {
    if (_model == null) throw const ModelNotLoadedException();
    await _closeSessionInternal();
    _session = await _model!.createSession(systemInstruction: systemInstruction);
  }

  @override
  Future<void> addHistoryMessage(String role, String content) async {
    if (_session == null) await createSession();
    await _session!.addQueryChunk(
      Message.text(text: content, isUser: role == 'user'),
    );
  }

  @override
  Stream<String> generateWithSession(String userMessage) async* {
    if (_model == null) throw const ModelNotLoadedException();
    if (_session == null) throw const ModelNotLoadedException();

    // P0 Logging
    log_util.log.i('[Gemma] generateWithSession: '
        'sessionActive=$hasActiveSession promptLength=${userMessage.length} maxTokens=${_model!.maxTokens}');
    log_util.log.i('[Gemma] sessionHash=${_session.hashCode}');

    final headLen = min(500, userMessage.length);
    log_util.log.i('[Gemma] prompt head:\n${userMessage.substring(0, headLen)}');
    if (userMessage.length > 500) {
      final tailStart = max(0, userMessage.length - 500);
      log_util.log.i('[Gemma] prompt tail:\n${userMessage.substring(tailStart)}');
    }

    try {
      await _session!.addQueryChunk(Message.text(text: userMessage, isUser: true));

      var tokenCount = 0;
      final responseBuffer = StringBuffer();
      await for (final response in _session!.getResponseAsync().timeout(
        const Duration(seconds: 120),
        onTimeout: (sink) { sink.addError(const ModelTimeoutException()); sink.close(); },
      )) {
        tokenCount++;
        responseBuffer.write(response);
        if (tokenCount <= 20) log_util.log.d('[Gemma] token[$tokenCount]=$response');
        yield response;
      }

      final responseStr = responseBuffer.toString();
      log_util.log.i('[Gemma] generateWithSession hoàn tất: $tokenCount tokens');
      log_util.log.i('[Gemma] response preview: ${responseStr.substring(0, min(200, responseStr.length))}');
    } catch (e) {
      log_util.log.w('[Gemma] generateWithSession lỗi: $e');
      await _closeSessionInternal();
      rethrow;
    }
  }

  Future<void> _closeSessionInternal() async {
    log_util.log.d('_closeSessionInternal called\n${StackTrace.current}');
    try { await _session?.close(); } catch (_) {}
    _session = null;
  }

  @override
  Future<void> closeSession() async => await _closeSessionInternal();

  @override
  Future<void> dispose() async {
    await _closeSessionInternal();
    _model = null;
  }
}
```

---

## 3. RagService — RAG Pipeline (VERSION=try_fit_v2)

```dart
// services/rag/rag_service_impl.dart
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/services/rag/rag_context.dart';

class RagServiceImpl implements RagService {
  static const int _topK = 20;
  static const double _threshold = 0.7;

  @override
  Future<RagContext> retrieve({
    required String query,
    required int tokenBudget,
    required KnowledgeScope scope,
    String? sessionId,
  }) async {
    // 0. Early exit guard
    final skipReason = _shouldSkipRag(query);
    if (skipReason != null) {
      log_util.log.i('[RAG] skip reason=${skipReason.name} query="$query"');
      return RagContext(chunks: [], tokenCount: 0);
    }

    // 1. Embed query
    if (!_geckoService.isReady) return RagContext(chunks: [], tokenCount: 0);
    final queryVector = await _geckoService.embed(query);

    // 2. Filter completed documents theo scope
    Set<String>? allowedDocIds;
    // ... (getCompletedDocumentIdsBySessionId, getCompletedGlobalDocumentIds, etc.)

    // 3. Vector search
    final results = await _vectorStore.search(
      queryVector: queryVector,
      topK: _topK,
      threshold: _threshold,
      allowedDocumentIds: allowedDocIds,
    );

    // 4. Log candidates (top 3)
    log_util.log.i('[RAG] VERSION=try_fit_v2');
    for (final c in results.take(3)) {
      final tokens = estimateTokens(c.chunkText);
      log_util.log.i('[RAG] candidate score=${c.score.toStringAsFixed(3)} '
          'chars=${c.chunkText.length} tokens=$tokens preview="${c.chunkText.substring(0, min(150, c.chunkText.length))}..."');
    }

    // 5. Try-fit packing
    var tokenSum = 0;
    final effectiveCap = min(tokenBudget, kMaxRagTokens);
    final labelTokenOverhead = estimateTokens('\n[Document N]\n');
    final trimmed = <SearchResult>[];
    var chunkCount = 0;

    for (final chunk in results) {
      if (chunkCount >= kMaxRagChunks) break;
      final chunkToken = estimateTokens(chunk.chunkText) + labelTokenOverhead;
      if (chunkToken > effectiveCap) continue;       // continue—không break
      if (tokenSum + chunkToken <= effectiveCap) {
        trimmed.add(chunk);
        tokenSum += chunkToken;
        chunkCount++;
        if (tokenSum >= effectiveCap) break;          // safety guard
      }
    }

    log_util.log.i('[RAG] packing matched=${results.length} packed=${trimmed.length} '
        'tokens=$tokenSum cap=$effectiveCap');

    return RagContext(chunks: trimmed, tokenCount: tokenSum);
  }

  RagSkipReason? _shouldSkipRag(String query) {
    final q = query.trim().toLowerCase();
    if (q.split(' ').length <= 2 && !q.contains('?') && q.length < 15) return RagSkipReason.tooShort;
    if (RegExp(r'^(hi|hello|hey|chào|xin chào)(\s|$)').hasMatch(q)) return RagSkipReason.greeting;
    if (q.contains('bạn là ai') || q.contains('giúp gì') || q.contains('what can you do')) return RagSkipReason.capability;
    return null;
  }
}

enum RagSkipReason { greeting, tooShort, capability }
```

---

## 4. VectorStore — SQLite Cosine Search (2-step)

```dart
// services/vectorstore/vector_store_service_impl.dart
class VectorStoreServiceImpl implements VectorStoreService {
  final AppDatabase _db;
  static const int _preTopK = 200;  // lấy 200 candidates trước, re-rank topK

  VectorStoreServiceImpl(this._db);

  @override
  Future<List<SearchResult>> search({
    required List<double> queryVector,
    int topK = 5,
    double threshold = 0.7,
    Set<String>? allowedDocumentIds,
  }) async {
    // Step 1: Lấy tất cả vectors
    final allVectors = await _db.vectorsDao.getAllVectors();
    if (allVectors.isEmpty) return [];

    // Step 2: Filter theo allowedDocumentIds (filter trước ranking)
    var candidates = allVectors;
    if (allowedDocumentIds != null && allowedDocumentIds.isNotEmpty) {
      final chunkIdsInScope = await _db.chunksDao.getChunkIdsByDocumentIds(allowedDocumentIds);
      final chunkIdSet = chunkIdsInScope.toSet();
      candidates = allVectors.where((v) => chunkIdSet.contains(v.chunkId)).toList();
    }

    // Step 3: Cosine similarity → preTopK
    final scored = <_ScoredResult>[];
    for (final v in candidates) {
      final embedding = EmbeddingSerializer.deserialize(v.embedding);
      if (embedding.length != queryVector.length) continue;
      final score = _cosineSimilarity(queryVector, embedding);
      if (score >= threshold) {
        scored.add(_ScoredResult(chunkId: v.chunkId, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final preTopResults = scored.take(_preTopK).toList();

    // Step 4: Re-rank → topK
    final topResults = preTopResults.take(topK).toList();

    // Fetch chunk texts
    final chunkIds = topResults.map((r) => r.chunkId).toList();
    final chunks = await _db.chunksDao.getChunksByIds(chunkIds);
    final chunkMap = {for (final c in chunks) c.id: c.chunkText};

    return topResults
        .where((r) => chunkMap.containsKey(r.chunkId))
        .map((r) => SearchResult(chunkId: r.chunkId, score: r.score, chunkText: chunkMap[r.chunkId]!))
        .toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
```

---

## 5. ChunkingService

```dart
// services/chunker/chunking_service_impl.dart
class ChunkingServiceImpl implements ChunkingService {
  @override
  List<String> chunk(String text, {int chunkSize = 500, int overlap = 100}) {
    if (text.isEmpty) return [];
    const int charsPerToken = 4;
    final charSize = chunkSize * charsPerToken;
    final charOverlap = overlap * charsPerToken;
    final step = charSize - charOverlap;

    if (text.length <= charSize) return [text.trim()];

    final chunks = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = min(start + charSize, text.length);
      if (end < text.length) {
        final nextSpace = text.indexOf(' ', end - 50);
        if (nextSpace != -1 && nextSpace < end + 50) end = nextSpace;
      }
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      start += step;
      if (start >= text.length) break;
    }
    return chunks;
  }
}

// Runtime default (set trong DocumentUploadQueue):
//   chunkSize = 200, overlap = 50
```
**Lưu ý:** charsPerToken = 4 (chunker) vs kCharsPerToken = 2.5 (estimator). Chunk thực tế ≈ 1.6x so với chunkSize.

---

## 6. DocumentUploadQueue — FIFO Pipeline

```dart
// services/chunker/document_upload_queue.dart
// (trích đoạn quan trọng)

const int chunkSize = 200;
const int chunkOverlap = 50;
final chunks = _chunker.chunk(rawText, chunkSize: chunkSize, overlap: chunkOverlap);

// Log chunk detail với estimateTokens()
for (var i = 0; i < chunks.length; i++) {
  final estimatedTokens = estimateTokens(chunks[i]);
  final previewLen = min(60, chunks[i].length);
  final preview = previewLen > 0 ? chunks[i].substring(0, previewLen) : '';
  logger.log.d('[UploadQueue] chunk[$i] chars=${chunks[i].length} '
      'tokens=$estimatedTokens preview="$preview..."');
}
logger.log.i('[UploadQueue] Completed: ${job.name} (${chunks.length} chunks, ${insertedChunks.length} vectors)');
```

---

## 7. PromptBuilder — Prompt Pipeline (VERSION=dedup_v1)

```dart
// services/prompt/prompt_builder_service.dart
const int kMaxHistoryTokens = 300;

final class PromptBuilderImpl implements PromptBuilder {
  @override
  Future<String> build({
    required String question,
    required RagContext ragContext,
    required List<MessageModel> history,
    String? sessionSummary,
    List<UserMemory>? userMemories,
  }) async {
    log_util.log.d('🔨 [PromptBuilder] VERSION=dedup_v1 Bắt đầu build prompt...');
    final buffer = StringBuffer();

    // ─── 1. System turn ──────────────────────────────────────────────
    buffer.writeln('<start_of_turn>system');
    buffer.writeln('''You are AgriAI, an agricultural assistant...''');

    // ─── 2. User Memories ─────────────────────────────────────────────
    if (userMemories != null && userMemories.isNotEmpty) {
      buffer.writeln('\n=== User Memory ===');
      for (final mem in userMemories) {
        buffer.writeln('- ${mem.namespace}:${mem.key} → ${mem.value}');
      }
    }

    // ─── 3. Session Summary ───────────────────────────────────────────
    if (sessionSummary != null && sessionSummary.isNotEmpty) {
      buffer.writeln('\n=== Session Summary ===');
      buffer.writeln(sessionSummary);
    }
    buffer.writeln('<end_of_turn>');

    // ─── 4. Recent Conversation (budget-based truncation) ─────────────
    var historyToInclude = (history.isNotEmpty &&
        history.last.role.name == 'user' &&
        history.last.content == question)
        ? history.sublist(0, history.length - 1)
        : history;

    if (historyToInclude.isNotEmpty) {
      final selected = <MessageModel>[];
      var tokenBudget = kMaxHistoryTokens;
      for (var i = historyToInclude.length - 1; i >= 0; i--) {
        final msg = historyToInclude[i];
        final msgTokens = estimateTokens(msg.content) +
            estimateTokens('<start_of_turn>role<end_of_turn>\n');
        if (tokenBudget - msgTokens < 0) break;
        tokenBudget -= msgTokens;
        selected.add(msg);
      }
      historyToInclude = selected.reversed.toList();
    }

    if (historyToInclude.isNotEmpty) {
      buffer.writeln('=== Recent Conversation ===');
      for (final msg in historyToInclude) {
        buffer.writeln('<start_of_turn>${msg.role.name}');
        buffer.writeln(msg.content);
        buffer.writeln('<end_of_turn>');
      }
    }

    // ─── 5. RAG Context ───────────────────────────────────────────────
    if (ragContext.hasContext) {
      buffer.writeln('\n=== Reference Documents ===');
      for (int i = 0; i < ragContext.chunks.length; i++) {
        buffer.writeln('\n[Document ${i + 1}]');
        buffer.writeln(ragContext.chunks[i].chunkText);
      }
    }

    // ─── 6. Current Question ──────────────────────────────────────────
    buffer.writeln('\n=== Current Question ===');
    buffer.writeln('<start_of_turn>user');
    buffer.writeln(question);
    buffer.writeln('<end_of_turn>');
    buffer.write('<start_of_turn>model\n');

    return buffer.toString();
  }
}
```

---

## 8. ChatBloc — Full Implementation (Refactored)

```dart
// features/chat/bloc/chat_bloc.dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final MessageRepository _messageRepo;
  final SessionRepository _sessionRepo;
  final GemmaService _gemmaService;
  final ModelBloc _modelBloc;
  final MemoryStoreService _memoryStore;
  final SummaryService _summaryService;
  final RagService _ragService;
  final PromptBuilder _promptBuilder;

  String? _currentSessionId;
  String _accumulatedText = '';
  List<MessageModel> _currentMessages = [];
  StreamSubscription<ModelState>? _modelSubscription;
  String? _pendingMessage;
  bool _isWaitingForModel = false;
  bool _isSummarizing = false;
  late final MemoryBudgetConfig _memoryBudget;
  KnowledgeScope _currentScope = KnowledgeScope.attachedAndGlobal;

  ChatBloc({
    required MessageRepository messageRepo,
    required SessionRepository sessionRepo,
    required GemmaService gemmaService,
    required ModelBloc modelBloc,
    required MemoryStoreService memoryStore,
    required SummaryService summaryService,
    required RagService ragService,
    required PromptBuilder promptBuilder,
    int? contextWindow,
  })  : ... super(const ChatInitial()) {
    on<SessionInitialized>(_onSessionInitialized);
    on<SendMessageRequested>(_onSendMessageRequested);
    on<StreamingCancelled>(_onStreamingCancelled);
    on<MessagesCleared>(_onMessagesCleared);
    on<ModelBecameReady>(_onModelBecameReady);
    on<KnowledgeScopeChanged>(_onKnowledgeScopeChanged);
  }

  Future<void> _onSendMessageRequested(
    SendMessageRequested event,
    Emitter<ChatState> emit,
  ) async {
    // Guard checks
    if (isClosed || _currentSessionId == null) return;

    // Nếu model chưa ready nhưng đã download → subscribe chờ
    if (!_gemmaService.isReady) { /* subscribe ModelBloc */ return; }

    // 1. Save user message → DB → emit ChatThinking
    final userMsg = await _messageRepo.saveMessage(...);
    emit(ChatThinking(currentMessages));

    // 2. RAG retrieval
    final ragContext = await _ragService.retrieve(
      query: event.content,
      tokenBudget: ragBudget.clamp(0, kGemmaMaxTokens),
      scope: scope,
      sessionId: _currentSessionId,
    );

    // 3. Build prompt
    final prompt = await _promptBuilder.build(
      question: event.content,
      ragContext: ragContext,
      history: _currentMessages,
      sessionSummary: memoryRow?.summary,
      userMemories: userMemoryList,
    );

    // 4. Ensure session exists
    if (!_gemmaService.hasActiveSession) {
      await _createGemmaSessionWithHistory(_currentMessages);
    }

    // 5. Stream response
    await emit.forEach<String>(
      _gemmaService.generateWithSession(prompt),
      onData: (token) { ... return ChatStreaming(...); },
      onError: (error, _) { _gemmaService.closeSession(); return ChatError(...); },
    );

    // 6. Save assistant message
    // 7. Trigger auto-summary
  }

  Future<void> _createGemmaSessionWithHistory(List<MessageModel> messages) async {
    await _gemmaService.createSession(systemInstruction: kSystemPrompt);
    // Replay history (35% context, từ mới→cũ)
    for (final msg in historyMessages) {
      await _gemmaService.addHistoryMessage(msg.role.name, msg.content);
    }
  }
}
```

---

## 9. ChatPage — UI (Refactored 11/06/2026)

```dart
// features/chat/views/chat_page.dart — 167 dòng
class ChatPage extends StatelessWidget {
  final String sessionId;
  const ChatPage({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey('chat_$sessionId'),
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: const ChatView(),
    );
  }
}

// ChatView: 11 widget con tách riêng
// - ModelNotInstalledBanner
// - ScopeSelector (PopupMenuButton, KnowledgeScope)
// - ClearButton (BlocBuilder riêng, buildWhen: streaming)
// - ChatBody (BlocBuilder, buildWhen: trừ ChatThinking→ChatThinking)
//   └─ MessageList (ScrollController + ListViewObserver)
//        ├─ MessageBubble (user: right blue, assistant: left gray)
//        └─ LastBubble (BlocBuilder riêng, buildWhen: streamingText)
//             ├─ ChatThinking → ThinkingBubble (3 chấm)
//             └─ ChatStreaming → MessageBubble(isStreaming: true)
// - ScrollToBottomButton (AnimatedOpacity + AnimatedSlide)
// - AttachedFilesBar (BlocBuilder<SessionFilesCubit>)
// - ChatInputBar (BlocListener → setState local _isStreaming)
```

---

## 10. Token Estimator

```dart
// core/utils/token_estimator.dart
const double kCharsPerToken = 2.5;
const int kRoleOverheadTokens = 5;

int estimateTokens(String text) => (text.length / kCharsPerToken).round();
int estimateMessageTokens(String text) => estimateTokens(text) + kRoleOverheadTokens;
```

---

## 11. Context Budget Calculation

```dart
// Trong chat_bloc.dart _onSendMessageRequested:
final historyBudget = (kGemmaMaxTokens * kHistoryBudgetRatio).round();   // 35%
final reservedResponse = (kGemmaMaxTokens * kResponseBudgetRatio).round(); // 25%
final reservedSystem = (kGemmaMaxTokens * kSystemBudgetRatio).round();    // 10%
final questionTokens = estimateTokens(event.content);

// Tính history tokens thực tế
var historyTokenSum = 0;
for (int i = _currentMessages.length - 1; i >= 0; i--) {
  final msgToken = estimateMessageTokens(_currentMessages[i].content);
  if (historyTokenSum + msgToken > historyBudget) break;
  historyTokenSum += msgToken;
}

final ragBudget = kGemmaMaxTokens - historyTokenSum - reservedResponse - reservedSystem - questionTokens;
```

---

## 12. DI Registration Pattern

```dart
// injection/service_locator.dart (trích đoạn)

// Singleton services
sl.registerLazySingleton<GemmaService>(() => GemmaServiceImpl());
sl.registerLazySingleton<GeckoService>(() => GeckoRetryService(GeckoServiceImpl()));
sl.registerLazySingleton<RagService>(() => RagServiceImpl(db: sl(), geckoService: sl(), vectorStore: sl()));
sl.registerLazySingleton<PromptBuilder>(() => PromptBuilderImpl());

// Singleton blocs (lifecycle do MultiBlocProvider ở app.dart)
sl.registerLazySingleton<ModelBloc>(() => ModelBloc(modelManager: sl(), gemmaService: sl(), geckoService: sl()));

// Factory — mỗi session 1 instance riêng
sl.registerFactory<ChatBloc>(() => ChatBloc(
  messageRepo: sl(), sessionRepo: sl(), gemmaService: sl(),
  modelBloc: sl(), memoryStore: sl(), summaryService: sl(),
  ragService: sl(), promptBuilder: sl(),
));