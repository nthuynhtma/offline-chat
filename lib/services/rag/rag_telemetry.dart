import 'package:offline_chat/core/constants/model_constants.dart';

/// Trạng thái retrieval dựa trên kết quả thực tế.
///
/// Lưu ý: Đây là computed state, không phải stored field.
/// Được tính từ [returnedChunks] và [bestScore].
enum RetrievalResultState {
  /// Không có chunk nào được trả về (returnedChunks == 0)
  empty,

  /// Có chunk nhưng bestScore < kWeakScoreThreshold
  weak,

  /// Retrieval bình thường (bestScore >= kWeakScoreThreshold)
  normal,
}

/// Bucket cho score histogram trong Aggregator.
enum ScoreBucket {
  below70,
  between70And80,
  between80And90,
  above90,
}

/// Telemetry cho một lần retrieval.
///
/// Tất cả scores là computed getters từ [topScores] — không lưu duplicated state.
/// [RetrievalResultState] cũng là computed, không phải stored field.
class RagTelemetry {
  /// Query gốc của user
  final String query;

  /// Thời gian embed query (ms)
  final int embeddingTimeMs;

  /// Thời gian search vector DB (ms)
  final int searchTimeMs;

  /// Tổng thời gian retrieval (embed + search) (ms)
  final int retrievalTimeMs;

  /// Top scores (tối đa kTelemetryTopScoresCount items, sorted desc)
  final List<double> topScores;

  /// Tổng số chunks matched từ vector search
  final int matchedChunks;

  /// Số chunks bị trim do vượt budget
  final int trimmedChunks;

  /// Số chunks thực tế được trả về (matched - trimmed)
  final int returnedChunks;

  /// Token count riêng của RAG chunks
  final int ragTokenCount;

  /// Budget dành cho RAG
  final int ragTokenBudget;

  /// Tổng token của toàn bộ prompt (history + summary + rag + ...)
  final int totalPromptTokenCount;

  // ─── Computed getters (không lưu field) ───────────────────────────────

  /// Best score (top-1), null nếu không có chunk nào
  double? get bestScore => topScores.isEmpty ? null : topScores.first;

  /// Gap giữa top-1 và top-2, null nếu có < 2 scores
  double? get bestScoreGap =>
      topScores.length < 2 ? null : topScores[0] - topScores[1];

  /// Worst score, null nếu không có chunk nào
  double? get worstScore => topScores.isEmpty ? null : topScores.last;

  /// Trạng thái retrieval (derived state)
  RetrievalResultState get state {
    if (returnedChunks == 0) return RetrievalResultState.empty;
    if ((bestScore ?? 0) < kWeakScoreThreshold) {
      return RetrievalResultState.weak;
    }
    return RetrievalResultState.normal;
  }

  const RagTelemetry({
    required this.query,
    required this.embeddingTimeMs,
    required this.searchTimeMs,
    required this.retrievalTimeMs,
    required this.topScores,
    required this.matchedChunks,
    required this.trimmedChunks,
    required this.returnedChunks,
    required this.ragTokenCount,
    required this.ragTokenBudget,
    required this.totalPromptTokenCount,
  });

  /// Format telemetry thành log string.
  String toLogString() {
    final scoresStr = topScores.take(kTelemetryTopScoresCount).join(', ');
    return '[RAG] query="$query" '
        'embed=${embeddingTimeMs}ms '
        'search=${searchTimeMs}ms '
        'total=${retrievalTimeMs}ms | '
        'scores: $scoresStr '
        'gap=${bestScoreGap?.toStringAsFixed(3) ?? "N/A"} | '
        'matched=$matchedChunks '
        'returned=$returnedChunks '
        'trimmed=$trimmedChunks | '
        'budget=$ragTokenBudget '
        'ragTokens=$ragTokenCount '
        'totalPromptTokens=$totalPromptTokenCount | '
        'state=$state';
  }
}