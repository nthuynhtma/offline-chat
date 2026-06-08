part of '../app_database.dart';

@DriftAccessor(tables: [Messages])
class MessagesDao extends DatabaseAccessor<AppDatabase> with _$MessagesDaoMixin {
  MessagesDao(super.db);

  Future<List<Message>> getMessagesBySession(String sessionId) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();

  Future<List<Message>> getRecentMessages(String sessionId, {int limit = 20}) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
            ..limit(limit))
          .get()
          .then((list) => list.reversed.toList());

  Stream<List<Message>> watchMessagesBySession(String sessionId) =>
      (select(messages)
            ..where((m) => m.sessionId.equals(sessionId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .watch();

  Future<void> insertMessage(MessagesCompanion message) =>
      into(messages).insert(message);

  Future<void> deleteMessagesBySession(String sessionId) =>
      (delete(messages)..where((m) => m.sessionId.equals(sessionId))).go();
}