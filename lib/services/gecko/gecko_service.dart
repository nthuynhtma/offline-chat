import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:offline_chat/core/errors/app_exception.dart';

abstract interface class GeckoService {
  /// Đăng ký model + tokenizer với flutter_gemma.
  /// Gọi 1 lần sau khi cả 2 file đã được download.
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  });

  /// Initialize Gecko embedding model via flutter_gemma.
  /// Cần gọi [registerModel] trước.
  Future<void> initialize();

  bool get isReady;

  Future<void> dispose();

  /// Embed một đoạn text → vector 768 chiều (query mode)
  Future<List<double>> embed(String text);

  /// Embed nhiều đoạn cùng lúc (batch) — document mode
  Future<List<List<double>>> embedBatch(List<String> texts);
}

/// Implementation using flutter_gemma's built-in EmbeddingModel API.
///
/// Uses `FlutterGemma.getActiveEmbedder()` to obtain the embedding model
/// (Gecko 110M or EmbeddingGemma), which handles tokenization, inference,
/// and normalization internally. No raw TFLite [`Interpreter`] needed.
class GeckoServiceImpl implements GeckoService {
  EmbeddingModel? _embeddingModel;
  bool _registered = false;

  @override
  bool get isReady => _embeddingModel != null;

  @override
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    if (_registered) return;

    try {
      await FlutterGemma.installEmbedder()
          .modelFromFile(modelPath)
          .tokenizerFromFile(tokenizerPath)
          .install();
      _registered = true;
    } catch (e) {
      throw EmbeddingException('Failed to register embedding model: $e');
    }
  }

  @override
  Future<void> initialize() async {
    if (_embeddingModel != null) return;

    try {
      _embeddingModel = await FlutterGemma.getActiveEmbedder();
    } catch (e) {
      throw EmbeddingException('Failed to initialize embedding model: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await _embeddingModel?.close();
    _embeddingModel = null;
  }

  @override
  Future<List<double>> embed(String text) async {
    final model = _embeddingModel;
    if (model == null) throw const ModelNotLoadedException();

    try {
      return await model.generateEmbedding(
        text,
        taskType: TaskType.retrievalQuery,
      );
    } catch (e) {
      throw EmbeddingException('Embedding failed: $e');
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final model = _embeddingModel;
    if (model == null) throw const ModelNotLoadedException();

    try {
      return await model.generateEmbeddings(
        texts,
        taskType: TaskType.retrievalDocument,
      );
    } catch (e) {
      throw EmbeddingException('Embedding batch failed: $e');
    }
  }
}