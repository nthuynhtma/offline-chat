import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';

/// Trạng thái của SessionFilesCubit.
sealed class SessionFilesState extends Equatable {
  const SessionFilesState();

  @override
  List<Object?> get props => [];
}

class SessionFilesLoading extends SessionFilesState {
  const SessionFilesLoading();
}

class SessionFilesLoaded extends SessionFilesState {
  final List<SessionFileItem> files;
  final QueueState queueState;
  final int pendingCount;

  const SessionFilesLoaded({
    required this.files,
    this.queueState = QueueState.idle,
    this.pendingCount = 0,
  });

  @override
  List<Object?> get props => [files, queueState, pendingCount];
}

class SessionFilesError extends SessionFilesState {
  final String message;
  const SessionFilesError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Một item file trong session.
class SessionFileItem extends Equatable {
  final String id;
  final String name;
  final IndexStatus status;
  final double progress;
  final String? errorMessage;
  final int retryCount;
  final DateTime createdAt;

  const SessionFileItem({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    this.errorMessage,
    this.retryCount = 0,
    required this.createdAt,
  });

  @override
  List<Object?> get props =>
      [id, name, status, progress, errorMessage, retryCount, createdAt];
}

/// Cubit quản lý danh sách files trong session.
///
/// Subscribes vào:
///   1. `DocumentsDao.watchAllDocuments()` — realtime DB updates
///   2. `DocumentUploadQueue.resultStream` — kết quả queue xử lý
///   3. `DocumentUploadQueue.stateStream` — trạng thái queue
class SessionFilesCubit extends Cubit<SessionFilesState> {
  final DocumentsDao _documentsDao;
  final SessionDocumentRefsDao _refsDao;
  final DocumentUploadQueue _uploadQueue;

  /// Subscription cho DB stream.
  StreamSubscription? _dbSubscription;

  /// Subscription cho queue result.
  StreamSubscription? _resultSubscription;

  /// Subscription cho queue state.
  StreamSubscription? _stateSubscription;

  /// SessionId hiện tại. null = global files.
  String? _sessionId;

  SessionFilesCubit({
    required DocumentsDao documentsDao,
    required SessionDocumentRefsDao refsDao,
    required DocumentUploadQueue uploadQueue,
  })  : _documentsDao = documentsDao,
        _refsDao = refsDao,
        _uploadQueue = uploadQueue,
        super(const SessionFilesLoading());

  /// Set session và bắt đầu watch.
  void setSession(String? sessionId) {
    _sessionId = sessionId;
    _startWatching();
  }

  void _startWatching() {
    _dbSubscription?.cancel();
    _resultSubscription?.cancel();
    _stateSubscription?.cancel();

    // Watch DB changes
    _dbSubscription = _documentsDao.watchAllDocuments().listen(
      _onDocumentsChanged,
      onError: (e) => emit(SessionFilesError(e.toString())),
    );

    // Watch queue results
    _resultSubscription = _uploadQueue.resultStream.listen((result) {
      // DB stream sẽ tự update, nhưng force refresh ngay
      _documentsDao.watchAllDocuments().first.then(_onDocumentsChanged);
    });

    // Watch queue state
    _stateSubscription = _uploadQueue.stateStream.listen((state) {
      // Refresh khi queue state change để cập nhật pending badge
      _documentsDao.watchAllDocuments().first.then(_onDocumentsChanged);
    });
  }

  void _onDocumentsChanged(List<Document> documents) {
    try {
      final filtered = documents
          .where((d) => d.sessionId == _sessionId)
          .map((d) => SessionFileItem(
                id: d.id,
                name: d.name,
                status: IndexStatusX.fromInt(d.status),
                progress: d.progress,
                errorMessage: d.errorMessage,
                retryCount: d.retryCount,
                createdAt: d.createdAt,
              ))
          .toList();

      emit(SessionFilesLoaded(
        files: filtered,
        queueState: _uploadQueue.state,
        pendingCount: _uploadQueue.pendingCount,
      ));
    } catch (e) {
      emit(SessionFilesError(e.toString()));
    }
  }

  /// Detach/remove một document khỏi session.
  ///
  /// - Nếu document thuộc sở hữu của session này (doc.sessionId == sessionId)
  ///   → xoá hoàn toàn (cascade chunks + vectors).
  /// - Nếu là referenced global document → chỉ xoá row trong session_document_refs.
  ///
  /// TODO: Khi owner session xoá document, kiểm tra còn session refs khác không.
  /// Nếu có → convert sang global document hoặc yêu cầu confirm.
  Future<void> detachDocument(String documentId) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    final doc = await _documentsDao.getDocumentById(documentId);
    if (doc == null) return;

    // Ownership quyết định: session-uploaded → delete, referenced → detach
    if (doc.sessionId == sessionId) {
      await _documentsDao.deleteDocument(documentId);
      // Cascade DB tự xoá chunks + vectors
    } else {
      await _refsDao.detachDocument(sessionId, documentId);
    }
  }

  /// Có file nào đang pending hoặc processing không.
  bool hasProcessingFiles(List<SessionFileItem> files) {
    return files.any(
      (f) =>
          f.status == IndexStatus.processing ||
          f.status == IndexStatus.pending,
    );
  }

  @override
  Future<void> close() async {
    await _dbSubscription?.cancel();
    await _resultSubscription?.cancel();
    await _stateSubscription?.cancel();
    super.close();
  }
}