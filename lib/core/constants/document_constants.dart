/// Phạm vi của document trong knowledge base.
enum DocumentScope {
  /// Global KB — document dùng chung cho mọi session
  global,

  /// Session-specific — document chỉ dùng trong session đó
  session,
}

/// Trạng thái indexing của document.
enum IndexStatus {
  /// Chờ xử lý
  pending,

  /// Đang parse/chunk/embed
  processing,

  /// Hoàn tất, sẵn sàng cho RAG
  completed,

  /// Lỗi trong quá trình xử lý
  failed,
}

/// Phạm vi RAG retrieval cho một session.
///
/// Lưu trong [sessions.knowledgeScope] để persist theo conversation.
enum KnowledgeScope {
  /// Chỉ dùng file đã upload trong session này
  sessionOnly,

  /// Chỉ dùng Global KB
  globalOnly,

  /// Dùng cả Global KB + Session files
  globalAndSession,
}

// ─── Helpers ────────────────────────────────────────────────────────────────

extension IndexStatusX on IndexStatus {
  int get toInt => index;

  static IndexStatus fromInt(int value) {
    return IndexStatus.values[value.clamp(0, IndexStatus.values.length - 1)];
  }
}

extension KnowledgeScopeX on KnowledgeScope {
  int get toInt => index;

  static KnowledgeScope fromInt(int value) {
    return KnowledgeScope.values[
        value.clamp(0, KnowledgeScope.values.length - 1)];
  }
}

/// Số bước trong pipeline indexing (parse → chunk → embed).
const int kIndexingTotalSteps = 3;