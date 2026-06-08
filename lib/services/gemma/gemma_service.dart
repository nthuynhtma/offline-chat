import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_chat/core/errors/app_exception.dart';

abstract interface class GemmaService {
  /// Initialize Gemma model.
  /// [modelPath] is not needed when using FlutterGemma API (auto-detected),
  /// but kept for backward compatibility with the contract.
  Future<void> initialize({String? modelPath, int maxTokens = 1024});
  bool get isReady;
  Future<void> dispose();
  Stream<String> generateStream(String prompt);
  Future<String> generate(String prompt);
}

/// Implementation wrapping flutter_gemma package v0.13.x modern API.
///
/// Uses the FlutterGemma facade:
/// - `FlutterGemma.getActiveModel()` to get InferenceModel
/// - `InferenceModel.createSession()` to create a session
///
/// Note: Due to abstract interface nature, dynamic dispatch is used
/// for methods that may vary between implementations.
/// TODO: Update with concrete type info when available.
class GemmaServiceImpl implements GemmaService {
  InferenceModel? _model;

  @override
  bool get isReady => _model != null;

  @override
  Future<void> initialize({String? modelPath, int maxTokens = 1024}) async {
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.gpu,
      );
    } catch (e) {
      if (e is StateError || e is ArgumentError) {
        throw const ModelNotLoadedException();
      }
      rethrow;
    }
  }

  @override
  Stream<String> generateStream(String prompt) async* {
    if (_model == null) throw const ModelNotLoadedException();
    // ignore: avoid_dynamic_calls
    final session = await (_model as dynamic).createSession();
    try {
      // ignore: avoid_dynamic_calls
      await for (final response in session.getResponseAsync(prompt)) {
        String text;
        if (response is String) {
          text = response;
        } else {
          // ignore: avoid_dynamic_calls
          text = response.text as String? ?? response.toString();
        }
        yield text;
      }
    } finally {
      // ignore: avoid_dynamic_calls
      session.close();
    }
  }

  @override
  Future<String> generate(String prompt) async {
    if (_model == null) throw const ModelNotLoadedException();
    // ignore: avoid_dynamic_calls
    final session = await (_model as dynamic).createSession();
    try {
      // ignore: avoid_dynamic_calls
      final response = await session.getResponse(prompt);
      if (response is String) {
        return response;
      }
      // ignore: avoid_dynamic_calls
      return (response.text as String?) ?? response.toString();
    } finally {
      // ignore: avoid_dynamic_calls
      session.close();
    }
  }

  @override
  Future<void> dispose() async {
    _model = null;
  }
}