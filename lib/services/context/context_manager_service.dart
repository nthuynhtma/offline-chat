import 'dart:async';

import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
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

/// Local BuiltContext for backward compatibility.
/// Do NOT use in new code — replaced by PromptBuilder + RagService.
class BuiltContext {
  final String question;
  final List<SearchResult> relevantChunks;
  final List<MessageModel> history;
  final bool historyWasTrimmed;
  final int estimatedTokens;
  final String? summary;

  const BuiltContext({
    required this.question,
    required this.relevantChunks,
    required this.history,
    required this.historyWasTrimmed,
    required this.estimatedTokens,
    this.summary,
  });
}

/// @Deprecated Replaced by Session API + MemoryStoreService + SummaryService.
/// Kept for backward compatibility, will be removed in a future cleanup.
@Deprecated('Use MemoryStoreService + SummaryService + Session API instead')
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
      // 1. Kiểm tra cache trước — không block nếu chưa có
      final cacheKey = '${sessionId}_${history.length}_${history.lastOrNull?.id}';
      final cached = _summaryCache[cacheKey];

      if (cached != null) {
        // Có cache → dùng ngay, không cần đợi summarize
        summary = cached.summary;
        // Giữ lại N messages gần nhất
        if (history.length > recentMessagesAfterSummary) {
          history = history.sublist(history.length - recentMessagesAfterSummary);
        }
        totalHistoryTokens = 0;
        for (final msg in history) {
          totalHistoryTokens += _estimateTokens(msg.content);
        }
      } else {
        // Chưa có cache → chạy summarize background, không block
        // Dùng tạm trim history cho request hiện tại
        unawaited(_summarizeHistory(history, sessionId));
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

  /// Summarize lịch sử chat bằng Gemma — chạy background, không blocking.
  /// Kết quả được lưu vào cache và dùng cho request tiếp theo.
  Future<void> _summarizeHistory(
    List<MessageModel> history,
    String sessionId,
  ) async {
    final cacheKey = '${sessionId}_${history.length}_${history.lastOrNull?.id}';
    // Cache hit → không cần chạy lại
    if (_summaryCache.containsKey(cacheKey)) return;

    try {
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
    } catch (_) {
      // Silent fail — summarize background fail không ảnh hưởng request chính
    }
  }

  int _estimateTokens(String text) {
    return (text.length / 3).ceil();
  }
}
