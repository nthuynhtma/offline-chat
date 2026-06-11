import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/features/session/models/session_model.dart';

abstract interface class SessionRepository {
  Future<List<SessionModel>> getAllSessions();
  Stream<List<SessionModel>> watchAllSessions();
  Future<SessionModel?> getSessionById(String id);
  Future<SessionModel> createSession({String? title});
  Future<void> updateSessionTitle(String id, String title);
  Future<void> deleteSession(String id);
  Future<void> updateSessionTimestamp(String id);
  Future<void> updateKnowledgeScope(String id, KnowledgeScope scope);
}

class SessionRepositoryImpl implements SessionRepository {
  final SessionsDao _dao;
  final Uuid _uuid = const Uuid();

  SessionRepositoryImpl(this._dao);

  @override
  Future<List<SessionModel>> getAllSessions() async {
    final rows = await _dao.getAllSessions();
    return rows.map(SessionModel.fromDbRow).toList();
  }

  @override
  Stream<List<SessionModel>> watchAllSessions() =>
      _dao.watchAllSessions().map(
            (rows) => rows.map(SessionModel.fromDbRow).toList(),
          );

  @override
  Future<SessionModel?> getSessionById(String id) async {
    final row = await _dao.getSessionById(id);
    return row != null ? SessionModel.fromDbRow(row) : null;
  }

  @override
  Future<SessionModel> createSession({String? title}) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final sessionTitle = title ?? 'New Chat';
    await _dao.insertSession(SessionsCompanion(
      id: Value(id),
      title: Value(sessionTitle),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return SessionModel(
      id: id,
      title: sessionTitle,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> updateSessionTitle(String id, String title) async {
    await _dao.updateSession(SessionsCompanion(
      id: Value(id),
      title: Value(title),
      updatedAt: Value(DateTime.now()),
    ));
  }

  @override
  Future<void> deleteSession(String id) async {
    await _dao.deleteSession(id);
  }

  @override
  Future<void> updateSessionTimestamp(String id) async {
    await _dao.updateSession(SessionsCompanion(
      id: Value(id),
      updatedAt: Value(DateTime.now()),
    ));
  }

  @override
  Future<void> updateKnowledgeScope(String id, KnowledgeScope scope) async {
    await _dao.updateSession(SessionsCompanion(
      id: Value(id),
      knowledgeScope: Value(scope.toInt),
      updatedAt: Value(DateTime.now()),
    ));
  }
}
