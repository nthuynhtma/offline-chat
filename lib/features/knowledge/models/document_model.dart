class DocumentModel {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final int chunkCount;
  final String mimeType;
  final DateTime createdAt;

  const DocumentModel({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.chunkCount,
    required this.mimeType,
    required this.createdAt,
  });

  factory DocumentModel.fromDbRow(dynamic row) => DocumentModel(
        id: row.id,
        name: row.name,
        path: row.path,
        sizeBytes: row.sizeBytes,
        chunkCount: row.chunkCount,
        mimeType: row.mimeType,
        createdAt: row.createdAt,
      );

  DocumentModel copyWith({int? chunkCount}) => DocumentModel(
        id: id,
        name: name,
        path: path,
        sizeBytes: sizeBytes,
        chunkCount: chunkCount ?? this.chunkCount,
        mimeType: mimeType,
        createdAt: createdAt,
      );
}