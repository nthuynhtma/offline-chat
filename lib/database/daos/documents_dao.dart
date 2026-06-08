part of '../app_database.dart';

@DriftAccessor(tables: [Documents])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  Future<List<Document>> getAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .get();

  Stream<List<Document>> watchAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .watch();

  Future<void> insertDocument(DocumentsCompanion doc) =>
      into(documents).insert(doc);

  Future<void> updateChunkCount(String docId, int count) =>
      (update(documents)..where((d) => d.id.equals(docId)))
          .write(DocumentsCompanion(chunkCount: Value(count)));

  Future<void> deleteDocument(String id) =>
      (delete(documents)..where((d) => d.id.equals(id))).go();
}