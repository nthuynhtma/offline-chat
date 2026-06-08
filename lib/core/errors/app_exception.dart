sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);
}

class ModelNotLoadedException extends AppException {
  const ModelNotLoadedException()
      : super('AI model chưa được tải. Vui lòng tải model trước.');
}

class InsufficientMemoryException extends AppException {
  final int requiredMB;
  const InsufficientMemoryException(this.requiredMB)
      : super('Không đủ RAM. Cần ít nhất $requiredMB MB trống.');
}

class DocumentParseException extends AppException {
  const DocumentParseException(String msg) : super(msg);
}

class EmbeddingException extends AppException {
  const EmbeddingException(String msg) : super(msg);
}

class StorageException extends AppException {
  const StorageException(String msg) : super(msg);
}