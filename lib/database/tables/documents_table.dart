import 'package:drift/drift.dart';

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get path => text()();
  IntColumn get sizeBytes => integer()();
  IntColumn get chunkCount => integer().withDefault(const Constant(0))();
  TextColumn get mimeType => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}