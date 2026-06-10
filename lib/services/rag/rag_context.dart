import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Kết quả retrieval từ RAG pipeline.
///
/// Không chứa derived state (hasContext được tính từ chunks.isNotEmpty).
class RagContext {
  /// Danh sách chunks liên quan, đã trim theo token budget.
  final List<SearchResult> chunks;

  /// Tổng số token của tất cả chunks.
  final int tokenCount;

  /// Best similarity score cao nhất (null nếu không có chunks).
  final double? bestScore;

  const RagContext({
    required this.chunks,
    required this.tokenCount,
    this.bestScore,
  });

  /// Có context hay không (derived state).
  bool get hasContext => chunks.isNotEmpty;
}