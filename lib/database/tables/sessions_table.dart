import 'package:drift/drift.dart';

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// KnowledgeScope enum: 0=sessionOnly, 1=globalOnly, 2=globalAndSession (default)
  IntColumn get knowledgeScope => integer().withDefault(const Constant(2))();

  @override
  Set<Column> get primaryKey => {id};
}
