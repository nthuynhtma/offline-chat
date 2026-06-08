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
  static const int summaryBudget = 500; // Tokens cho summary
  static const int summaryThreshold = 3000; // Nếu history > 3000 tokens → summarize

  Future<BuiltContext> buildContext({
    required String question,
    required String sessionId,
    required List<SearchResult> ragResults,
  }) async {
    var history =
        await _messageRepo.getRecentMessages(sessionId, limit: 20);

    bool historyTrimmed = false;
    String? summary;
    int estimatedTokens = _estimateTokens(question);

    // Trim RAG if over budget
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

    // Tính tổng tokens của history
    int totalHistoryTokens = 0;
    for (final msg in history) {
      totalHistoryTokens += _estimateTokens(msg.content);
    }

    // Nếu history quá dài → summarize
    if (totalHistoryTokens > summaryThreshold && _gemmaService != null && _gemmaService!.isReady) {
      try {
        summary = await _summarizeHistory(history, sessionId);
        // Dùng summary thay cho history (chỉ giữ lại messages gần nhất)
        history = history.length > 4 ? history.sublist(history.length - 4) : history;
        totalHistoryTokens = summaryBudget;
      } catch (_) {
        // Graceful degradation: fallback về trim thường nếu summarize fail
        summary = null;
      }
    }

    if (summary != null) {
      estimatedTokens += summaryBudget;
    } else if (totalHistoryTokens + estimatedTokens > (historyBudget + questionBudget)) {
      // Trim history if over budget (fallback)
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
      estimatedTokens += usedTokens;
    } else {
      estimatedTokens += totalHistoryTokens;
    }

    return BuiltContext(
      question: question,
      relevantChunks: trimmedRag,
      history: history,
      historyWasTrimmed: historyTrimmed,
      estimatedTokens: estimatedTokens + usedRagTokens,
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

    final prompt = buffer.toString();
    final response = await _gemmaService!.generate(prompt);

    // Cache summary
    _summaryCache[cacheKey] = _SummaryCache(
      summary: response.trim(),
      estimatedTokens: _estimateTokens(response),
      createdAt: DateTime.now(),
    );

    // Giới hạn cache size (giữ tối đa 10 entries)
    if (_summaryCache.length > 10) {
      final oldestKey = _summaryCache.entries
          .reduce((a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b)
          .key;
      _summaryCache.remove(oldestKey);
    }

    return response.trim();
  }

  int _estimateTokens(String text) {
    return (text.length / 3).ceil();
  }
}
