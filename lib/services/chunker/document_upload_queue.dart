import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/core/utils/logger.dart' as logger;
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/services/chunker/chunking_service.dart';
import 'package:offline_chat/services/gecko/gecko_service.dart';
import 'package:offline_chat/services/parser/document_parser_service.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Một job trong upload queue.
class DocumentUploadJob {
  final String documentId;
  final String filePath;
  final String name;
  final int sizeBytes;
  final String mimeType;
  final String? sessionId;

  const DocumentUploadJob({
    required this.documentId,
    required this.filePath,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    this.sessionId,
  });
}

/// Trạng thái của queue.
enum QueueState { idle, processing }

/// FIFO queue xử lý upload document qua pipeline:
///   parse → chunk → embed → insert chunks + vectors + update DB
///
/// Granular progress (0.0 → 1.0):
///   0.00       pending    (status=pending, progress=0)
///   0.00→0.10  parse      (status=processing)
///   0.10→0.20  chunk      (status=processing)
///   0.20→0.95  embed      (per chunk, progressive)
///   0.95→1.00  insert DB  (status=processing)
///   1.00       completed  (status=completed)
///
/// Thread-safe: FIFO bằng [Future] chain, không cần lock phức tạp.
class DocumentUploadQueue {
  final DocumentsDao _docsDao;
  final ChunksDao _chunksDao;
  final DocumentParserService _parser;
  final ChunkingService _chunker;
  final GeckoService _gecko;
  final VectorStoreService _vectorStore;

  /// FIFO chain: job hiện tại đang chạy (null nếu idle).
  Future<void>? _currentJob;

  /// Queue các job đang chờ.
  final List<DocumentUploadJob> _pending = [];

  QueueState _state = QueueState.idle;
  QueueState get state => _state;

  /// Stream trạng thái queue.
  final StreamController<QueueState> _stateController =
      StreamController<QueueState>.broadcast();
  Stream<QueueState> get stateStream => _stateController.stream;

  /// Stream sự kiện khi một job hoàn thành / fail.
  final StreamController<DocumentUploadResult> _resultController =
      StreamController<DocumentUploadResult>.broadcast();
  Stream<DocumentUploadResult> get resultStream => _resultController.stream;

  DocumentUploadQueue({
    required DocumentsDao docsDao,
    required ChunksDao chunksDao,
    required DocumentParserService parser,
    required ChunkingService chunker,
    required GeckoService gecko,
    required VectorStoreService vectorStore,
  })  : _docsDao = docsDao,
        _chunksDao = chunksDao,
        _parser = parser,
        _chunker = chunker,
        _gecko = gecko,
        _vectorStore = vectorStore;

  /// Enqueue một job. Trả về documentId.
  /// Nếu queue đang idle, tự động start processing.
  String enqueue(DocumentUploadJob job) {
    _pending.add(job);
    _processNext();
    return job.documentId;
  }

  /// Đưa job vào đầu queue (dùng cho retry).
  String enqueuePriority(DocumentUploadJob job) {
    _pending.insert(0, job);
    _processNext();
    return job.documentId;
  }

  /// Retry một document đã failed.
  /// Đặt lại status=pending, retryCount=0 và đưa vào đầu queue.
  Future<void> retry(String documentId) async {
    final doc = await _docsDao.getDocumentById(documentId);
    if (doc == null) {
      logger.log.w('[UploadQueue] retry: document not found: $documentId');
      return;
    }
    if (IndexStatusX.fromInt(doc.status) != IndexStatus.failed) {
      logger.log.w('[UploadQueue] retry: document not failed: $documentId');
      return;
    }

    // Reset status
    await _docsDao.updateDocumentStatus(documentId, IndexStatus.pending);
    await _docsDao.resetRetryCount(documentId);

    // Enqueue priority (đầu queue)
    enqueuePriority(DocumentUploadJob(
      documentId: documentId,
      filePath: doc.path,
      name: doc.name,
      sizeBytes: doc.sizeBytes,
      mimeType: doc.mimeType,
      sessionId: doc.sessionId,
    ));

    logger.log.i('[UploadQueue] retry: $documentId (${doc.name})');
  }

  /// Số job đang pending.
  int get pendingCount => _pending.length;

  /// Cleanup.
  void dispose() {
    _stateController.close();
    _resultController.close();
  }

  /// Xử lý job tiếp theo trong queue (nếu đang idle và còn job).
  void _processNext() {
    if (_currentJob != null) return; // Đang xử lý
    if (_pending.isEmpty) return;

    final job = _pending.removeAt(0);
    _currentJob = _processJob(job).whenComplete(() {
      _currentJob = null;
      // Xử lý job tiếp theo nếu còn
      _processNext();
    });
  }

