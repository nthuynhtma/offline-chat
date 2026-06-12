import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/rag/rag_context.dart';
import 'package:offline_chat/services/rag/rag_service.dart';
import 'package:offline_chat/services/rag/rag_telemetry.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Lý do skip RAG cho no-context query.
enum RagSkipReason { greeting, tooShort, capability }

/// Implementation của [RagService] sử dụng Gecko embedding + SQLite vector search.
///
/// Pipeline:
/// 1. Embed query → GeckoService
/// 2. Vector search → VectorStoreService (topK: 20, threshold: 0.7)
/// 3. Try-fit packing (greedy knapsack)
/// 4. Log telemetry
/// 5. Return RagContext
/// 
/// VERSION=try_fit_v2
class RagServiceImpl implements RagService {
  final AppDatabase _db;
  final GeckoService _geckoService;
  final VectorStoreService _vectorStore;

  /// topK mặc định cho vector search (có thể tune sau).
  static const int _topK = 20;

  /// Threshold cố định 0.7 (sẽ dynamic sau khi có dữ liệu thực tế).
  static const double _threshold = 0.7;

  RagServiceImpl({
    required AppDatabase db,
    required GeckoService geckoService,
    required VectorStoreService vectorStore,
  })  : _db = db,
        _geckoService = geckoService,
        _vectorStore = vectorStore;

  /// Kiểm tra query có phải no-context (greeting, capability, quá ngắn) hay không.
  /// Trả về [RagSkipReason] nếu skip, null nếu không.
  RagSkipReason? _shouldSkipRag(String query) {
    final q = query.trim().toLowerCase();

    // Rule 1: quá ngắn (<= 2 từ, không có dấu ?, và < 15 ký tự)
    if (q.split(' ').length <= 2 && !q.contains('?') && q.length < 15) {
      return RagSkipReason.tooShort;
    }

    // Rule 2: greeting pattern
    if (RegExp(r'^(hi|hello|hey|chào|xin chào)(\s|$)').hasMatch(q)) {
      return RagSkipReason.greeting;
    }

    // Rule 3: capability question
    if (q.contains('bạn là ai') ||
        q.contains('giúp gì') ||
        q.contains('what can you do')) {
      return RagSkipReason.capability;
    }

    return null;
  }

