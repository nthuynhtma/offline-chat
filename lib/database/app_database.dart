import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'tables/sessions_table.dart';
import 'tables/messages_table.dart';
import 'tables/documents_table.dart';
import 'tables/chunks_table.dart';
import 'tables/vectors_table.dart';

part 'app_database.g.dart';
part 'daos/sessions_dao.dart';
part 'daos/messages_dao.dart';
part 'daos/documents_dao.dart';
part 'daos/chunks_dao.dart';
part 'daos/vectors_dao.dart';

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