import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'package:offline_chat/core/constants/document_constants.dart';
import 'tables/sessions_table.dart';
import 'tables/messages_table.dart';
import 'tables/documents_table.dart';
import 'tables/chunks_table.dart';
import 'tables/vectors_table.dart';
import 'tables/session_memory_table.dart';
import 'tables/user_memory_table.dart';
import 'tables/session_document_refs_table.dart';

part 'app_database.g.dart';
part 'daos/sessions_dao.dart';
part 'daos/messages_dao.dart';
part 'daos/documents_dao.dart';
part 'daos/chunks_dao.dart';
part 'daos/vectors_dao.dart';
part 'daos/session_memory_dao.dart';
part 'daos/user_memory_dao.dart';
part 'daos/session_document_refs_dao.dart';

@DriftDatabase(
  tables: [
    Sessions,
    Messages,
    Documents,
    Chunks,
    Vectors,
    SessionMemory,
    UserMemory,
    SessionDocumentRefs,
  ],
  daos: [
    SessionsDao,
    MessagesDao,
    DocumentsDao,
    ChunksDao,
    VectorsDao,
    SessionMemoryDao,
    UserMemoryDao,
    SessionDocumentRefsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [queryExecutor] có thể được cung cấp để test (in-memory database)
  AppDatabase({QueryExecutor? queryExecutor})
      : super(queryExecutor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX idx_messages_session ON messages(session_id, created_at)',
          );
          await customStatement(
            'CREATE INDEX idx_chunks_document ON chunks(document_id)',
          );
          await customStatement(
            'CREATE INDEX idx_vectors_chunk ON vectors(chunk_id)',
          );
          await customStatement(
            'CREATE INDEX idx_documents_session ON documents(session_id)',
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(sessionMemory);
            await m.createTable(userMemory);
          }
          if (from < 3) {
            // Thêm columns cho documents table (dùng ALTER TABLE vì nullable columns)
            await customStatement(
              'ALTER TABLE documents ADD COLUMN session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE',
            );
            await customStatement(
              'ALTER TABLE documents ADD COLUMN status INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE documents ADD COLUMN progress REAL NOT NULL DEFAULT 0.0',
            );
            await customStatement(
              'ALTER TABLE documents ADD COLUMN error_message TEXT',
            );
            // Thêm knowledgeScope cho sessions table
            await customStatement(
              'ALTER TABLE sessions ADD COLUMN knowledge_scope INTEGER NOT NULL DEFAULT 2',
            );
            // Index
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_documents_session ON documents(session_id)',
            );
          }
          if (from < 4) {
            // Tạo junction table session_document_refs
            await m.createTable(sessionDocumentRefs);
            // Thêm retry_count và last_processed_at cho documents
            await customStatement(
              'ALTER TABLE documents ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE documents ADD COLUMN last_processed_at TEXT',
            );
          }
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