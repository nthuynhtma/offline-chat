import 'dart:math';
import 'package:offline_chat/services/rag/rag_telemetry.dart';

/// Aggregator cho Retrieval Telemetry.
///
/// Thu thập và tổng hợp [RagTelemetry] từ nhiều queries để cung cấp
/// dashboard số liệu về health của RAG pipeline.
///
/// Dùng để quyết định:
/// - Dynamic Threshold (dựa trên score distribution thực tế)
/// - Có cần tăng/giảm topK không
/// - Chunk size có đang phù hợp không
class RagTelemetryAggregator {
  int _totalQueries = 0;
  int _emptyCount = 0;
  int _weakCount = 0;
  int _normalCount = 0;

  int _totalRetrievalTimeMs = 0;
  int _totalTrimmedChunks = 0;
  int _totalReturnedChunks = 0;
  int _totalMatchedChunks = 0;

  // Score buckets: below70, between70And80, between80And90, above90
  final Map<ScoreBucket, int> _scoreBuckets = {
    ScoreBucket.below70: 0,
    ScoreBucket.between70And80: 0,
    ScoreBucket.between80And90: 0,
    ScoreBucket.above90: 0,
  };

  double _sumBestScores = 0;
  double _sumBestScoreGaps = 0;
  int _gapCount = 0;
  double _maxRetrievalTimeMs = 0;

  /// Ghi nhận một telemetry entry.
  void record(RagTelemetry telemetry) {
    _totalQueries++;

    // State counts
    switch (telemetry.state) {
      case RetrievalResultState.empty:
        _emptyCount++;
        break;
      case RetrievalResultState.weak:
        _weakCount++;
        break;
      case RetrievalResultState.normal:
        _normalCount++;
        break;
    }

    // Timing
    _totalRetrievalTimeMs += telemetry.retrievalTimeMs;
    _maxRetrievalTimeMs =
        max(_maxRetrievalTimeMs, telemetry.retrievalTimeMs.toDouble());

    // Chunks
    _totalTrimmedChunks += telemetry.trimmedChunks;
    _totalReturnedChunks += telemetry.returnedChunks;
    _totalMatchedChunks += telemetry.matchedChunks;

    // Best score
    final bestScore = telemetry.bestScore;
    if (bestScore != null) {
      _sumBestScores += bestScore;
      if (bestScore < 0.7) {
        _scoreBuckets[ScoreBucket.below70] =
            (_scoreBuckets[ScoreBucket.below70] ?? 0) + 1;
      } else if (bestScore < 0.8) {
        _scoreBuckets[ScoreBucket.between70And80] =
            (_scoreBuckets[ScoreBucket.between70And80] ?? 0) + 1;
      } else if (bestScore < 0.9) {
        _scoreBuckets[ScoreBucket.between80And90] =
            (_scoreBuckets[ScoreBucket.between80And90] ?? 0) + 1;
      } else {
        _scoreBuckets[ScoreBucket.above90] =
            (_scoreBuckets[ScoreBucket.above90] ?? 0) + 1;
      }
    }

    // Best score gap
    final gap = telemetry.bestScoreGap;
    if (gap != null) {
      _sumBestScoreGaps += gap;
      _gapCount++;
    }
  }

  // ─── Computed metrics ─────────────────────────────────────────────

  /// Tổng số queries đã ghi nhận.
  int get totalQueries => _totalQueries;

  /// Tỉ lệ retrieval "normal" (thành công).
  double get retrievalSuccessRate =>
      _totalQueries > 0 ? _normalCount / _totalQueries : 0;

  /// Tỉ lệ weak retrieval.
  double get weakRetrievalPercent =>
      _totalQueries > 0 ? _weakCount / _totalQueries * 100 : 0;

  /// Tỉ lệ empty retrieval.
  double get emptyRetrievalPercent =>
      _totalQueries > 0 ? _emptyCount / _totalQueries * 100 : 0;

  /// Thời gian retrieval trung bình (ms).
  double get avgRetrievalTimeMs =>
      _totalQueries > 0 ? _totalRetrievalTimeMs / _totalQueries : 0;

  /// Thời gian retrieval max (ms).
  double get maxRetrievalTimeMs => _maxRetrievalTimeMs;

