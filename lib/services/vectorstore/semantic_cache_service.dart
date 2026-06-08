import 'dart:math';

import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Entry trong semantic cache
class _CacheEntry {
  final String query;
  final List<double> embedding;
  final List<SearchResult> results;
  final DateTime createdAt;
  int hitCount;

  _CacheEntry({
    required this.query,
    required this.embedding,
    required this.results,
    required this.createdAt,
    this.hitCount = 1,
  });
}

/// Semantic cache cho embedding queries.
///
/// Khi user hỏi câu tương tự, dùng cache thay vì re-embed và re-search.
/// Dùng cosine similarity để detect queries giống nhau.
abstract interface class SemanticCacheService {
  /// Tìm kết quả cached cho query.
  /// Trả về null nếu không có cache match (threshold < 0.95).
  Future<List<SearchResult>?> get(String query);

  /// Lưu kết quả vào cache.
  Future<void> set(String query, List<double> embedding, List<SearchResult> results);

  /// Xoá toàn bộ cache.
  Future<void> clear();

  /// Số entries trong cache.
  int get size;
}

class SemanticCacheServiceImpl implements SemanticCacheService {
  final List<_CacheEntry> _cache = [];
  static const int _maxSize = 50;
  static const double _similarityThreshold = 0.95;
  static const int _maxAgeMinutes = 30;

  @override
  int get size => _cache.length;

  @override
  Future<List<SearchResult>?> get(String query) async {
    _evictExpired();

    for (final entry in _cache) {
      // Fast path: exact match
      if (entry.query == query) {
        entry.hitCount++;
        return entry.results;
      }

      // Semantic match: compare embedding similarity
      // (chỉ dùng nếu đã có sẵn embedding, thường là từ GeckoService)
    }

    return null;
  }

  /// Kiểm tra cache bằng embedding vector (gọi sau khi embed query)
  List<SearchResult>? getByEmbedding(List<double> embedding) {
    _evictExpired();

    for (final entry in _cache) {
      final similarity = _cosineSimilarity(embedding, entry.embedding);
      if (similarity >= _similarityThreshold) {
        entry.hitCount++;
        return entry.results;
      }
    }

    return null;
  }

  @override
  Future<void> set(
    String query,
    List<double> embedding,
    List<SearchResult> results,
  ) async {
    // Không cache nếu không có kết quả
    if (results.isEmpty) return;

    // Kiểm tra xem query đã tồn tại chưa (update hitCount)
    for (final entry in _cache) {
      if (entry.query == query) {
        entry.hitCount++;
        return;
      }
    }

    // Evict nếu đầy (xóa entry ít hit nhất + cũ nhất)
    if (_cache.length >= _maxSize) {
      _cache.sort((a, b) {
        final hitDiff = a.hitCount.compareTo(b.hitCount);
        if (hitDiff != 0) return hitDiff;
        return a.createdAt.compareTo(b.createdAt);
      });
      _cache.removeAt(0);
    }

    _cache.add(_CacheEntry(
      query: query,
      embedding: embedding,
      results: results,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }

  void _evictExpired() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: _maxAgeMinutes));
    _cache.removeWhere((entry) => entry.createdAt.isBefore(cutoff));
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
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