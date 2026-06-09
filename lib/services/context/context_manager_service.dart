import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

/// Tóm tắt lịch sử chat được cache
class _SummaryCache {
  final String summary;
  final int estimatedTokens;
  final DateTime createdAt;

  const _SummaryCache({
    required this.summary,
    required this.estimatedTokens,
    required this.createdAt,
  });
}

class ContextManagerService {
  final MessageRepository _messageRepo;
  final GemmaService? _gemmaService; // Optional để summarize

  /// Cache summary theo sessionId
  final Map<String, _SummaryCache> _summaryCache = {};

  ContextManagerService(this._messageRepo, [this._gemmaService]);

  static const int totalBudget = 8000;
  static const int ragBudget = 4000;
  static const int historyBudget = 3000;
  static const int questionBudget = 1000;
  static const int summaryBudget = 500;
  static const int summaryThreshold = 3000;
  // Số messages gần nhất giữ lại khi có summary
  static const int recentMessagesAfterSummary = 4;

  Future<BuiltContext> buildContext({
    required String question,
    required String sessionId,
    required List<SearchResult> ragResults,
  }) async {
    var history =
        await _messageRepo.getRecentMessages(sessionId, limit: 20);

    bool historyTrimmed = false;
    String? summary;

    // --- RAG budget trim ---
    int usedRagTokens = 0;
    final trimmedRag = <SearchResult>[];
    for (final result in ragResults) {
      final t = _estimateTokens(result.chunkText);
      if (usedRagTokens + t <= ragBudget) {
        trimmedRag.add(result);
        usedRagTokens += t;
      } else {
        break;
      }
    }

    // --- History token count ---
    int totalHistoryTokens = 0;
    for (final msg in history) {
      totalHistoryTokens += _estimateTokens(msg.content);
    }

    // --- Summarize nếu history quá dài ---
    if (totalHistoryTokens > summaryThreshold &&
        _gemmaService != null &&
        _gemmaService!.isReady) {
      try {
        summary = await _summarizeHistory(history, sessionId);
        // Giữ lại N messages gần nhất sau summary
        if (history.length > recentMessagesAfterSummary) {
          history = history.sublist(
              history.length - recentMessagesAfterSummary);
        }
        // FIX #7: Tính đúng tokens của history còn lại sau khi trim
        totalHistoryTokens = 0;
        for (final msg in history) {
          totalHistoryTokens += _estimateTokens(msg.content);
        }
      } catch (_) {
        summary = null;
        // totalHistoryTokens vẫn giữ giá trị gốc → fallback trim bên dưới
      }
    }

    // --- Trim history nếu không có summary và vẫn over budget ---
    if (summary == null &&
        totalHistoryTokens > historyBudget) {
      final trimmedHistory = <MessageModel>[];
      int usedTokens = 0;
      for (final msg in history.reversed) {
        final t = _estimateTokens(msg.content);
        if (usedTokens + t <= historyBudget) {
          trimmedHistory.insert(0, msg);
          usedTokens += t;
        } else {
          historyTrimmed = true;
          break;
        }
      }
      history = trimmedHistory;
      totalHistoryTokens = usedTokens;
    }

    // FIX #7: Tính estimatedTokens chính xác từng phần
    // question + history thực tế + summary (nếu có) + rag
    final questionTokens = _estimateTokens(question);
    final summaryTokens = summary != null ? summaryBudget : 0;
    final totalEstimated =
        questionTokens + totalHistoryTokens + summaryTokens + usedRagTokens;

    return BuiltContext(
      question: question,
      relevantChunks: trimmedRag,
      history: history,
      historyWasTrimmed: historyTrimmed,
      estimatedTokens: totalEstimated,
      summary: summary,
    );
  }

  /// Summarize lịch sử chat bằng Gemma
  Future<String> _summarizeHistory(
    List<MessageModel> history,
    String sessionId,
  ) async {
    // Kiểm tra cache
    final cacheKey = '${sessionId}_${history.length}_${history.lastOrNull?.id}';
    final cached = _summaryCache[cacheKey];
    if (cached != null) {
      return cached.summary;
    }

    // Xây dựng prompt summarize
    final buffer = StringBuffer();
    buffer.writeln('<start_of_turn>system');
    buffer.writeln(
      'Summarize the conversation history concisely in Vietnamese. '
      'Keep only the key information, topics discussed, and user preferences. '
      'Max 100 words.',
    );
    buffer.writeln('<end_of_turn>');
    buffer.writeln('<start_of_turn>user');
    buffer.writeln('Conversation history:');
    for (final msg in history) {
      buffer.writeln('${msg.role.name}: ${msg.content}');
    }
    buffer.writeln('<end_of_turn>');
    buffer.write('<start_of_turn>model\n');

    final response = await _gemmaService!.generate(buffer.toString());

    // Cache summary
    _summaryCache[cacheKey] = _SummaryCache(
      summary: response.trim(),
      estimatedTokens: _estimateTokens(response),
      createdAt: DateTime.now(),
    );

    // Giới hạn cache size (giữ tối đa 10 entries)
    if (_summaryCache.length > 10) {
      final oldestKey = _summaryCache.entries
          .reduce((a, b) =>
              a.value.createdAt.isBefore(b.value.createdAt) ? a : b)
          .key;
      _summaryCache.remove(oldestKey);
    }

    return response.trim();
  }

  int _estimateTokens(String text) {
    return (text.length / 3).ceil();
  }
}
