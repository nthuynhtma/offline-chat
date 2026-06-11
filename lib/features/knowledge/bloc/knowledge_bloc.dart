import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/features/knowledge/models/document_model.dart';
import 'package:offline_chat/features/knowledge/repositories/document_repository.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';

// Events
sealed class KnowledgeEvent extends Equatable {
  const KnowledgeEvent();

  @override
  List<Object?> get props => [];
}

class DocumentsLoaded extends KnowledgeEvent {
  const DocumentsLoaded();
}

class DocumentImportRequested extends KnowledgeEvent {
  final String filePath;
  const DocumentImportRequested(this.filePath);

  @override
  List<Object?> get props => [filePath];
}

class DocumentDeleteRequested extends KnowledgeEvent {
  final String id;
  const DocumentDeleteRequested(this.id);

  @override
  List<Object?> get props => [id];
}

class DocumentReindexRequested extends KnowledgeEvent {
  final String id;
  const DocumentReindexRequested(this.id);

  @override
  List<Object?> get props => [id];
}

/// Internal: documents changed from DB watch stream.
class _DocumentsChanged extends KnowledgeEvent {
  final List<DocumentModel> documents;
  const _DocumentsChanged(this.documents);

  @override
  List<Object?> get props => [documents];
}

/// Internal: documents watch stream error.
class _DocumentsWatchFailed extends KnowledgeEvent {
  final Object error;
  const _DocumentsWatchFailed(this.error);

  @override
  List<Object?> get props => [error];
}

/// Internal: queue result (success or fail).
class _QueueResultArrived extends KnowledgeEvent {
  final DocumentUploadResult result;
  const _QueueResultArrived(this.result);

  @override
  List<Object?> get props => [result];
}

// States
sealed class KnowledgeState extends Equatable {
  const KnowledgeState();

  @override
  List<Object?> get props => [];
}

class KnowledgeInitial extends KnowledgeState {
  const KnowledgeInitial();
}

class KnowledgeLoading extends KnowledgeState {
  const KnowledgeLoading();
}

class KnowledgeLoaded extends KnowledgeState {
  final List<DocumentModel> documents;
  const KnowledgeLoaded(this.documents);

  @override
  List<Object?> get props => [documents];
}

class KnowledgeIndexing extends KnowledgeState {
  final String documentId;
  final String documentName;
  final double progress;
  const KnowledgeIndexing({
    required this.documentId,
    required this.documentName,
    required this.progress,
  });

  @override
  List<Object?> get props => [documentId, documentName, progress];
}

class KnowledgeError extends KnowledgeState {
  final String message;
  final List<DocumentModel> documents;
  const KnowledgeError(this.message, {this.documents = const []});

  @override
  List<Object?> get props => [message, documents];
}

// Bloc
class KnowledgeBloc extends Bloc<KnowledgeEvent, KnowledgeState> {
  final DocumentRepository _documentRepository;
  final DocumentUploadQueue _uploadQueue;

  StreamSubscription<List<DocumentModel>>? _watchSubscription;
  StreamSubscription<DocumentUploadResult>? _queueResultSubscription;

  KnowledgeBloc(
    this._documentRepository,
    this._uploadQueue,
  ) : super(const KnowledgeInitial()) {
    on<DocumentsLoaded>(_onDocumentsLoaded);
    on<DocumentImportRequested>(_onDocumentImportRequested);
    on<DocumentDeleteRequested>(_onDocumentDeleteRequested);
    on<DocumentReindexRequested>(_onDocumentReindexRequested);
    on<_DocumentsChanged>(_onDocumentsChanged);
    on<_DocumentsWatchFailed>(_onDocumentsWatchFailed);
    on<_QueueResultArrived>(_onQueueResultArrived);

    // Subscribe queue results
    _queueResultSubscription = _uploadQueue.resultStream.listen(
      (result) => add(_QueueResultArrived(result)),
    );
  }

  Future<void> _onDocumentsLoaded(
    DocumentsLoaded event,
    Emitter<KnowledgeState> emit,
  ) async {
    emit(const KnowledgeLoading());
    try {
      await _watchSubscription?.cancel();
      _watchSubscription = _documentRepository.watchAllDocuments().listen(
            (documents) => add(_DocumentsChanged(documents)),
            onError: (e) => add(_DocumentsWatchFailed(e)),
          );

      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      emit(KnowledgeError(e.toString()));
    }
  }

