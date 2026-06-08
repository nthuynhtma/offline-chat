import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

AppDatabase createTestDatabase() {
  return AppDatabase(queryExecutor: NativeDatabase.memory());
}

/// Helper to insert a chunk and its vector into the database
Future<void> insertChunkWithVector({
  required AppDatabase db,
  required String chunkId,
  required String documentId,
  required String chunkText,
  required List<double> embedding,
  int chunkIndex = 0,
}) async {
  // Insert chunk
  final chunk = ChunksCompanion(
    id: Value(chunkId),
    documentId: Value(documentId),
    chunkText: Value(chunkText),
    chunkIndex: Value(chunkIndex),
    tokenCount: Value((chunkText.length / 4).ceil()),
    createdAt: Value(DateTime.now()),
  );
  await db.chunksDao.insertChunks([chunk]);

  // Insert vector
  final vector = VectorsCompanion(
    id: Value('v_$chunkId'),
    chunkId: Value(chunkId),
    embedding: Value(
      Float32List.fromList(embedding).buffer.asUint8List(),
    ),
    createdAt: Value(DateTime.now()),
  );
  await db.vectorsDao.insertVectors([vector]);
}

void main() {
  late AppDatabase db;
  late VectorStoreService vectorStore;

  setUp(() {
    db = createTestDatabase();
    vectorStore = VectorStoreServiceImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('VectorStoreService', () {
    test('count returns 0 for empty store', () async {
      final count = await vectorStore.count();
      expect(count, 0);
    });

    test('search returns empty list for empty store', () async {
      final results = await vectorStore.search(
        queryVector: List<double>.filled(768, 0.1),
        topK: 5,
        threshold: 0.7,
      );
      expect(results, isEmpty);
    });

    test('insert and count work correctly', () async {
      await vectorStore.insert(
        chunkId: 'chunk_1',
        embedding: List<double>.filled(768, 0.5),
      );
      final count = await vectorStore.count();
      expect(count, 1);
    });

    test('insertBatch stores multiple vectors', () async {
      await vectorStore.insertBatch([
        VectorEntry(
          chunkId: 'chunk_1',
          embedding: List<double>.filled(768, 0.5),
        ),
        VectorEntry(
          chunkId: 'chunk_2',
          embedding: List<double>.filled(768, 0.3),
        ),
      ]);
      final count = await vectorStore.count();
      expect(count, 2);
    });

    test('search returns results with high similarity', () async {
      // Target: first half = 1.0, second half = 0.0
      final targetVector = List<double>.filled(768, 0.0);
      for (int i = 0; i < 384; i++) {
        targetVector[i] = 1.0;
      }
      // Norm = sqrt(384) ≈ 19.6
      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_target',
        documentId: 'doc_1',
        chunkText: 'Target document chunk',
        embedding: targetVector,
      );

      // Other: all 0.0
      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_other',
        documentId: 'doc_1',
        chunkText: 'Other document chunk',
        embedding: List<double>.filled(768, 0.0),
      );

      // Query: same as target (first half 1.0)
      final query = List<double>.filled(768, 0.0);
      for (int i = 0; i < 384; i++) {
        query[i] = 1.0;
      }
      final results = await vectorStore.search(
        queryVector: query,
        topK: 5,
        threshold: 0.7,
      );

      expect(results, hasLength(1));
      expect(results.first.chunkId, 'chunk_target');
      expect(results.first.chunkText, 'Target document chunk');
    });

    test('search respects threshold', () async {
      // Insert vector orthogonal to query
      final vec = List<double>.filled(768, 0.0);
      vec[0] = 1.0;
      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_1',
        documentId: 'doc_1',
        chunkText: 'Orthogonal chunk',
        embedding: vec,
      );

      // Query: different dimension (orthogonal → score ≈ 0)
      final query = List<double>.filled(768, 0.0);
      query[1] = 1.0;
      final results = await vectorStore.search(
        queryVector: query,
        topK: 5,
        threshold: 0.9,
      );
      expect(results, isEmpty);
    });

    test('search respects topK parameter', () async {
      // All vectors have some similarity to query (same first 2 dims)
      for (int i = 0; i < 5; i++) {
        final vec = List<double>.filled(768, 0.0);
        vec[0] = 0.9;
        vec[1] = 0.4;
        vec[2] = 0.1 * i;
        await insertChunkWithVector(
          db: db,
          chunkId: 'chunk_$i',
          documentId: 'doc_1',
          chunkText: 'Chunk $i',
          embedding: vec,
          chunkIndex: i,
        );
      }

      // All vectors have same first 2 dims → similar to query
      final query = List<double>.filled(768, 0.0);
      query[0] = 0.9;
      query[1] = 0.4;
      final results = await vectorStore.search(
        queryVector: query,
        topK: 3,
        threshold: 0.7,
      );
      expect(results.length, 3);
    });

    test('deleteByChunkIds removes vectors', () async {
      final vec1 = List<double>.filled(768, 0.0);
      vec1[0] = 1.0;
      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_1',
        documentId: 'doc_1',
        chunkText: 'Chunk 1',
        embedding: vec1,
      );

      final vec2 = List<double>.filled(768, 0.0);
      vec2[1] = 1.0;
      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_2',
        documentId: 'doc_1',
        chunkText: 'Chunk 2',
        embedding: vec2,
      );

      await vectorStore.deleteByChunkIds(['chunk_1']);
      final count = await vectorStore.count();
      expect(count, 1);
    });

    test('insert and search with specific vector patterns', () async {
      // Create vectors with specific patterns
      final v1 = List<double>.filled(768, 0.0);
      v1[0] = 1.0;
      v1[1] = 0.5;
      // Normalize v1
      double norm1 = 0;
      for (final x in v1) {
        norm1 += x * x;
      }
      norm1 = norm1 > 0 ? norm1 : 1;
      for (int i = 0; i < v1.length; i++) {
        v1[i] = v1[i] / norm1;
      }

      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_a',
        documentId: 'doc_1',
        chunkText: 'First document chunk',
        embedding: v1,
      );

      final v2 = List<double>.filled(768, 0.0);
      v2[0] = 0.8;
      v2[1] = 0.3;
      double norm2 = 0;
      for (final x in v2) {
        norm2 += x * x;
      }
      norm2 = norm2 > 0 ? norm2 : 1;
      for (int i = 0; i < v2.length; i++) {
        v2[i] = v2[i] / norm2;
      }

      await insertChunkWithVector(
        db: db,
        chunkId: 'chunk_b',
        documentId: 'doc_1',
        chunkText: 'Second document chunk',
        embedding: v2,
      );

      // Search with query similar to v1
      final query = List<double>.filled(768, 0.0);
      query[0] = 0.9;
      query[1] = 0.4;
      double qNorm = 0;
      for (final x in query) {
        qNorm += x * x;
      }
      qNorm = qNorm > 0 ? qNorm : 1;
      for (int i = 0; i < query.length; i++) {
        query[i] = query[i] / qNorm;
      }

      final results = await vectorStore.search(
        queryVector: query,
        topK: 2,
        threshold: 0.0,
      );

      expect(results.length, 2);
      expect(results.first.chunkId, 'chunk_a');
      expect(results.first.chunkText, 'First document chunk');
    });
  });
}