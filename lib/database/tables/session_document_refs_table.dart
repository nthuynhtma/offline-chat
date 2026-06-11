import 'package:drift/drift.dart';
import 'documents_table.dart';
import 'sessions_table.dart';

/// Junction table referencing global KB documents into a session.
/// A document may appear in its own session via Documents.sessionId,
/// OR be referenced here for shared/global documents.
class SessionDocumentRefs extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get attachedAt => dateTime()();

  IntColumn get displayOrder => integer()();

  @override
  Set<Column> get primaryKey => {sessionId, documentId};
}