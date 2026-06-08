import 'package:drift/drift.dart';
import 'chunks_table.dart';

class Vectors extends Table {
  TextColumn get id => text()();
  TextColumn get chunkId =>
      text().references(Chunks, #id, onDelete: KeyAction.cascade)();
  BlobColumn get embedding => blob()(); // Float32List serialized as Uint8List
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}