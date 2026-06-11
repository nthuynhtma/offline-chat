part of '../app_database.dart';

@DriftAccessor(tables: [Documents])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  // ─── Queries ────────────────────────────────────────────────────────────

  Future<List<Document>> getAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .get();

  Stream<List<Document>> watchAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .watch();

  /// Lấy documents theo sessionId. null = global documents.
  Future<List<Document>> getDocumentsBySessionId(String? sessionId) {
    return (select(documents)
          ..where((d) => sessionId != null
              ? d.sessionId.equals(sessionId)
              : d.sessionId.isNull())
          ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
        .get();
  }

  /// Lấy document IDs phù hợp với KnowledgeScope để filter vector search.
  Future<Set<String>> getDocumentIdsByScope({
    required KnowledgeScope scope,
    String? sessionId,
  }) async {
    final docs = await (select(documents)
          ..where((d) {
            final condition = switch (scope) {
              KnowledgeScope.globalOnly => d.sessionId.isNull(),
              KnowledgeScope.attachedOnly => d.sessionId.equals(sessionId ?? ''),
              KnowledgeScope.attachedAndGlobal => d.sessionId.isNull() |
                  d.sessionId.equals(sessionId ?? ''),
            };
            return condition;
          })
          ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
        .get();
    return docs.map((d) => d.id).toSet();
  }

  /// Lấy document theo id
  Future<Document?> getDocumentById(String id) =>
      (select(documents)..where((d) => d.id.equals(id))).getSingleOrNull();

  // ─── Mutations ──────────────────────────────────────────────────────────

  Future<void> insertDocument(DocumentsCompanion doc) =>
      into(documents).insert(doc);

  Future<void> updateChunkCount(String docId, int count) =>
      (update(documents)..where((d) => d.id.equals(docId)))
          .write(DocumentsCompanion(chunkCount: Value(count)));

  /// Update progress theo step/totalSteps (atomic, tránh race condition).
  Future<void> updateDocumentProgress(
      String docId, int step, int totalSteps) async {
    final progress = totalSteps > 0 ? step / totalSteps : 0.0;
    await (update(documents)..where((d) => d.id.equals(docId)))
        .write(DocumentsCompanion(progress: Value(progress)));
  }

  /// Update status + optional error message.
  Future<void> updateDocumentStatus(
    String docId,
    IndexStatus status, {
    String? error,
  }) async {
    await (update(documents)..where((d) => d.id.equals(docId)))
        .write(DocumentsCompanion(
      status: Value(status.toInt),
      errorMessage: Value(error),
    ));
  }

  /// Xoá document + cascade chunks (ON DELETE CASCADE trong DB).
  Future<void> deleteDocument(String id) =>
      (delete(documents)..where((d) => d.id.equals(id))).go();

  /// Xoá tất cả documents của một session + cascade chunks.
  Future<void> deleteBySessionId(String sessionId) =>
      (delete(documents)..where((d) => d.sessionId.equals(sessionId))).go();

  // ─── Retry & Progress ─────────────────────────────────────────────────────

  /// Lấy documents có status=failed và retryCount < maxRetries.
  Future<List<Document>> getDocumentsByRetryNeeded(int maxRetries) async {
    return (select(documents)
          ..where((d) =>
              d.status.equals(IndexStatus.failed.toInt) &
               d.retryCount.isSmallerThan(Variable(maxRetries)))
          ..orderBy([(d) => OrderingTerm.desc(d.lastProcessedAt)]))
        .get();
  }

  /// Tăng retryCount cho document.
  Future<void> incrementRetryCount(String docId) async {
    final doc = await getDocumentById(docId);
    if (doc == null) return;
    await (update(documents)..where((d) => d.id.equals(docId)))
        .write(DocumentsCompanion(
      retryCount: Value(doc.retryCount + 1),
    ));
  }

  /// Reset retryCount về 0 (khi indexing thành công).
  Future<void> resetRetryCount(String docId) async {
    await (update(documents)..where((d) => d.id.equals(docId)))
        .write(DocumentsCompanion(
      retryCount: const Value(0),
      lastProcessedAt: Value(DateTime.now()),
    ));
  }

  /// Update lastProcessedAt (dùng để tracking lần xử lý cuối).
  Future<void> updateLastProcessedAt(String docId) async {
    await (update(documents)..where((d) => d.id.equals(docId)))
        .write(DocumentsCompanion(
      lastProcessedAt: Value(DateTime.now()),
    ));
  }
}
