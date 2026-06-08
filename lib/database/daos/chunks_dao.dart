part of '../app_database.dart';

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