import 'package:offline_chat/services/rag/rag_context.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

/// Interface cho PromptBuilder.
///
/// Chịu trách nhiệm format prompt cho Session-based API:
/// - `buildSystemInstruction()`: System prompt + User memories + Session summary
///   → Dùng cho `createSession()` (KHÔNG chứa history)
/// - `buildTurnPayload()`: RAG context + Current question
///   → Dùng cho `generateWithSession()` (KHÔNG chứa system/history)
abstract interface class PromptBuilder {
  /// Build system instruction cho `createSession()`.
  /// Chứa: system prompt + user memories + session summary.
  /// KHÔNG chứa history (history được replay qua `addHistoryMessage`).
  Future<String> buildSystemInstruction({
    String? sessionSummary,
    List<UserMemory>? userMemories,
  });

  /// Build turn payload cho `generateWithSession()`.
  /// Chứa: RAG context (nếu có) + current question.
  /// KHÔNG chứa system prompt, history.
  Future<String> buildTurnPayload({
    required String question,
    required RagContext ragContext,
  });
}

/// Một user memory entry đơn giản.
class UserMemory {
  final String namespace;
  final String key;
  final String value;

  const UserMemory({
    required this.namespace,
    required this.key,
    required this.value,
  });
}

final class PromptBuilderImpl implements PromptBuilder {
  @override
  Future<String> buildSystemInstruction({
    String? sessionSummary,
    List<UserMemory>? userMemories,
  }) async {
    log_util.log.d('🔨 [PromptBuilder] VERSION=session_api_v1 Build system instruction...');

    final buffer = StringBuffer();

    // ─── System turn ──────────────────────────────────────────────
    buffer.writeln('<start_of_turn>system');
    buffer.writeln('''
    You are AgriAI, an agricultural assistant running completely offline on a mobile device.

    Your primary purpose is to help users with:
    - Crop cultivation and management
    - Soil health and fertilization
    - Pest and disease identification
    - Irrigation and water management
    - Livestock and poultry farming
    - Agricultural best practices
    - Sustainable farming techniques

    Instructions:
    - Answer in the same language as the user.
    - Provide practical, clear, and actionable agricultural advice.
    - Prefer information from the provided document context when available.
    - If document context contains the answer, prioritize it over general knowledge.
    - If document context does not contain the answer, use your general agricultural knowledge.
    - If you are uncertain, clearly state your uncertainty instead of guessing.
    - Keep answers concise unless the user asks for more detail.
    - Explain agricultural terms in simple language.
    - Do not claim to have internet access, real-time data, weather data, or external services.
    - Remember that you operate completely offline on the user's mobile device.
    ''');

    // ─── User Memories (persona dài hạn) ─────────────────────────
    if (userMemories != null && userMemories.isNotEmpty) {
      buffer.writeln('\n=== User Memory ===');
      for (final mem in userMemories) {
        buffer.writeln('- ${mem.namespace}:${mem.key} → ${mem.value}');
      }
      log_util.log.d('🔨 [PromptBuilder] Đã thêm ${userMemories.length} user memories');
    }

    // ─── Session Summary (trạng thái cuộc hội thoại) ────────────
    if (sessionSummary != null && sessionSummary.isNotEmpty) {
      buffer.writeln('\n=== Session Summary ===');
      buffer.writeln(sessionSummary);
      log_util.log.d('🔨 [PromptBuilder] Đã thêm conversation summary (${sessionSummary.length} chars)');
    }

    buffer.writeln('<end_of_turn>');

    final result = buffer.toString();
    log_util.log.i('🔨 [PromptBuilder] System instruction built (${result.length} chars)');
    return result;
  }

  @override
  Future<String> buildTurnPayload({
    required String question,
    required RagContext ragContext,
  }) async {
    log_util.log.d('🔨 [PromptBuilder] VERSION=session_api_v1 Build turn payload...');

    final buffer = StringBuffer();

    // ─── RAG Context (sát question nhất — Gemma tập trung tốt hơn) ──
    if (ragContext.hasContext) {
      buffer.writeln('=== Reference Documents ===');
      log_util.log.d('🔨 [PromptBuilder] Thêm ${ragContext.chunks.length} chunks vào turn payload');

      for (int i = 0; i < ragContext.chunks.length; i++) {
        buffer.writeln('\n[Document ${i + 1}]');
        buffer.writeln(ragContext.chunks[i].chunkText);
      }
      buffer.writeln(); // Empty line before question
    } else {
      log_util.log.d('🔨 [PromptBuilder] Không có relevant chunks — chỉ gửi question');
    }

    // ─── Current question ──────────────────────────────────────────
    buffer.writeln('=== Current Question ===');
    buffer.writeln(question);

    final result = buffer.toString();
    log_util.log.i('🔨 [PromptBuilder] Turn payload built (${result.length} chars, hasRAG=${ragContext.hasContext})');
    return result;
  }
}