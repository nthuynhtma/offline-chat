import 'dart:math';

abstract interface class ChunkingService {
  /// Chia text thành chunks với sliding window
  /// [chunkSize] tính theo xấp xỉ token (~4 ký tự = 1 token)
  /// [overlap] số token chồng lặp giữa 2 chunk liền kề
  List<String> chunk(
    String text, {
    int chunkSize = 500,
    int overlap = 100,
  });
}

/// Implementation of ChunkingService with sliding window approach.
///
/// Uses character-based approximation: 1 token ≈ 4 characters.
/// Attempts to split at word boundaries for cleaner chunks.
class ChunkingServiceImpl implements ChunkingService {
  @override
  List<String> chunk(
    String text, {
    int chunkSize = 500,
    int overlap = 100,
  }) {
    if (text.isEmpty) return [];

    // Xấp xỉ: 1 token ≈ 4 ký tự (tiếng Anh)
    // Với tiếng Việt dùng 2 ký tự/token (mixed mode dùng 3)
    const int charsPerToken = 4;
    final charSize = chunkSize * charsPerToken;
    final charOverlap = overlap * charsPerToken;
    final step = charSize - charOverlap;

    if (text.length <= charSize) return [text.trim()];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = min(start + charSize, text.length);

      // Cố tìm word boundary
      if (end < text.length) {
        final nextSpace = text.indexOf(' ', end - 50);
        if (nextSpace != -1 && nextSpace < end + 50) {
          end = nextSpace;
        }
      }

      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);

      start += step;
      if (start >= text.length) break;
    }

    return chunks;
  }
}