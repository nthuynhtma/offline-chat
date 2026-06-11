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
///
/// DB values are stable:
///   0 = attachedOnly,  1 = globalOnly,  2 = attachedAndGlobal
enum KnowledgeScope {
  /// Chỉ dùng tài liệu đã attach (session docs + referenced global docs)
  attachedOnly,

  /// Chỉ dùng Global KB
  globalOnly,

  /// Dùng cả tài liệu attach + toàn bộ Global KB
  attachedAndGlobal,
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
    // Values: 0=attachedOnly, 1=globalOnly, 2=attachedAndGlobal
    return KnowledgeScope.values[
        value.clamp(0, KnowledgeScope.values.length - 1)];
  }
}

/// Số bước trong pipeline indexing (parse → chunk → embed).
const int kIndexingTotalSteps = 3;