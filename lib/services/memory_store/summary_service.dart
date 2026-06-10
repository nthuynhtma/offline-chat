import 'dart:async';

import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;
import 'package:offline_chat/core/utils/token_estimator.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/memory_store/memory_store_service.dart';

/// Logic summarize conversation + extract user memory.
/// Sử dụng Gemma legacy `generate()` để không ảnh hưởng session chính.
class SummaryService {
  final GemmaService _gemmaService;
  final MemoryStoreService _memoryStore;

  SummaryService(this._gemmaService, this._memoryStore);

  /// Incremental summary: lấy old summary (nếu có) + new messages → tạo summary mới.
  /// Timeout 30s, fallback silent nếu fail.
  Future<String?> incrementalSummarize({
    required String? oldSummary,
    required List<MessageModel> newMessages,
  }) async {
    if (newMessages.isEmpty) return oldSummary;

    try {
      final prompt = _buildIncrementalPrompt(oldSummary, newMessages);

      final result = await _gemmaService
          .generate(prompt)
          .timeout(
            const Duration(seconds: kSummaryTimeoutSeconds),
          );

      final summary = result.trim();
      log_util.log.i('📝 [Summary] Generated: ${summary.length} chars (~${estimateTokens(summary)} tok)');

      return summary.isNotEmpty ? summary : oldSummary;
    } catch (e) {
      log_util.log.w('⚠️ [Summary] Failed (timeout/error): $e — keeping old summary');
      return oldSummary;
    }
  }

  /// Extract persistent user memory từ recent messages.
  /// Dùng Gemma để rút ra facts about user: project info, preferences, settings.
  /// Upsert key-value vào UserMemory table qua MemoryStore.
  Future<void> extractUserMemory(List<MessageModel> messages) async {
    if (!_gemmaService.isReady) return;

    try {
      final prompt = _buildMemoryExtractionPrompt(messages);

      final result = await _gemmaService
          .generate(prompt)
          .timeout(
            const Duration(seconds: kSummaryTimeoutSeconds),
          );

      final memories = _parseMemoryExtraction(result);
      for (final entry in memories.entries) {
        final parts = entry.key.split('.');
        if (parts.length == 2) {
          await _memoryStore.upsertUserMemory(parts[0], parts[1], entry.value);
        }
      }
      log_util.log.i('🧠 [MemoryExtract] Extracted ${memories.length} facts');
    } catch (e) {
      log_util.log.w('⚠️ [MemoryExtract] Failed: $e');
    }
  }

  // ─── Private prompt builders ─────────────────────────────────────────

  String _buildIncrementalPrompt(String? oldSummary, List<MessageModel> newMessages) {
    final conversation = newMessages.map((m) => '${m.role.name}: ${m.content}').join('\n');

    if (oldSummary != null && oldSummary.isNotEmpty) {
      return '''
[SYSTEM]
You are a conversation summarizer for an offline AI assistant app.
Update the summary below with the new conversation. Keep it concise, factual, in bullet points.
Max ${(kGemmaMaxTokens * kSummaryBudgetRatio).round()} tokens. Write in Vietnamese.

[PREVIOUS SUMMARY]
$oldSummary

[NEW CONVERSATION]
$conversation

[UPDATED SUMMARY]
''';
    }

    return '''
[SYSTEM]
You are a conversation summarizer for an offline AI assistant app.
Summarize the conversation concisely. Keep it factual, in bullet points.
Max ${(kGemmaMaxTokens * kSummaryBudgetRatio).round()} tokens. Write in Vietnamese.

[CONVERSATION]
$conversation

[SUMMARY]
''';
  }

  String _buildMemoryExtractionPrompt(List<MessageModel> messages) {
    final conversation = messages.map((m) => '${m.role.name}: ${m.content}').join('\n');

    return '''
[SYSTEM]
Extract persistent user facts from this conversation.
Output in format:
namespace.key=value
One per line. Max 10 items.

Examples:
project.type=Offline AI Chatbot
project.framework=Flutter
user.language=Vietnamese

[CONVERSATION]
$conversation

[FACTS]
''';
  }

  Map<String, String> _parseMemoryExtraction(String raw) {
    final result = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.contains('=')) continue;
      final parts = trimmed.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim().toLowerCase();
        final value = parts.sublist(1).join('=').trim();
        // Chỉ chấp nhận namespace.key format
        if (key.contains('.') && key.split('.').length == 2 && value.isNotEmpty) {
          result[key] = value;
        }
      }
    }
    return result;
  }
}