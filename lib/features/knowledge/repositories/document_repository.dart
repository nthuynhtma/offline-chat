import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/features/knowledge/models/document_model.dart';
import 'package:offline_chat/services/chunker/chunking_service.dart';
import 'package:offline_chat/services/parser/document_parser_service.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

abstract interface class DocumentRepository {
  Future<List<DocumentModel>> getAllDocuments();
  Stream<List<DocumentModel>> watchAllDocuments();
  Future<DocumentModel> importDocument(String filePath);
  Future<void> deleteDocument(String id);
  Future<void> reindexDocument(String id);
}

class DocumentRepositoryImpl implements DocumentRepository {
  final AppDatabase _db;
  final DocumentParserService _parser;
  final ChunkingService _chunker;
  final VectorStoreService _vectorStore;
  final Uuid _uuid = const Uuid();

  DocumentRepositoryImpl(
    this._db,
    this._parser,
    this._chunker,
    this._vectorStore,
  );

  @override
  Future<List<DocumentModel>> getAllDocuments() async {
    final rows = await _db.documentsDao.getAllDocuments();
    return rows.map(DocumentModel.fromDbRow).toList();
  }

  @override
  Stream<List<DocumentModel>> watchAllDocuments() =>
      _db.documentsDao.watchAllDocuments().map(
            (rows) => rows.map(DocumentModel.fromDbRow).toList(),
          );

  @override
  Future<DocumentModel> importDocument(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw DocumentParseException('File not found: $filePath');
    }

    final docId = _uuid.v4();
    final appDir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(appDir.path, 'documents'));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    final destPath = p.join(destDir.path, '${docId}_${p.basename(filePath)}');
    await file.copy(destPath);

    final docName = p.basename(filePath);
    final mimeType = _detectMime(filePath);
    final fileSize = await file.length();

    try {
      // 1. Save document metadata
      await _db.documentsDao.insertDocument(DocumentsCompanion(
        id: Value(docId),
        name: Value(docName),
        path: Value(destPath),
        sizeBytes: Value(fileSize),
        chunkCount: const Value(0),
        mimeType: Value(mimeType),
        createdAt: Value(DateTime.now()),
      ));

      // 2. Parse → rawText
      final rawText = await _parser.parse(destPath);

      // 3. Chunk text
      final chunks = _chunker.chunk(rawText);

      // 4. Save chunks + vectors
      final chunkEntries = <_ChunkEntry>[];
      for (int i = 0; i < chunks.length; i++) {
        final chunkId = _uuid.v4();
        chunkEntries.add(_ChunkEntry(
          id: chunkId,
          text: chunks[i],
          index: i,
        ));
      }

      // Insert chunks into database
      final chunkCompanions = chunkEntries.map((e) {
        return ChunksCompanion(
          id: Value(e.id),
          documentId: Value(docId),
          chunkText: Value(e.text),
          chunkIndex: Value(e.index),
          tokenCount: Value((e.text.length / 4).ceil()),
          createdAt: Value(DateTime.now()),
        );
      }).toList();
      await _db.chunksDao.insertChunks(chunkCompanions);

      // 5. Update chunk count
      await _db.documentsDao.updateChunkCount(docId, chunks.length);

      // Return document model
      final row = await _db.documentsDao.getAllDocuments();
      final doc = row.firstWhere((d) => d.id == docId);
      return DocumentModel.fromDbRow(doc);
    } catch (e) {
      // Clean up on failure
      try {
        await _db.documentsDao.deleteDocument(docId);
        await File(destPath).delete();
      } catch (_) {}
      if (e is AppException) rethrow;
      throw DocumentParseException('Import failed: $e');
    }
  }

  @override
  Future<void> deleteDocument(String id) async {
    try {
      // Get chunks to delete vectors
      final chunks = await _db.chunksDao.getChunksByDocument(id);
      final chunkIds = chunks.map((c) => c.id).toList();

      // Delete vectors
      if (chunkIds.isNotEmpty) {
        await _vectorStore.deleteByChunkIds(chunkIds);
      }

      // Get document for file path
      final doc = await _db.documentsDao.getAllDocuments();
      final docRow = doc.where((d) => d.id == id).firstOrNull;
      if (docRow != null) {
        final file = File(docRow.path);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Delete from database (cascade deletes chunks automatically)
      await _db.documentsDao.deleteDocument(id);
    } catch (e) {
      throw StorageException('Failed to delete document: $e');
    }
  }

  @override
  Future<void> reindexDocument(String id) async {
    final docs = await _db.documentsDao.getAllDocuments();
    final doc = docs.where((d) => d.id == id).firstOrNull;
    if (doc == null) {
      throw DocumentParseException('Document not found: $id');
    }

    try {
      // Delete old chunks and vectors
      final oldChunks = await _db.chunksDao.getChunksByDocument(id);
      final oldChunkIds = oldChunks.map((c) => c.id).toList();
      if (oldChunkIds.isNotEmpty) {
        await _vectorStore.deleteByChunkIds(oldChunkIds);
      }
      await _db.chunksDao.deleteChunksByDocument(id);

      // Re-parse and re-chunk
      final rawText = await _parser.parse(doc.path);
      final chunks = _chunker.chunk(rawText);

      final chunkEntries = chunks.asMap().entries.map((e) {
        return ChunksCompanion(
          id: Value(_uuid.v4()),
          documentId: Value(id),
          chunkText: Value(e.value),
          chunkIndex: Value(e.key),
          tokenCount: Value((e.value.length / 4).ceil()),
          createdAt: Value(DateTime.now()),
        );
      }).toList();

      await _db.chunksDao.insertChunks(chunkEntries);
      await _db.documentsDao.updateChunkCount(id, chunks.length);
    } catch (e) {
      throw StorageException('Reindex failed: $e');
    }
  }

  String _detectMime(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      default:
        return 'application/octet-stream';
    }
  }
}

class _ChunkEntry {
  final String id;
  final String text;
  final int index;
  _ChunkEntry({required this.id, required this.text, required this.index});
}