import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/features/knowledge/models/document_model.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';

abstract interface class DocumentRepository {
  Future<List<DocumentModel>> getAllDocuments();
  Stream<List<DocumentModel>> watchAllDocuments();
  Future<DocumentModel> importDocument(String filePath);
  Future<void> deleteDocument(String id);
  Future<void> reindexDocument(String id);

  /// Import with progress callback [onProgress] (0.0 to 1.0).
  /// The callback receives [documentId] (once known) and [progress].
  Future<DocumentModel> importDocumentWithProgress(
    String filePath, {
    void Function(String documentId, double progress)? onProgress,
  });
}

class DocumentRepositoryImpl implements DocumentRepository {
  final AppDatabase _db;
  final DocumentUploadQueue _uploadQueue;
  final Uuid _uuid = const Uuid();

  DocumentRepositoryImpl(
    this._db,
    this._uploadQueue,
  );

  @override
  Future<List<DocumentModel>> getAllDocuments() async {
    final rows = await _db.documentsDao.getDocumentsBySessionId(null);
    return rows.map(DocumentModel.fromDbRow).toList();
  }

  @override
  Stream<List<DocumentModel>> watchAllDocuments() =>
      _db.documentsDao.watchAllDocuments().map(
            (rows) => rows
                .where((row) => row.sessionId == null)
                .map(DocumentModel.fromDbRow)
                .toList(),
          );

  @override
  Future<DocumentModel> importDocument(String filePath) async {
    return importDocumentWithProgress(filePath);
  }

  @override
  Future<DocumentModel> importDocumentWithProgress(
    String filePath, {
    void Function(String documentId, double progress)? onProgress,
  }) async {
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

    void progress(double p) => onProgress?.call(docId, p);
    progress(0.05); // 5% - copied file

    try {
      // Save metadata only. The shared upload queue owns parse/chunk/embed.
      await _db.documentsDao.insertDocument(DocumentsCompanion(
        id: Value(docId),
        name: Value(docName),
        path: Value(destPath),
        sizeBytes: Value(fileSize),
        chunkCount: const Value(0),
        mimeType: Value(mimeType),
        sessionId: const Value(null),
        status: Value(IndexStatus.pending.toInt),
        progress: const Value(0.0),
        createdAt: Value(DateTime.now()),
      ));

      _uploadQueue.enqueue(DocumentUploadJob(
        documentId: docId,
        filePath: destPath,
        name: docName,
        sizeBytes: fileSize,
        mimeType: mimeType,
        sessionId: null,
      ));

      final row = await _db.documentsDao.getAllDocuments();
      final doc = row.firstWhere((d) => d.id == docId);
      progress(0.1); // 10% - queued
      return DocumentModel.fromDbRow(doc);
    } catch (e) {
      // Clean up on failure
      try {
        await _db.documentsDao.deleteDocument(docId);
        await File(destPath).delete();
      } catch (_) {}
      if (e is DocumentParseException) rethrow;
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

      // Delete vectors (via vectorsDao)
      if (chunkIds.isNotEmpty) {
        await _db.vectorsDao.deleteVectorsByChunkIds(chunkIds);
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
        await _db.vectorsDao.deleteVectorsByChunkIds(oldChunkIds);
      }
      await _db.chunksDao.deleteChunksByDocument(id);
      await _db.documentsDao.updateChunkCount(id, 0);
      await _db.documentsDao.updateDocumentStatus(id, IndexStatus.pending);
      await _db.documentsDao.updateDocumentProgress(id, 0, 100);

      _uploadQueue.enqueuePriority(DocumentUploadJob(
        documentId: id,
        filePath: doc.path,
        name: doc.name,
        sizeBytes: doc.sizeBytes,
        mimeType: doc.mimeType,
        sessionId: doc.sessionId,
      ));
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
