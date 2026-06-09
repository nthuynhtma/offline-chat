import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/errors/app_exception.dart';
import 'package:offline_chat/features/knowledge/models/document_model.dart';
import 'package:offline_chat/features/knowledge/repositories/document_repository.dart';

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
  // FIX #5: Giữ documents khi lỗi để UI không mất danh sách
  final List<DocumentModel> documents;
  const KnowledgeError(this.message, {this.documents = const []});

  @override
  List<Object?> get props => [message, documents];
}

// Bloc
class KnowledgeBloc extends Bloc<KnowledgeEvent, KnowledgeState> {
  final DocumentRepository _documentRepository;

  KnowledgeBloc(this._documentRepository) : super(const KnowledgeInitial()) {
    on<DocumentsLoaded>(_onDocumentsLoaded);
    on<DocumentImportRequested>(_onDocumentImportRequested);
    on<DocumentDeleteRequested>(_onDocumentDeleteRequested);
    on<DocumentReindexRequested>(_onDocumentReindexRequested);
  }

  Future<void> _onDocumentsLoaded(
    DocumentsLoaded event,
    Emitter<KnowledgeState> emit,
  ) async {
    emit(const KnowledgeLoading());
    try {
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

    // FIX #5: Dùng try/finally để đảm bảo LUÔN thoát khỏi KnowledgeIndexing
    // dù import thành công hay thất bại
    try {
      await _documentRepository.importDocumentWithProgress(
        event.filePath,
        onProgress: (documentId, progress) {
          // Chỉ emit Indexing khi chưa hoàn tất (< 1.0)
          // Khi progress == 1.0 không emit ở đây — để finally xử lý
          if (progress < 1.0) {
            emit(KnowledgeIndexing(
              documentId: documentId,
              documentName: fileName,
              progress: progress,
            ));
          }
        },
      );

      // Import thành công: load lại danh sách
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      // FIX #5: Khi lỗi load lại documents (có thể rỗng nếu DB lỗi)
      // Không để state kẹt tại KnowledgeIndexing
      List<DocumentModel> existingDocs = [];
      try {
        existingDocs = await _documentRepository.getAllDocuments();
      } catch (_) {
        // Nếu cả getAllDocuments cũng lỗi thì dùng danh sách rỗng
      }

      final message = e is AppException ? e.message : e.toString();
      emit(KnowledgeError(message, documents: existingDocs));
    }
  }

  Future<void> _onDocumentDeleteRequested(
    DocumentDeleteRequested event,
    Emitter<KnowledgeState> emit,
  ) async {
    // Lưu lại documents hiện tại để rollback nếu lỗi
    final currentDocs = state is KnowledgeLoaded
        ? (state as KnowledgeLoaded).documents
        : <DocumentModel>[];

    try {
      await _documentRepository.deleteDocument(event.id);
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      // FIX: Trả về documents cũ khi delete lỗi, không mất UI
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
}