  /// Pipeline xử lý một job.
  Future<void> _processJob(DocumentUploadJob job) async {
    _setState(QueueState.processing);
    logger.log.i('[UploadQueue] Processing: ${job.name} (${job.documentId})');

    try {
      await _docsDao.updateDocumentStatus(
        job.documentId,
        IndexStatus.processing,
      );

      // ─── Step 1: Parse (0.00 → 0.10) ──────────────────────────────────
      await _setProgress(job.documentId, 0.05);
      final rawText = await _parser.parse(job.filePath);
      if (rawText.isEmpty) {
        throw const DocumentParseException('Parsed text is empty');
      }

      // ─── Step 2: Chunk (0.10 → 0.20) ──────────────────────────────────
      await _setProgress(job.documentId, 0.15);
      const int chunkSize = 200;
      const int chunkOverlap = 50;
      final chunks = _chunker.chunk(
        rawText,
        chunkSize: chunkSize,
        overlap: chunkOverlap,
      );
      if (chunks.isEmpty) {
        throw const DocumentParseException('No chunks generated');
      }

      // Log chunk detail
      logger.log.i('[UploadQueue] Chunks: ${chunks.length} chunks (chunkSize=$chunkSize, overlap=$chunkOverlap)');
      for (var i = 0; i < chunks.length; i++) {
        final estimatedTokens = estimateTokens(chunks[i]);
        final previewLen = min(60, chunks[i].length);
        final preview = previewLen > 0 ? chunks[i].substring(0, previewLen) : '';
        logger.log.d(
          '[UploadQueue] chunk[$i] '
          'chars=${chunks[i].length} '
          'tokens=$estimatedTokens '
          'preview="$preview..."',
        );
      }

      await _setProgress(job.documentId, 0.20);

      // ─── Step 3: Embed từng chunk (0.20 → 0.95) ───────────────────────
      // Guard: Gecko phải ready trước khi embed
      if (!_gecko.isReady) {
        logger.log.w(
          '[UploadQueue] Gecko guard triggered: '
          'isReady=${_gecko.isReady}, '
          'Doc=${job.name} (${job.documentId})',
        );
        throw const UploadQueueException(
          'Embedding model (Gecko) chưa sẵn sàng. '
          'Vui lòng đợi model khởi tạo xong rồi thử lại.',
        );
      }

      final totalChunks = chunks.length;

      final allEmbeddings = <List<double>>[];
      for (var i = 0; i < totalChunks; i++) {
        final progress = 0.20 + 0.75 * ((i + 1) / totalChunks);
        await _setProgress(job.documentId, progress);

        final embedding = await _gecko.embed(chunks[i]);
        allEmbeddings.add(embedding);
      }

      // ─── Step 4: Insert chunks + vectors (0.95 → 1.00) ────────────────
      await _setProgress(job.documentId, 0.95);

      // Tạo ChunksCompanions
      final uuid = const Uuid();
      final chunkCompanions = <ChunksCompanion>[];
      for (var i = 0; i < chunks.length; i++) {
        chunkCompanions.add(ChunksCompanion(
          id: Value(uuid.v4()),
          documentId: Value(job.documentId),
          chunkIndex: Value(i),
          chunkText: Value(chunks[i]),
          tokenCount: Value((chunks[i].length / 4).round()),
          createdAt: Value(DateTime.now()),
        ));
      }

      // Insert chunks vào DB
      await _chunksDao.insertChunks(chunkCompanions);

      // Fetch lại để lấy id thật (Drift auto-generate)
      final insertedChunks =
          await _chunksDao.getChunksByDocument(job.documentId);

      // Tạo VectorEntries
      final vectorEntries = <VectorEntry>[];
      for (var i = 0; i < insertedChunks.length && i < allEmbeddings.length; i++) {
        vectorEntries.add(VectorEntry(
          chunkId: insertedChunks[i].id,
          embedding: allEmbeddings[i],
        ));
      }

      // Insert vectors
      if (vectorEntries.isNotEmpty) {
        await _vectorStore.insertBatch(vectorEntries);
      }

      // ─── Step 5: Finalize ─────────────────────────────────────────────
      await _docsDao.updateChunkCount(job.documentId, chunks.length);
      await _docsDao.updateDocumentStatus(job.documentId, IndexStatus.completed);
      await _docsDao.resetRetryCount(job.documentId);
      await _setProgress(job.documentId, 1.0);

      logger.log.i('[UploadQueue] Completed: ${job.name} '
          '(${chunks.length} chunks, ${insertedChunks.length} vectors)');

      _resultController.add(DocumentUploadResult(
        documentId: job.documentId,
        success: true,
        chunkCount: chunks.length,
      ));
    } catch (e) {
      logger.log.e('[UploadQueue] Failed: ${job.name} — $e');

      // Update status + error
      await _docsDao.updateDocumentStatus(
        job.documentId,
        IndexStatus.failed,
        error: e.toString(),
      );
      await _docsDao.incrementRetryCount(job.documentId);

      _resultController.add(DocumentUploadResult(
        documentId: job.documentId,
        success: false,
        error: e.toString(),
      ));
    } finally {
      if (_pending.isEmpty) {
        _setState(QueueState.idle);
      }
    }
  }

  /// Update progress value (0.0 → 1.0) trên DB document.
  Future<void> _setProgress(String docId, double value) async {
    final clamped = min(value, 1.0);
    // Chuyển sang step/totalSteps format (100 bước)
    final step = (clamped * 100).round();
    await _docsDao.updateDocumentProgress(docId, step, 100);
  }

  void _setState(QueueState newState) {
    _state = newState;
    _stateController.add(newState);
  }
}

/// Kết quả xử lý một job.
class DocumentUploadResult {
  final String documentId;
  final bool success;
  final int chunkCount;
  final String? error;

  const DocumentUploadResult({
    required this.documentId,
    required this.success,
    this.chunkCount = 0,
    this.error,
  });
}