  @override
  Future<RagContext> retrieve({
    required String query,
    required int tokenBudget,
    required KnowledgeScope scope,
    String? sessionId,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (tokenBudget <= 0) {
      log_util.log.w('⚠️ [RagService] tokenBudget <= 0 ($tokenBudget) — skip retrieval');
      return RagContext(chunks: [], tokenCount: 0);
    }

    // 0. Early exit: no-context query → skip RAG
    final skipReason = _shouldSkipRag(query);
    if (skipReason != null) {
      log_util.log.i('[RAG] skip reason=${skipReason.name} query="$query"');
      return RagContext(chunks: [], tokenCount: 0);
    }

    // 1. Embed query
    if (!_geckoService.isReady) {
      log_util.log.w('⚠️ [RagService] Gecko chưa ready — graceful degradation, skip RAG');
      return RagContext(chunks: [], tokenCount: 0);
    }

    List<double> queryVector;
    try {
      queryVector = await _geckoService.embed(query);
    } catch (e) {
      log_util.log.w('⚠️ [RagService] Lỗi embed query: $e — graceful degradation');
      return RagContext(chunks: [], tokenCount: 0);
    }
    final embedTime = stopwatch.elapsedMilliseconds;

    // 2. Xác định document IDs theo scope (chỉ lấy documents đã completed)
    Set<String>? allowedDocIds;
    try {
      if (scope == KnowledgeScope.attachedOnly && sessionId != null) {
        // Session documents (completed) + referenced global docs (completed)
        final sessionDocIds = await _db.documentsDao
            .getCompletedDocumentIdsBySessionId(sessionId);
        final refDocIds = await _db.sessionDocumentRefsDao
            .getDocumentIdsBySession(sessionId);
        // Filter referenced docs: chỉ lấy những doc đã completed
        final completedRefDocIds = refDocIds.isNotEmpty
            ? await _db.documentsDao.getCompletedDocumentIdsByIds(refDocIds)
            : <String>{};
        allowedDocIds = {...sessionDocIds, ...completedRefDocIds};
      } else if (scope == KnowledgeScope.globalOnly) {
        // Global documents only (completed)
        allowedDocIds = await _db.documentsDao.getCompletedGlobalDocumentIds();
      } else if (scope == KnowledgeScope.attachedAndGlobal) {
        // Global + session + attached global docs (tất cả completed)
        final globalDocIds = await _db.documentsDao.getCompletedGlobalDocumentIds();
        final sessionDocIds = sessionId != null
            ? await _db.documentsDao.getCompletedDocumentIdsBySessionId(sessionId)
            : <String>{};
        final refDocIds = sessionId != null
            ? await _db.sessionDocumentRefsDao.getDocumentIdsBySession(sessionId)
            : <String>{};
        final completedRefDocIds = refDocIds.isNotEmpty
            ? await _db.documentsDao.getCompletedDocumentIdsByIds(refDocIds)
            : <String>{};
        allowedDocIds = {...globalDocIds, ...sessionDocIds, ...completedRefDocIds};
      }
      // Nếu không có documents nào trong scope → skip RAG (early return, không embed)
      if (allowedDocIds != null && allowedDocIds.isEmpty) {
        log_util.log.i('🔍 [RagService] Không có completed documents trong scope ($scope) — skip RAG');
        return RagContext(chunks: [], tokenCount: 0);
      }
    } catch (e) {
      log_util.log.w('⚠️ [RagService] Lỗi khi get document IDs theo scope: $e — graceful degradation');
      return RagContext(chunks: [], tokenCount: 0);
    }

    // 3. Vector search với allowedDocumentIds
    List<SearchResult> results;
    try {
      results = await _vectorStore.search(
        queryVector: queryVector,
        topK: _topK,
        threshold: _threshold,
        allowedDocumentIds: allowedDocIds,
      );
    } catch (e) {
      log_util.log.w('⚠️ [RagService] Lỗi vector search: $e — graceful degradation');
      return RagContext(chunks: [], tokenCount: 0);
    }
    final searchTime = stopwatch.elapsedMilliseconds - embedTime;
    final totalTime = stopwatch.elapsedMilliseconds;

    // Collect top scores (giới hạn theo kTelemetryTopScoresCount)
    final topScores = results
        .take(kTelemetryTopScoresCount)
        .map((r) => r.score)
        .toList();

    final matchedChunks = results.length;

    // Log candidates info (top 3 chunks): score, chars, estimatedTokens, preview
    log_util.log.i('[RAG] VERSION=try_fit_v2');
    for (final c in results.take(3)) {
      final tokens = estimateTokens(c.chunkText);
      final preview = c.chunkText.length > 150
          ? '${c.chunkText.substring(0, 150)}...'
          : c.chunkText;
      log_util.log.i(
        '[RAG] candidate score=${c.score.toStringAsFixed(3)} '
        'chars=${c.chunkText.length} tokens=$tokens '
        'preview="$preview"',
      );
    }

    if (results.isEmpty) {
      log_util.log.i('🔍 [RagService] Không tìm thấy chunks liên quan (threshold=$_threshold)');
      return RagContext(chunks: [], tokenCount: 0);
    }

    // 3. Try-fit packing (greedy knapsack, không early break)
    // Mỗi chunk cần tính token của cả chunk text + label overhead (e.g. "[Document 1]\n")
    var tokenSum = 0;
    final effectiveCap = tokenBudget < kMaxRagTokens ? tokenBudget : kMaxRagTokens;
    final labelTokenOverhead = estimateTokens('\n[Document N]\n');
    final trimmed = <SearchResult>[];
    var chunkCount = 0;

    for (final chunk in results) {
      // Hard cap: max chunks
      if (chunkCount >= kMaxRagChunks) break;

      final chunkToken = estimateTokens(chunk.chunkText) + labelTokenOverhead;

      // Skip chunk nếu 1 chunk quá lớn so với cap
      if (chunkToken > effectiveCap) continue;

      // Try-fit: chỉ add nếu còn chỗ
      if (tokenSum + chunkToken <= effectiveCap) {
        trimmed.add(chunk);
        tokenSum += chunkToken;
        chunkCount++;

        // Safety guard: dừng khi đã đầy budget
        if (tokenSum >= effectiveCap) break;
      }
    }

    final returnedChunks = trimmed.length;
    final trimmedChunks = matchedChunks - returnedChunks;
    final ragTokenCount = tokenSum;

    // Log packing result
    log_util.log.i(
      '[RAG] packing matched=$matchedChunks packed=$returnedChunks '
      'tokens=$ragTokenCount cap=$effectiveCap',
    );

    // Tính bestScore từ chunk đầu tiên (đã sort score desc)
    final bestScore = trimmed.isNotEmpty ? trimmed.first.score : null;

    // 4. Log telemetry
    final telemetry = RagTelemetry(
      query: query,
      embeddingTimeMs: embedTime,
      searchTimeMs: searchTime,
      retrievalTimeMs: totalTime,
      topScores: topScores,
      matchedChunks: matchedChunks,
      trimmedChunks: trimmedChunks,
      returnedChunks: returnedChunks,
      ragTokenCount: ragTokenCount,
      ragTokenBudget: tokenBudget,
    );
    log_util.log.i(telemetry.toLogString());

    return RagContext(
      chunks: trimmed,
      tokenCount: ragTokenCount,
      bestScore: bestScore,
    );
  }
}