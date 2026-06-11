import 'package:offline_chat/core/constants/document_constants.dart';

class SessionModel {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final KnowledgeScope knowledgeScope;

  const SessionModel({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.knowledgeScope = KnowledgeScope.globalAndSession,
  });

  factory SessionModel.fromDbRow(dynamic row) => SessionModel(
        id: row.id,
        title: row.title,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        knowledgeScope: KnowledgeScopeX.fromInt(row.knowledgeScope),
      );

  SessionModel copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    KnowledgeScope? knowledgeScope,
  }) =>
      SessionModel(
        id: id ?? this.id,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        knowledgeScope: knowledgeScope ?? this.knowledgeScope,
      );
}