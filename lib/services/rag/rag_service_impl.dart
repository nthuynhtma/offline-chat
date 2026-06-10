import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/rag/rag_context.dart';
import 'package:offline_chat/services/rag/rag_service.dart';
import 'package:offline_chat/services/rag/rag_telemetry.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Implementation của [RagService] sử dụng Gecko embedding + SQLite vector search.
///
/// Pipeline:
/// 1. Embed query → GeckoService
/// 2. Vector search → VectorStoreService (topK: 20, threshold: 0.7)
/// 3. Chunk-level trim → removeLast() cho đến khi vừa tokenBudget
/// 4. Log telemetry
/// 5. Return RagContext
class RagServiceImpl implements RagService {
  final GeckoService _geckoService;
  final VectorStoreService _vectorStore;

  /// topK mặc định cho vector search (có thể tune sau).
  static const int _topK = 20;

  /// Threshold cố định 0.7 (sẽ dynamic sau khi có dữ liệu thực tế).
  static const double _threshold = 0.7;

  RagServiceImpl({
    required GeckoService geckoService,
    required VectorStoreService vectorStore,
  })  : _geckoService = geckoService,
        _vectorStore = vectorStore;

  @override
  Future<RagContext> retrieve({
    required String query,
    required int tokenBudget,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (tokenBudget <= 0) {
      log_util.log.w('⚠️ [RagService] tokenBudget <= 0 ($tokenBudget) — skip retrieval');
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

    // 2. Vector search
    List<SearchResult> results;
    try {
      results = await _vectorStore.search(
        queryVector: queryVector,
        topK: _topK,
        threshold: _threshold,
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

    if (results.isEmpty) {
      log_util.log.i('🔍 [RagService] Không tìm thấy chunks liên quan (threshold=$_threshold)');
      return RagContext(chunks: [], tokenCount: 0);
    }

    // 3. Chunk-level trimming (drop last chunks cho đến khi vừa budget)
    // Mỗi chunk cần tính token của cả chunk text + label overhead (e.g. "[Document 1]\n")
    var tokenSum = 0;
    final labelTokenOverhead = estimateTokens('\n[Document N]\n');
    final trimmed = <SearchResult>[];

    for (final chunk in results) {
      final chunkToken = estimateTokens(chunk.chunkText) + labelTokenOverhead;
      if (tokenSum + chunkToken > tokenBudget) {
        break;
      }
      tokenSum += chunkToken;
      trimmed.add(chunk);
    }

    final returnedChunks = trimmed.length;
    final trimmedChunks = matchedChunks - returnedChunks;
    final ragTokenCount = tokenSum;

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