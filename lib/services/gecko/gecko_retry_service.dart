import 'package:offline_chat/services/gecko/gecko_service.dart';

/// Wrapper cho GeckoService với retry logic.
///
/// Tự động retry khi embed/embedBatch thất bại (tối đa 3 lần).
class GeckoRetryService implements GeckoService {
  final GeckoService _inner;
  final int maxRetries;

  GeckoRetryService(this._inner, {this.maxRetries = 3});

  @override
  bool get isReady => _inner.isReady;

  @override
  Future<void> registerModel({
    required String modelPath,
    required String tokenizerPath,
  }) =>
      _inner.registerModel(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
      );

  @override
  Future<void> initialize() =>
      _inner.initialize();

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Future<List<double>> embed(String text) => _retry(
        () => _inner.embed(text),
      );

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) => _retry(
        () => _inner.embedBatch(texts),
      );

  /// Retry với exponential backoff
  Future<T> _retry<T>(Future<T> Function() fn) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) rethrow;
        // Exponential backoff: 1s, 2s, 4s
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }
}