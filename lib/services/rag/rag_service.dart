import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/services/rag/rag_context.dart';

/// Service chịu trách nhiệm retrieval cho RAG pipeline.
///
/// ChatBloc chỉ gọi [retrieve] và nhận [RagContext] — không biết
/// topK, threshold, embedding hay chunk trimming bên trong.
abstract interface class RagService {
  /// Retrieve các chunks liên quan đến [query] trong [tokenBudget] cho phép.
  ///
  /// [tokenBudget] được tính từ context window và các budget khác.
  /// RagService tự động trim chunks để vừa budget (chunk-level, không substring).
  ///
  /// [scope] — phạm vi knowledge để search.
  /// [sessionId] — session hiện tại (null nếu globalOnly).
  Future<RagContext> retrieve({
    required String query,
    required int tokenBudget,
    required KnowledgeScope scope,
    String? sessionId,
  });
}
