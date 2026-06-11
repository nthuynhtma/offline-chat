import 'package:offline_chat/core/constants/document_constants.dart';

class DocumentModel {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final int chunkCount;
  final String mimeType;
  final DateTime createdAt;
  final String? sessionId;
  final IndexStatus status;
  final double progress;
  final String? errorMessage;
  final int retryCount;
  final DateTime? lastProcessedAt;

  const DocumentModel({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.chunkCount,
    required this.mimeType,
    required this.createdAt,
    this.sessionId,
    this.status = IndexStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.retryCount = 0,
    this.lastProcessedAt,
  });

  factory DocumentModel.fromDbRow(dynamic row) => DocumentModel(
        id: row.id,
        name: row.name,
        path: row.path,
        sizeBytes: row.sizeBytes,
        chunkCount: row.chunkCount,
        mimeType: row.mimeType,
        createdAt: row.createdAt,
        sessionId: row.sessionId,
        status: IndexStatusX.fromInt(row.status),
        progress: row.progress,
        errorMessage: row.errorMessage,
        retryCount: row.retryCount,
        lastProcessedAt: row.lastProcessedAt,
      );

  DocumentModel copyWith({
    int? chunkCount,
    IndexStatus? status,
    double? progress,
    String? errorMessage,
    int? retryCount,
  }) =>
      DocumentModel(
        id: id,
        name: name,
        path: path,
        sizeBytes: sizeBytes,
        chunkCount: chunkCount ?? this.chunkCount,
        mimeType: mimeType,
        createdAt: createdAt,
        sessionId: sessionId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        errorMessage: errorMessage ?? this.errorMessage,
        retryCount: retryCount ?? this.retryCount,
        lastProcessedAt: lastProcessedAt,
      );
}
