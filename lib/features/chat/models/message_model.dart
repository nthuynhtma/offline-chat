import 'package:offline_chat/database/tables/messages_table.dart';

class MessageModel {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory MessageModel.fromDbRow(dynamic row) => MessageModel(
        id: row.id,
        sessionId: row.sessionId,
        role: row.role,
        content: row.content,
        createdAt: row.createdAt,
      );

  MessageModel copyWith({String? content}) => MessageModel(
        id: id,
        sessionId: sessionId,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
      );
}