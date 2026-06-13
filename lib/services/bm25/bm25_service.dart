// ═══════════════════════════════════════════════════════════════════════════════
// BM25 SPARSE SEARCH SERVICE (VERSION=bm25_v1)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Sparse search dùng SQLite FTS5 để thực hiện BM25 keyword matching.
// Kết hợp với dense search (Gecko embedding) qua Reciprocal Rank Fusion (RRF)
// để cải thiện RAG accuracy (giải P1 Gecko discrimination).
//
// Dùng kèm: chunks_fts virtual table (FTS5) trong SQLite.

import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Service thực hiện BM25 sparse search trên chunks đã index.
abstract interface class Bm25Service {
  /// Search chunks bằng BM25 (FTS5).
  ///
  /// [query] - Câu hỏi người dùng (sẽ được sanitize cho FTS5).
  /// [allowedDocumentIds] - Set document IDs được phép truy cập (theo KnowledgeScope).
  /// [topK] - Số kết quả tối đa (default 50).
  Future<List<SearchResult>> search({
    required String query,
    required Set<String> allowedDocumentIds,
    int topK = 50,
  });

  /// Index một chunk vào FTS5 table.
  Future<void> indexChunk(String chunkId, String documentId, String chunkText);

  /// Index nhiều chunks cùng lúc.
  Future<void> indexChunks(List<({String id, String documentId, String text})> chunks);

  /// Xoá chunks khỏi FTS5 table.
  Future<void> deleteByChunkIds(List<String> chunkIds);
}