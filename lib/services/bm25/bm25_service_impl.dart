// ═══════════════════════════════════════════════════════════════════════════════
// BM25 SPARSE SEARCH IMPLEMENTATION (VERSION=bm25_v1)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Implementation sử dụng SQLite FTS5 full-text search với BM25 ranking.
// Pipeline:
//   1. Sanitize query (remove FTS5 special chars)
//   2. FTS5 MATCH search → topK results
//   3. Filter by allowedDocumentIds
//   4. Normalize scores (BM25 trả về negative scores)
//
// FTS5 tokenizer: unicode61 (hỗ trợ tiếng Việt Unicode)

import 'package:drift/drift.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/services/bm25/bm25_service.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

class Bm25ServiceImpl implements Bm25Service {
  final AppDatabase _db;

  Bm25ServiceImpl(this._db);

  /// Sanitize FTS5 query: remove special characters và format cho phrase search.
  /// FTS5 special characters: ( ) * ^ " ~ : +
  String _sanitizeQuery(String query) {
    // Trim và normalize whitespace
    var q = query.trim().replaceAll(RegExp(r'\s+'), ' ');

    // Remove FTS5 special characters
    q = q.replaceAll(RegExp(r'[()*^"~:+]'), ' ');

    // Trim lại sau khi remove
    q = q.trim();

    // Nếu query có nhiều từ, wrap trong double quotes cho phrase search
    // để match chính xác cụm từ
    if (q.contains(' ') && q.length > 3) {
      // Không wrap nếu đã có quotes hoặc ký tự đặc biệt
      if (!q.contains('"') && !q.contains("'")) {
        q = '"$q"';
      }
    }

    return q;
  }

  @override
  Future<List<SearchResult>> search({
    required String query,
    required Set<String> allowedDocumentIds,
    int topK = 50,
  }) async {
    final sanitizedQuery = _sanitizeQuery(query);

    if (sanitizedQuery.isEmpty) {
      log_util.log.d('🔍 [BM25] Query rỗng sau khi sanitize — skip search');
      return [];
    }

    log_util.log.d(
      '🔍 [BM25] Searching: query="$query" sanitized="$sanitizedQuery"',
    );

    try {
      // BM25 search with FTS5 (virtual table, không có Drift table class)
      final rows = await _db.customSelect(
        '''
        SELECT 
          chunk_id,
          bm25(chunks_fts, 1.0, 10.0) as score,
          document_id,
          chunk_text
        FROM chunks_fts
        WHERE chunks_fts MATCH ?
        ORDER BY score
        LIMIT ?
        ''',
        variables: [
          Variable.withString(sanitizedQuery),
          Variable.withInt(topK),
        ],
      ).get();

      if (rows.isEmpty) {
        log_util.log.d('🔍 [BM25] Không tìm thấy kết quả cho query');
        return [];
      }

      // Filter by allowedDocumentIds
      final filtered = rows.where((r) {
        final docId = r.read<String>('document_id');
        return allowedDocumentIds.contains(docId);
      }).toList();

      log_util.log.i(
        '🔍 [BM25] Found ${rows.length} raw, '
        '${filtered.length} after document filter',
      );

      // Map to SearchResult (BM25 returns negative scores, take absolute value)
      return filtered.map((r) => SearchResult(
        chunkId: r.read<String>('chunk_id'),
        score: r.read<double>('score').abs(),
        chunkText: r.read<String>('chunk_text'),
      )).toList();
    } catch (e) {
      log_util.log.w('⚠️ [BM25] Search error: $e');
      return [];
    }
  }

  @override
  Future<void> indexChunk(String chunkId, String documentId, String chunkText) async {
    try {
      // Escape single quotes by doubling them (FTS5 SQL injection safety)
      final escapedText = chunkText.replaceAll("'", "''");
      await _db.customStatement(
        "INSERT INTO chunks_fts(chunk_id, document_id, chunk_text) VALUES ('$chunkId', '$documentId', '$escapedText')",
      );
    } catch (e) {
      log_util.log.w('⚠️ [BM25] Index chunk error (chunkId=$chunkId): $e');
    }
  }

  @override
  Future<void> indexChunks(
    List<({String id, String documentId, String text})> chunks,
  ) async {
    if (chunks.isEmpty) return;

    for (final chunk in chunks) {
      await indexChunk(chunk.id, chunk.documentId, chunk.text);
    }
    log_util.log.i('📚 [BM25] Indexed ${chunks.length} chunks into FTS5');
  }

  @override
  Future<void> deleteByChunkIds(List<String> chunkIds) async {
    if (chunkIds.isEmpty) return;

    for (final chunkId in chunkIds) {
      try {
        await _db.customStatement(
          "DELETE FROM chunks_fts WHERE chunk_id = '$chunkId'",
        );
      } catch (e) {
        log_util.log.w('⚠️ [BM25] Delete chunk error (chunkId=$chunkId): $e');
      }
    }
    log_util.log.d('🗑️ [BM25] Deleted ${chunkIds.length} chunks from FTS5');
  }
}