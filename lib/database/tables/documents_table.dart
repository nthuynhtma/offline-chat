import 'package:drift/drift.dart';
import 'sessions_table.dart';

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get path => text()();
  IntColumn get sizeBytes => integer()();
  IntColumn get chunkCount => integer().withDefault(const Constant(0))();
  TextColumn get mimeType => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// null = Global KB, non-null = Session-specific document
  TextColumn get sessionId =>
      text().nullable().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// IndexStatus enum: 0=pending, 1=processing, 2=completed, 3=failed
  IntColumn get status => integer().withDefault(const Constant(0))();

  /// Progress 0.0 → 1.0 trong pipeline indexing
  RealColumn get progress => real().withDefault(const Constant(0.0))();

  /// Thông báo lỗi nếu status=failed
  TextColumn get errorMessage => text().nullable()();

  /// Số lần retry indexing (reset khi indexing thành công)
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Thời gian xử lý lần cuối (null nếu chưa từng xử lý)
  DateTimeColumn get lastProcessedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
