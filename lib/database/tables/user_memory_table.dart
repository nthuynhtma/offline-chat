import 'package:drift/drift.dart';

class UserMemory extends Table {
  TextColumn get namespace => text()();
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {namespace, key};
}