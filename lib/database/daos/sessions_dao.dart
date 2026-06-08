part of '../app_database.dart';

@DriftAccessor(tables: [Sessions])
class SessionsDao extends DatabaseAccessor<AppDatabase> with _$SessionsDaoMixin {
  SessionsDao(super.db);

  Future<List<Session>> getAllSessions() =>
      (select(sessions)..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])).get();

  Stream<List<Session>> watchAllSessions() =>
      (select(sessions)..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])).watch();

  Future<Session?> getSessionById(String id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> insertSession(SessionsCompanion session) =>
      into(sessions).insert(session);

  Future<void> updateSession(SessionsCompanion session) =>
      (update(sessions)..where((s) => s.id.equals(session.id.value)))
          .write(session);

  Future<void> deleteSession(String id) =>
      (delete(sessions)..where((s) => s.id.equals(id))).go();
}