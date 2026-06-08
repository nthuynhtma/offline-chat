# Database Schema (Drift/SQLite)

## Tổng quan

Dùng **drift** package (formerly moor) cho type-safe SQLite trên cả Android và iOS.

```
pubspec.yaml dependencies:
  drift: ^2.x
  sqlite3_flutter_libs: ^0.x
  path_provider: ^2.x
  path: ^1.x

dev_dependencies:
  drift_dev: ^2.x
  build_runner: ^2.x
```

---

## Tables Definition

### `database/tables/sessions_table.dart`
```dart
import 'package:drift/drift.dart';

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### `database/tables/messages_table.dart`
```dart
import 'package:drift/drift.dart';

enum MessageRole { user, assistant, system }

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get role => textEnum<MessageRole>()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### `database/tables/documents_table.dart`
```dart
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
```

### `database/tables/chunks_table.dart`
```dart
import 'package:drift/drift.dart';

class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get chunkText => text()();
  IntColumn get chunkIndex => integer()();
  IntColumn get tokenCount => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### `database/tables/vectors_table.dart`
```dart
import 'package:drift/drift.dart';

class Vectors extends Table {
  TextColumn get id => text()();
  TextColumn get chunkId => text().references(Chunks, #id, onDelete: KeyAction.cascade)();
  BlobColumn get embedding => blob()(); // Float32List serialized as Uint8List
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## App Database

### `database/app_database.dart`
```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Sessions, Messages, Documents, Chunks, Vectors],
  daos: [SessionsDao, MessagesDao, DocumentsDao, ChunksDao, VectorsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Create indexes
      await customStatement(
        'CREATE INDEX idx_messages_session ON messages(session_id, created_at)',
      );
      await customStatement(
        'CREATE INDEX idx_chunks_document ON chunks(document_id)',
      );
      await customStatement(
        'CREATE INDEX idx_vectors_chunk ON vectors(chunk_id)',
      );
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'offline_chat.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

---

## DAOs

### `database/daos/sessions_dao.dart`
```dart
import 'package:drift/drift.dart';
import '../app_database.dart';

part 'sessions_dao.g.dart';

@DriftAccessor(tables: [Sessions])
class SessionsDao extends DatabaseAccessor<AppDatabase> with _$SessionsDaoMixin {
  SessionsDao(super.db);

  Future<List<Session>> getAllSessions() =>
      (select(sessions)..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])).get();

  Stream<List<Session>> watchAllSessions() =>
      (select(sessions)..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])).watch();

  Future<Session?> getSessionById(String id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> insertSession(SessionsCompanion session) =>
      into(sessions).insert(session);

  Future<void> updateSession(SessionsCompanion session) =>
      (update(sessions)..where((s) => s.id.equals(session.id.value)))
          .write(session);

  Future<void> deleteSession(String id) =>
      (delete(sessions)..where((s) => s.id.equals(id))).go();
}
```

### `database/daos/messages_dao.dart`
```dart
import 'package:drift/drift.dart';
import '../app_database.dart';

part 'messages_dao.g.dart';

@DriftAccessor(tables: [Messages])
class MessagesDao extends DatabaseAccessor<AppDatabase> with _$MessagesDaoMixin {
  MessagesDao(super.db);

  Future<List<Message>> getMessagesBySession(String sessionId) =>
      (select(messages)
        ..where((m) => m.sessionId.equals(sessionId))
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();

  /// Lấy N messages gần nhất của session (cho context window)
  Future<List<Message>> getRecentMessages(String sessionId, {int limit = 20}) =>
      (select(messages)
        ..where((m) => m.sessionId.equals(sessionId))
        ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
        ..limit(limit))
          .get()
          .then((list) => list.reversed.toList());

  Stream<List<Message>> watchMessagesBySession(String sessionId) =>
      (select(messages)
        ..where((m) => m.sessionId.equals(sessionId))
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .watch();

  Future<void> insertMessage(MessagesCompanion message) =>
      into(messages).insert(message);

  Future<void> deleteMessagesBySession(String sessionId) =>
      (delete(messages)..where((m) => m.sessionId.equals(sessionId))).go();
}
```

### `database/daos/documents_dao.dart`
```dart
import 'package:drift/drift.dart';
import '../app_database.dart';

part 'documents_dao.g.dart';

@DriftAccessor(tables: [Documents])
class DocumentsDao extends DatabaseAccessor<AppDatabase> with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  Future<List<Document>> getAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).get();

  Stream<List<Document>> watchAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).watch();

  Future<void> insertDocument(DocumentsCompanion doc) =>
      into(documents).insert(doc);

  Future<void> updateChunkCount(String docId, int count) =>
      (update(documents)..where((d) => d.id.equals(docId)))
          .write(DocumentsCompanion(chunkCount: Value(count)));

  Future<void> deleteDocument(String id) =>
      (delete(documents)..where((d) => d.id.equals(id))).go();
}
```

### `database/daos/chunks_dao.dart`
```dart
import 'package:drift/drift.dart';
import '../app_database.dart';

part 'chunks_dao.g.dart';

@DriftAccessor(tables: [Chunks])
class ChunksDao extends DatabaseAccessor<AppDatabase> with _$ChunksDaoMixin {
  ChunksDao(super.db);

  Future<List<Chunk>> getChunksByDocument(String documentId) =>
      (select(chunks)
        ..where((c) => c.documentId.equals(documentId))
        ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)]))
          .get();

  Future<List<Chunk>> getChunksByIds(List<String> ids) =>
      (select(chunks)..where((c) => c.id.isIn(ids))).get();

  Future<void> insertChunks(List<ChunksCompanion> chunkList) =>
      batch((b) => b.insertAll(chunks, chunkList));

  Future<void> deleteChunksByDocument(String documentId) =>
      (delete(chunks)..where((c) => c.documentId.equals(documentId))).go();
}
```

### `database/daos/vectors_dao.dart`
```dart
import 'package:drift/drift.dart';
import '../app_database.dart';

part 'vectors_dao.g.dart';

@DriftAccessor(tables: [Vectors])
class VectorsDao extends DatabaseAccessor<AppDatabase> with _$VectorsDaoMixin {
  VectorsDao(super.db);

  /// Lấy tất cả vectors (dùng cho brute-force search)
  Future<List<Vector>> getAllVectors() => select(vectors).get();

  Future<void> insertVectors(List<VectorsCompanion> vectorList) =>
      batch((b) => b.insertAll(vectors, vectorList));

  Future<void> deleteVectorsByChunkIds(List<String> chunkIds) =>
      (delete(vectors)..where((v) => v.chunkId.isIn(chunkIds))).go();

  Future<int> countVectors() =>
      vectors.count().getSingle();
}
```

---

## Serialization Helpers

### `core/utils/embedding_serializer.dart`
```dart
import 'dart:typed_data';

class EmbeddingSerializer {
  /// Float32List → Uint8List để lưu vào SQLite BLOB
  static Uint8List serialize(List<double> embedding) {
    final float32 = Float32List.fromList(embedding);
    return float32.buffer.asUint8List();
  }

  /// Uint8List → List<double> khi đọc từ SQLite
  static List<double> deserialize(Uint8List bytes) {
    return Float32List.view(bytes.buffer).toList();
  }
}
```

---

## Migrations (khi nâng schema version)

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async { await m.createAll(); },
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      // Ví dụ: thêm cột tags vào documents
      await m.addColumn(documents, documents.tags);
    }
  },
);
```
