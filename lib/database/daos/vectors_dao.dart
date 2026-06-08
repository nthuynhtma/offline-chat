part of '../app_database.dart';

@DriftAccessor(tables: [Vectors])
class VectorsDao extends DatabaseAccessor<AppDatabase> with _$VectorsDaoMixin {
  VectorsDao(super.db);

  Future<List<Vector>> getAllVectors() => select(vectors).get();

  Future<void> insertVectors(List<VectorsCompanion> vectorList) =>
      batch((b) => b.insertAll(vectors, vectorList));

  Future<void> deleteVectorsByChunkIds(List<String> chunkIds) =>
      (delete(vectors)..where((v) => v.chunkId.isIn(chunkIds))).go();

  Future<int> countVectors() => vectors.count().getSingle();
}