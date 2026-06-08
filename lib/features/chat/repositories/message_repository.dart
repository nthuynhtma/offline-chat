import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';

abstract interface class MessageRepository {
  Future<List<MessageModel>> getMessages(String sessionId);
  Future<List<MessageModel>> getRecentMessages(String sessionId,
      {int limit = 20});
  Stream<List<MessageModel>> watchMessages(String sessionId);
  Future<MessageModel> saveMessage({
    required String sessionId,
    required MessageRole role,
    required String content,
  });
  Future<void> deleteMessagesBySession(String sessionId);
}

class MessageRepositoryImpl implements MessageRepository {
  final MessagesDao _dao;
  final Uuid _uuid = const Uuid();

  MessageRepositoryImpl(this._dao);

  @override
  Future<List<MessageModel>> getMessages(String sessionId) async {
    final rows = await _dao.getMessagesBySession(sessionId);
    return rows.map(MessageModel.fromDbRow).toList();
  }

  @override
  Future<List<MessageModel>> getRecentMessages(String sessionId,
      {int limit = 20}) async {
    final rows = await _dao.getRecentMessages(sessionId, limit: limit);
    return rows.map(MessageModel.fromDbRow).toList();
  }

  @override
  Stream<List<MessageModel>> watchMessages(String sessionId) =>
      _dao.watchMessagesBySession(sessionId).map(
            (rows) => rows.map(MessageModel.fromDbRow).toList(),
          );

  @override
  Future<MessageModel> saveMessage({
    required String sessionId,
    required MessageRole role,
    required String content,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    await _dao.insertMessage(MessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      createdAt: Value(now),
    ));
    return MessageModel(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content,
      createdAt: now,
    );
  }

  @override
  Future<void> deleteMessagesBySession(String sessionId) async {
    await _dao.deleteMessagesBySession(sessionId);
  }
}