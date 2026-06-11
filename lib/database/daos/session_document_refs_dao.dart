part of '../app_database.dart';

@DriftAccessor(tables: [SessionDocumentRefs])
class SessionDocumentRefsDao extends DatabaseAccessor<AppDatabase>
    with _$SessionDocumentRefsDaoMixin {
  SessionDocumentRefsDao(super.db);

  /// Lấy tất cả document IDs được attach vào session.
  Future<Set<String>> getDocumentIdsBySession(String sessionId) async {
    final rows = await (select(sessionDocumentRefs)
          ..where((r) => r.sessionId.equals(sessionId))
          ..orderBy([(r) => OrderingTerm.asc(r.displayOrder)]))
        .get();
    return rows.map((r) => r.documentId).toSet();
  }

  /// Kiểm tra document có được attach vào session không.
  Future<bool> isDocumentAttached(String sessionId, String documentId) async {
    final row = await (select(sessionDocumentRefs)
          ..where((r) =>
              r.sessionId.equals(sessionId) &
              r.documentId.equals(documentId)))
        .getSingleOrNull();
    return row != null;
  }

  /// Attach một document vào session (nếu chưa có).
  Future<void> attachDocument(String sessionId, String documentId) async {
    final exists = await isDocumentAttached(sessionId, documentId);
    if (exists) return;

    // Tính displayOrder tiếp theo
    final maxOrder = await (select(sessionDocumentRefs)
          ..where((r) => r.sessionId.equals(sessionId))
          ..orderBy([(r) => OrderingTerm.desc(r.displayOrder)])
          ..limit(1))
        .getSingleOrNull();

    final nextOrder = (maxOrder?.displayOrder ?? -1) + 1;

    await into(sessionDocumentRefs).insert(SessionDocumentRefsCompanion(
      sessionId: Value(sessionId),
      documentId: Value(documentId),
      attachedAt: Value(DateTime.now()),
      displayOrder: Value(nextOrder),
    ));
  }

  /// Detach một document khỏi session.
  Future<void> detachDocument(String sessionId, String documentId) async {
    await (delete(sessionDocumentRefs)
          ..where((r) =>
              r.sessionId.equals(sessionId) &
              r.documentId.equals(documentId)))
        .go();
  }

  /// Detach tất cả documents khỏi session (khi xoá session).
  Future<void> detachAllBySession(String sessionId) async {
    await (delete(sessionDocumentRefs)
          ..where((r) => r.sessionId.equals(sessionId)))
        .go();
  }

  /// Xoá tất cả refs trỏ đến một document (khi xoá document).
  Future<void> detachAllByDocument(String documentId) async {
    await (delete(sessionDocumentRefs)
          ..where((r) => r.documentId.equals(documentId)))
        .go();
  }

  /// Đếm số documents đã attach trong session.
  Future<int> countBySession(String sessionId) async {
    return (select(sessionDocumentRefs)
          ..where((r) => r.sessionId.equals(sessionId)))
        .map((r) => r.documentId)
        .get()
        .then((rows) => rows.length);
  }

  /// Stream watch các document IDs được attach trong session.
  Stream<Set<String>> watchDocumentIdsBySession(String sessionId) {
    return (select(sessionDocumentRefs)
          ..where((r) => r.sessionId.equals(sessionId))
          ..orderBy([(r) => OrderingTerm.asc(r.displayOrder)]))
        .watch()
        .map((rows) => rows.map((r) => r.documentId).toSet());
  }
}