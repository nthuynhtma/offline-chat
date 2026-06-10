part of '../app_database.dart';

@DriftAccessor(tables: [SessionMemory])
class SessionMemoryDao extends DatabaseAccessor<AppDatabase>
    with _$SessionMemoryDaoMixin {
  SessionMemoryDao(super.db);

  Future<SessionMemoryData?> getBySessionId(String sessionId) =>
      (select(sessionMemory)
            ..where((t) => t.sessionId.equals(sessionId)))
          .getSingleOrNull();

  Future<void> upsert(SessionMemoryCompanion data) =>
      into(sessionMemory).insertOnConflictUpdate(data);

  Future<void> deleteBySessionId(String sessionId) =>
      (delete(sessionMemory)..where((t) => t.sessionId.equals(sessionId)))
          .go();

  Future<void> updateRunningTokenCount(
    String sessionId,
    int newCount,
  ) async {
    final row = await getBySessionId(sessionId);
    if (row != null) {
      await update(sessionMemory).replace(
        row.copyWith(
          runningTokenCount: newCount,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }
}