  Future<void> _onDocumentImportRequested(
    DocumentImportRequested event,
    Emitter<KnowledgeState> emit,
  ) async {
    final fileName = event.filePath.split('/').last;

    try {
      // importDocument now: copy file + insert metadata + enqueue → returns immediately
      final doc = await _documentRepository.importDocument(event.filePath);

      // Show indexing state immediately
      emit(KnowledgeIndexing(
        documentId: doc.id,
        documentName: fileName,
        progress: 0.0,
      ));
    } catch (e) {
      List<DocumentModel> existingDocs = [];
      try {
        existingDocs = await _documentRepository.getAllDocuments();
      } catch (_) {}

      final message = e is AppException ? e.message : e.toString();
      emit(KnowledgeError('Không thể import "$fileName": $message',
          documents: existingDocs));
    }
  }

  Future<void> _onDocumentDeleteRequested(
    DocumentDeleteRequested event,
    Emitter<KnowledgeState> emit,
  ) async {
    final currentDocs = state is KnowledgeLoaded
        ? (state as KnowledgeLoaded).documents
        : <DocumentModel>[];

    try {
      await _documentRepository.deleteDocument(event.id);
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      emit(KnowledgeError(e.toString(), documents: currentDocs));
    }
  }

  Future<void> _onDocumentReindexRequested(
    DocumentReindexRequested event,
    Emitter<KnowledgeState> emit,
  ) async {
    final currentDocs = state is KnowledgeLoaded
        ? (state as KnowledgeLoaded).documents
        : <DocumentModel>[];

    try {
      emit(const KnowledgeLoading());
      await _documentRepository.reindexDocument(event.id);
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      emit(KnowledgeError(e.toString(), documents: currentDocs));
    }
  }

  void _onDocumentsChanged(
    _DocumentsChanged event,
    Emitter<KnowledgeState> emit,
  ) {
    final currentState = state;

    if (currentState is KnowledgeIndexing) {
      // Đang indexing — cập nhật progress từ DocumentModel.progress trong DB
      final indexingDoc = event.documents
          .where((d) => d.id == currentState.documentId)
          .firstOrNull;

      if (indexingDoc != null) {
        emit(KnowledgeIndexing(
          documentId: currentState.documentId,
          documentName: currentState.documentName,
          progress: indexingDoc.progress,
        ));
      }
      // Không emit loaded — giữ state indexing
      return;
    }

    emit(KnowledgeLoaded(event.documents));
  }

  Future<void> _onDocumentsWatchFailed(
    _DocumentsWatchFailed event,
    Emitter<KnowledgeState> emit,
  ) async {
    List<DocumentModel> existingDocs = [];
    try {
      existingDocs = await _documentRepository.getAllDocuments();
    } catch (_) {}
    emit(KnowledgeError(event.error.toString(), documents: existingDocs));
  }

  /// Xử lý kết quả từ queue khi job hoàn thành hoặc fail.
  Future<void> _onQueueResultArrived(
    _QueueResultArrived event,
    Emitter<KnowledgeState> emit,
  ) async {
    final result = event.result;

    if (result.success) {
      // Reload documents — DB stream sẽ tự emit KnowledgeLoaded
      // Nhưng nếu đang ở KnowledgeIndexing, cần thoát khỏi nó
      try {
        final documents = await _documentRepository.getAllDocuments();
        emit(KnowledgeLoaded(documents));
      } catch (e) {
        emit(KnowledgeError(e.toString()));
      }
    } else {
      // Queue processing failed — show error
      List<DocumentModel> existingDocs = [];
      try {
        existingDocs = await _documentRepository.getAllDocuments();
      } catch (_) {}

      emit(KnowledgeError(
        result.error ?? 'Indexing thất bại',
        documents: existingDocs,
      ));
    }
  }

  @override
  Future<void> close() async {
    await _watchSubscription?.cancel();
    await _queueResultSubscription?.cancel();
    return super.close();
  }
}