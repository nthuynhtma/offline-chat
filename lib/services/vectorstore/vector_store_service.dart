import 'dart:math';

import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/core/utils/embedding_serializer.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:drift/drift.dart';

abstract interface class VectorStoreService {
  /// Lưu vector cho một chunk
  Future<void> insert({
    required String chunkId,
    required List<double> embedding,
  });

  /// Lưu nhiều vectors cùng lúc
  Future<void> insertBatch(List<VectorEntry> entries);

  /// Tìm top-K chunks gần nhất với queryVector
  /// Chỉ trả về kết quả có score >= threshold
  Future<List<SearchResult>> search({
    required List<double> queryVector,
    int topK = 5,
    double threshold = 0.7,
  });

  /// Xóa vectors theo danh sách chunk IDs
  Future<void> deleteByChunkIds(List<String> chunkIds);

  /// Tổng số vectors
  Future<int> count();
}

class VectorEntry {
  final String chunkId;
  final List<double> embedding;
  const VectorEntry({required this.chunkId, required this.embedding});
}

class SearchResult {
  final String chunkId;
  final double score;
  final String chunkText;

  const SearchResult({
    required this.chunkId,
    required this.score,
    required this.chunkText,
  });
}

/// SQLite-based vector store with brute-force cosine similarity search.
///
/// Uses the existing VectorsDao and ChunksDao from Drift via AppDatabase.
/// Suitable for up to ~50,000 chunks.
class VectorStoreServiceImpl implements VectorStoreService {
  final AppDatabase _db;

  VectorStoreServiceImpl(this._db);

  @override
  Future<void> insert({
    required String chunkId,
    required List<double> embedding,
  }) async {
    try {
      final vector = VectorsCompanion(
        // FIX #6: chunkId đã unique → dùng trực tiếp làm id, không cần timestamp
        id: Value('v_$chunkId'),
        chunkId: Value(chunkId),
        embedding: Value(EmbeddingSerializer.serialize(embedding)),
        createdAt: Value(DateTime.now()),
      );
      await _db.vectorsDao.insertVectors([vector]);
    } catch (e) {
      throw StorageException('Failed to insert vector: $e');
    }
  }

  @override
  Future<void> insertBatch(List<VectorEntry> entries) async {
    try {
      // FIX #6: Dùng index để đảm bảo ID unique trong batch
      // (chunkId đã unique theo thiết kế, nhưng index phòng trường hợp duplicate chunkId)
      final seen = <String>{};
      final vectors = <VectorsCompanion>[];

      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        // Nếu chunkId trùng trong cùng batch (không nên xảy ra), skip
        if (!seen.add(e.chunkId)) continue;

        vectors.add(VectorsCompanion(
          id: Value('v_${e.chunkId}'),
          chunkId: Value(e.chunkId),
          embedding: Value(EmbeddingSerializer.serialize(e.embedding)),
          createdAt: Value(DateTime.now()),
        ));
      }

      await _db.vectorsDao.insertVectors(vectors);
    } catch (e) {
      throw StorageException('Failed to insert vectors batch: $e');
    }
  }

  @override
  Future<List<SearchResult>> search({
    required List<double> queryVector,
    int topK = 5,
    double threshold = 0.7,
  }) async {
    try {
      final allVectors = await _db.vectorsDao.getAllVectors();
      if (allVectors.isEmpty) return [];

      // Calculate cosine similarity for all vectors
      final scored = <_ScoredResult>[];
      for (final v in allVectors) {
        final embedding = EmbeddingSerializer.deserialize(v.embedding);
        if (embedding.length != queryVector.length) continue;

        final score = _cosineSimilarity(queryVector, embedding);
        if (score >= threshold) {
          scored.add(_ScoredResult(chunkId: v.chunkId, score: score));
        }
      }

      // Sort by score descending
      scored.sort((a, b) => b.score.compareTo(a.score));
      final topResults = scored.take(topK).toList();

      if (topResults.isEmpty) return [];

      // Fetch chunk texts
      final chunkIds = topResults.map((r) => r.chunkId).toList();
      final chunks = await _db.chunksDao.getChunksByIds(chunkIds);
      final chunkMap = {for (final c in chunks) c.id: c.chunkText};

      return topResults
          .where((r) => chunkMap.containsKey(r.chunkId))
          .map((r) => SearchResult(
                chunkId: r.chunkId,
                score: r.score,
                chunkText: chunkMap[r.chunkId]!,
              ))
          .toList();
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Vector search failed: $e');
    }
  }

  @override
  Future<void> deleteByChunkIds(List<String> chunkIds) async {
    try {
      await _db.vectorsDao.deleteVectorsByChunkIds(chunkIds);
    } catch (e) {
      throw StorageException('Failed to delete vectors: $e');
    }
  }

  @override
  Future<int> count() async {
    try {
      return await _db.vectorsDao.countVectors();
    } catch (e) {
      throw StorageException('Failed to count vectors: $e');
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length);
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}

class _ScoredResult {
  final String chunkId;
  final double score;
  _ScoredResult({required this.chunkId, required this.score});
}
