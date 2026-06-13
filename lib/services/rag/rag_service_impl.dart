import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/services/bm25/bm25_service.dart';
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
/// VERSION=hybrid_v1 (hybrid search: dense + sparse + RRF)
class RagServiceImpl implements RagService {
  final AppDatabase _db;
  final GeckoService _geckoService;
  final VectorStoreService _vectorStore;
  final Bm25Service _bm25Service;

  /// topK cho vector search và BM25 search (hybrid search cần 50 candidates).
  static const int _topK = 50;

  /// Threshold cho cosine similarity.
  static const double _threshold = 0.7;

  /// RRF constant (k=60 là giá trị chuẩn).
  static const int _rrfK = 60;

  RagServiceImpl({
    required AppDatabase db,
    required GeckoService geckoService,
    required VectorStoreService vectorStore,
    required Bm25Service bm25Service,
  })  : _db = db,
        _geckoService = geckoService,
        _vectorStore = vectorStore,
        _bm25Service = bm25Service;

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

    // 3. Vector search (dense) với allowedDocumentIds
    List<SearchResult> denseResults;
    try {
      denseResults = await _vectorStore.search(
        queryVector: queryVector,
        topK: _topK,
        threshold: _threshold,
        allowedDocumentIds: allowedDocIds,
      );
    } catch (e) {
      log_util.log.w('⚠️ [RagService] Lỗi vector search: $e — graceful degradation');
      return RagContext(chunks: [], tokenCount: 0);
    }
    final denseSearchTime = stopwatch.elapsedMilliseconds - embedTime;

    // 4. Sparse search (BM25)
    List<SearchResult> sparseResults;
    try {
      sparseResults = await _bm25Service.search(
        query: query,
        allowedDocumentIds: allowedDocIds ?? <String>{},
        topK: _topK,
      );
    } catch (e) {
      log_util.log.w('⚠️ [RagService] Lỗi BM25 search: $e — graceful degradation');
      sparseResults = [];
    }
    final sparseSearchTime = stopwatch.elapsedMilliseconds - embedTime - denseSearchTime;
    final totalTime = stopwatch.elapsedMilliseconds;

    // 5. Reciprocal Rank Fusion (RRF) + fallback nếu 1 trong 2 nguồn rỗng
    final List<SearchResult> results;
    final int denseCount = denseResults.length;
    final int sparseCount = sparseResults.length;

    if (denseResults.isEmpty && sparseResults.isEmpty) {
      log_util.log.i('🔍 [RagService] Không tìm thấy chunks liên quan (cả dense và sparse đều rỗng)');
      return RagContext(chunks: [], tokenCount: 0);
    } else if (denseResults.isEmpty) {
      results = sparseResults;
      log_util.log.d('[RAG] Fallback: chỉ có sparse results (dense rỗng)');
    } else if (sparseResults.isEmpty) {
      results = denseResults;
      log_util.log.d('[RAG] Fallback: chỉ có dense results (sparse rỗng)');
    } else {
      results = _reciprocalRankFusion(denseResults, sparseResults);
    }

    // Collect top scores
    final topScores = results
        .take(kTelemetryTopScoresCount)
        .map((r) => r.score)
        .toList();

    final matchedChunks = results.length;

    // Log candidates info (top 3 chunks)
    log_util.log.i('[RAG] VERSION=hybrid_v1 dense=$denseCount sparse=$sparseCount fused=$matchedChunks');
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

    // 6. Try-fit packing (greedy knapsack, không early break)
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

    // 7. Log telemetry
    final telemetry = RagTelemetry(
      query: query,
      embeddingTimeMs: embedTime,
      searchTimeMs: denseSearchTime + sparseSearchTime,
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

  /// Reciprocal Rank Fusion: kết hợp dense và sparse search results.
  /// [k] = RRF constant (60 là giá trị chuẩn).
  List<SearchResult> _reciprocalRankFusion(
    List<SearchResult> denseResults,
    List<SearchResult> sparseResults,
  ) {
    final scores = <String, double>{};
    final chunkMap = <String, SearchResult>{};

    // Dense search scores
    for (int i = 0; i < denseResults.length; i++) {
      final chunk = denseResults[i];
      scores[chunk.chunkId] = (scores[chunk.chunkId] ?? 0) + (1.0 / (_rrfK + i + 1));
      chunkMap[chunk.chunkId] = chunk;
    }

    // Sparse search scores
    for (int i = 0; i < sparseResults.length; i++) {
      final chunk = sparseResults[i];
      scores[chunk.chunkId] = (scores[chunk.chunkId] ?? 0) + (1.0 / (_rrfK + i + 1));
      chunkMap[chunk.chunkId] = chunk;
    }

    // Sort by fused score (descending)
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.map((e) {
      final chunk = chunkMap[e.key]!;
      return SearchResult(
        chunkId: chunk.chunkId,
        score: e.value, // Fused score
        chunkText: chunk.chunkText,
      );
    }).toList();
  }
}
