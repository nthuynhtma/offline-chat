import 'package:drift/drift.dart';
import 'documents_table.dart';

class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get chunkText => text()();
  IntColumn get chunkIndex => integer()();
  IntColumn get tokenCount => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}