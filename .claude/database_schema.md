# Database Schema (Drift/SQLite)

## Tổng quan

Dùng **drift** package cho type-safe SQLite.

```yaml
dependencies:
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.x
  path_provider: ^2.x
  path: ^1.x
dev_dependencies:
  drift_dev: ^2.18.0
  build_runner: ^2.x
```

---

## Tables

### sessions_table.dart
```dart
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// KnowledgeScope: 0=attachedOnly, 1=globalOnly, 2=attachedAndGlobal (default)
  IntColumn get knowledgeScope => integer().withDefault(const Constant(2))();

  @override
  Set<Column> get primaryKey => {id};
}
```

### messages_table.dart
```dart
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

### documents_table.dart
```dart
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

  /// IndexStatus: 0=pending, 1=processing, 2=completed, 3=failed
  IntColumn get status => integer().withDefault(const Constant(0))();

  /// Progress 0.0→1.0 trong pipeline indexing
  RealColumn get progress => real().withDefault(const Constant(0.0))();

  /// Thông báo lỗi nếu status=failed
  TextColumn get errorMessage => text().nullable()();

  /// Số lần retry indexing
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Thời gian xử lý lần cuối
  DateTimeColumn get lastProcessedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### chunks_table.dart
```dart
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
```

### vectors_table.dart
```dart
class Vectors extends Table {
  TextColumn get id => text()();
  TextColumn get chunkId =>
      text().references(Chunks, #id, onDelete: KeyAction.cascade)();
  BlobColumn get embedding => blob()(); // Float32List serialized

  @override
  Set<Column> get primaryKey => {id};
}
```

### session_document_refs_table.dart (junction table)
```dart
class SessionDocumentRefs extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get attachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, documentId};
}
```

### session_memory_table.dart
```dart
class SessionMemory extends Table {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get summary => text()();
  IntColumn get summaryVersion => integer()();
  IntColumn get msgCount => integer()();
  IntColumn get estTokens => integer()();
  IntColumn get runningTokenCount => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId};
}
```

### user_memory_table.dart
```dart
class UserMemory extends Table {
  TextColumn get namespace => text()();
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {namespace, key};
}
```

---

## AppDatabase

```dart
@DriftDatabase(
  tables: [
    Sessions,
    Messages,
    Documents,
    SessionDocumentRefs,
    Chunks,
    Vectors,
    SessionMemory,
    UserMemory,
  ],
  daos: [
    SessionsDao,
    MessagesDao,
    DocumentsDao,
    SessionDocumentRefsDao,
    ChunksDao,
    VectorsDao,
    SessionMemoryDao,
    UserMemoryDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Indexes
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
```

---

## DAOs

### DocumentsDao — Queries quan trọng
```dart
// Filter documents by status + scope (dùng cho RAG)
Future<Set<String>> getCompletedDocumentIdsBySessionId(String sessionId);
Future<Set<String>> getCompletedDocumentIdsByIds(Set<String> ids);
Future<Set<String>> getCompletedGlobalDocumentIds();
Future<List<Document>> getDocumentsByRetryNeeded();

// Update pipeline
updateDocumentStatus(id, status, {error})
updateDocumentProgress(id, step, total)
updateChunkCount(id, count)
incrementRetryCount(id) / resetRetryCount(id)
```

### ChunksDao
```dart
Future<List<Chunk>> getChunksByDocument(String documentId);
Future<List<Chunk>> getChunksByIds(List<String> ids);
Future<Set<String>> getChunkIdsByDocumentIds(Set<String> documentIds);
Future<void> insertChunks(List<ChunksCompanion> chunkList);
```

### VectorsDao
```dart
Future<List<Vector>> getAllVectors();     // brute-force search
Future<void> insertVectors(List<VectorsCompanion> vectorList);
Future<void> deleteVectorsByChunkIds(List<String> chunkIds);
Future<int> countVectors();
```

---

## Serialization

```dart
// lib/core/utils/embedding_serializer.dart
class EmbeddingSerializer {
  static Uint8List serialize(List<double> embedding) {
    return Float32List.fromList(embedding).buffer.asUint8List();
  }
  static List<double> deserialize(Uint8List bytes) {
    return Float32List.view(bytes.buffer).toList();
  }
}