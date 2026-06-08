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
  final double progress;
  const KnowledgeIndexing({
    required this.documentId,
    required this.progress,
  });

  @override
  List<Object?> get props => [documentId, progress];
}

class KnowledgeError extends KnowledgeState {
  final String message;
  const KnowledgeError(this.message);

  @override
  List<Object?> get props => [message];
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
    try {
      emit(const KnowledgeLoading());
      await _documentRepository.importDocument(event.filePath);
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      if (e is AppException) {
        emit(KnowledgeError(e.message));
      } else {
        emit(KnowledgeError(e.toString()));
      }
    }
  }

  Future<void> _onDocumentDeleteRequested(
    DocumentDeleteRequested event,
    Emitter<KnowledgeState> emit,
  ) async {
    try {
      await _documentRepository.deleteDocument(event.id);
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      emit(KnowledgeError(e.toString()));
    }
  }

  Future<void> _onDocumentReindexRequested(
    DocumentReindexRequested event,
    Emitter<KnowledgeState> emit,
  ) async {
    try {
      emit(const KnowledgeLoading());
      await _documentRepository.reindexDocument(event.id);
      final documents = await _documentRepository.getAllDocuments();
      emit(KnowledgeLoaded(documents));
    } catch (e) {
      emit(KnowledgeError(e.toString()));
    }
  }
}