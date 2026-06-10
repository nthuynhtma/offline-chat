import 'package:drift/drift.dart';
import 'sessions_table.dart';

class SessionMemory extends Table {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get summary => text().nullable()();
  IntColumn get summaryVersion => integer().withDefault(const Constant(0))();
  IntColumn get msgCount => integer().withDefault(const Constant(0))();
  IntColumn get estTokens => integer().withDefault(const Constant(0))();
  IntColumn get runningTokenCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId};
}