  /// Average best score (alias for readability).
  double get averageBestScore => avgBestScore;

  /// Average best score.
  double get avgBestScore =>
      _totalQueries > 0 ? _sumBestScores / _totalQueries : 0;

  /// Average gap between top-1 and top-2 scores.
  double get averageBestScoreGap =>
      _gapCount > 0 ? _sumBestScoreGaps / _gapCount : 0;

  /// Thời gian retrieval trung bình (ms) — alias for readability.
  double get averageLatencyMs => avgRetrievalTimeMs;

  /// Số chunk trim trung bình mỗi query.
  double get avgTrimmedChunks =>
      _totalQueries > 0 ? _totalTrimmedChunks / _totalQueries : 0;

  /// Số chunk returned trung bình mỗi query.
  double get avgReturnedChunks =>
      _totalQueries > 0 ? _totalReturnedChunks / _totalQueries : 0;

  /// Số chunk matched trung bình mỗi query.
  double get avgMatchedChunks =>
      _totalQueries > 0 ? _totalMatchedChunks / _totalQueries : 0;

  /// Score distribution histogram.
  Map<ScoreBucket, int> get scoreDistribution =>
      Map.unmodifiable(_scoreBuckets);

  /// Reset tất cả metrics.
  void reset() {
    _totalQueries = 0;
    _emptyCount = 0;
    _weakCount = 0;
    _normalCount = 0;
    _totalRetrievalTimeMs = 0;
    _totalTrimmedChunks = 0;
    _totalReturnedChunks = 0;
    _totalMatchedChunks = 0;
    _sumBestScores = 0;
    _sumBestScoreGaps = 0;
    _gapCount = 0;
    _maxRetrievalTimeMs = 0;
    for (final bucket in _scoreBuckets.keys) {
      _scoreBuckets[bucket] = 0;
    }
  }

  /// In health report.
  String toReportString() {
    if (_totalQueries == 0) return 'RAG Health Report: No data yet.';

    final buffer = StringBuffer();
    buffer.writeln('===== RAG Health Report ($_totalQueries queries) =====');
    buffer.writeln('Success Rate: ${(retrievalSuccessRate * 100).toStringAsFixed(1)}%');
    buffer.writeln('  normal: $_normalCount (${(1 - weakRetrievalPercent / 100 - emptyRetrievalPercent / 100).toStringAsFixed(1)}%)');
    buffer.writeln('  weak: $_weakCount (${weakRetrievalPercent.toStringAsFixed(1)}%)');
    buffer.writeln('  empty: $_emptyCount (${emptyRetrievalPercent.toStringAsFixed(1)}%)');
    buffer.writeln('');
    buffer.writeln('Avg Best Score: ${avgBestScore.toStringAsFixed(3)}');
    buffer.writeln('Avg Best Score Gap: ${averageBestScoreGap.toStringAsFixed(3)}');
    buffer.writeln('Avg Retrieval Time: ${avgRetrievalTimeMs.toStringAsFixed(0)}ms (max: ${maxRetrievalTimeMs.toStringAsFixed(0)}ms)');
    buffer.writeln('');
    buffer.writeln('Chunks: matched=${avgMatchedChunks.toStringAsFixed(1)} returned=${avgReturnedChunks.toStringAsFixed(1)} trimmed=${avgTrimmedChunks.toStringAsFixed(1)}');
    buffer.writeln('');
    buffer.writeln('Score Distribution:');
    for (final entry in _scoreBuckets.entries) {
      final pct = _totalQueries > 0
          ? (entry.value / _totalQueries * 100).toStringAsFixed(1)
          : '0.0';
      buffer.writeln('  ${_bucketLabel(entry.key)}: ${entry.value} ($pct%)');
    }
    buffer.writeln('==========================================');
    return buffer.toString();
  }

  String _bucketLabel(ScoreBucket bucket) {
    switch (bucket) {
      case ScoreBucket.below70:
        return '< 0.7';
      case ScoreBucket.between70And80:
        return '0.7 - 0.8';
      case ScoreBucket.between80And90:
        return '0.8 - 0.9';
      case ScoreBucket.above90:
        return '0.9 - 1.0';
    }
  }
}