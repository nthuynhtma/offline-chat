import 'dart:io';
import 'dart:math';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:offline_chat/core/errors/app_exception.dart';

abstract interface class GeckoService {
  /// Load Gecko TFLite model
  Future<void> initialize(String modelPath);

  bool get isReady;

  Future<void> dispose();

  /// Embed một đoạn text → vector 768 chiều
  Future<List<double>> embed(String text);

  /// Embed nhiều đoạn cùng lúc (batch)
  Future<List<List<double>>> embedBatch(List<String> texts);
}

/// TensorFlow Lite implementation of Gecko embedding service.
///
/// Uses the Gecko 110M embedding model to convert text into
/// 768-dimensional vectors for semantic search.
class GeckoServiceImpl implements GeckoService {
  Interpreter? _interpreter;

  @override
  bool get isReady => _interpreter != null;

  @override
  Future<void> initialize(String modelPath) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      throw const ModelNotLoadedException();
    }
    try {
      _interpreter = await Interpreter.fromFile(file);
    } catch (e) {
      throw EmbeddingException('Failed to load Gecko model: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }

  @override
  Future<List<double>> embed(String text) async {
    final results = await embedBatch([text]);
    return results.first;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw const ModelNotLoadedException();
    }

    try {
      // Gecko 110M input: tokenized strings → output: float32[768]
      // The TFLite model accepts raw strings and tokenizes internally
      final input = texts.map((t) => [t]).toList();
      final output = List.generate(
        texts.length,
        (_) => List<double>.filled(768, 0.0),
      );

      interpreter.run(input, output);

      // Normalize vectors if not already normalized
      final normalized = <List<double>>[];
      for (final vec in output) {
        double norm = 0;
        for (final v in vec) {
          norm += v * v;
        }
        norm = sqrt(norm);
        if (norm > 0) {
          normalized.add(vec.map((v) => v / norm).toList());
        } else {
          normalized.add(vec);
        }
      }

      return normalized;
    } catch (e) {
      throw EmbeddingException('Embedding failed: $e');
    }
  }
}