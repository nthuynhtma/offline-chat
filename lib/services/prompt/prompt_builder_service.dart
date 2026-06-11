import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/services/rag/rag_context.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

/// Interface cho PromptBuilder.
///
/// Chịu trách nhiệm format toàn bộ prompt từ các thành phần:
/// - System prompt
/// - User memories (cross-session knowledge)
/// - Session summary (conversation history đã summarize)
/// - History (recent messages)
/// - RAG context (document chunks — sát question nhất để Gemma tập trung)
/// - Question
abstract interface class PromptBuilder {
  /// Build prompt string hoàn chỉnh.
  Future<String> build({
    required String question,
    required RagContext ragContext,
    required List<MessageModel> history,
    String? sessionSummary,
    List<UserMemory> userMemories,
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
  Future<String> build({
    required String question,
    required RagContext ragContext,
    required List<MessageModel> history,
    String? sessionSummary,
    List<UserMemory>? userMemories,
  }) async {
    log_util.log.d('🔨 [PromptBuilder] Bắt đầu build prompt...');

    final buffer = StringBuffer();

    // ─── 1. System turn ──────────────────────────────────────────────
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

    // ─── 2. User Memories (persona dài hạn) ─────────────────────────
    if (userMemories != null && userMemories.isNotEmpty) {
      buffer.writeln('\n=== User Memory ===');
      for (final mem in userMemories) {
        buffer.writeln('- ${mem.namespace}:${mem.key} → ${mem.value}');
      }
      log_util.log.d('🔨 [PromptBuilder] Đã thêm ${userMemories.length} user memories');
    }

    // ─── 3. Session Summary (trạng thái cuộc hội thoại) ────────────
    if (sessionSummary != null && sessionSummary.isNotEmpty) {
      buffer.writeln('\n=== Session Summary ===');
      buffer.writeln(sessionSummary);
      log_util.log.d('🔨 [PromptBuilder] Đã thêm conversation summary (${sessionSummary.length} chars)');
    }

    buffer.writeln('<end_of_turn>');

    // ─── 4. Recent Conversation (ngữ cảnh gần) ──────────────────────
    // Bỏ qua message cuối cùng trong history nếu nó trùng với question
    // (vì message này sẽ được thêm riêng ở bước "Current question" bên dưới)
    final historyToInclude = (history.isNotEmpty &&
            history.last.role.name == 'user' &&
            history.last.content == question)
        ? history.sublist(0, history.length - 1)
        : history;

    if (historyToInclude.isNotEmpty) {
      buffer.writeln('=== Recent Conversation ===');
      log_util.log.d('🔨 [PromptBuilder] Thêm ${historyToInclude.length} history turns (bỏ qua ${history.length - historyToInclude.length} message cuối trùng với question)');
      for (final msg in historyToInclude) {
        buffer.writeln('<start_of_turn>${msg.role.name}');
        buffer.writeln(msg.content);
        buffer.writeln('<end_of_turn>');
      }
    } else {
      log_util.log.d('🔨 [PromptBuilder] Không có history turns');
    }

    // ─── 5. RAG Context (sát question nhất — Gemma tập trung tốt hơn) ──
    if (ragContext.hasContext) {
      buffer.writeln('\n=== Reference Documents ===');
      log_util.log.d('🔨 [PromptBuilder] Thêm ${ragContext.chunks.length} chunks vào prompt');

      for (int i = 0; i < ragContext.chunks.length; i++) {
        buffer.writeln('\n[Document ${i + 1}]');
        buffer.writeln(ragContext.chunks[i].chunkText);
      }
    } else {
      log_util.log.d('🔨 [PromptBuilder] Không có relevant chunks — bỏ qua RAG context');
    }

    // ─── 6. Current question ──────────────────────────────────────────
    buffer.writeln('\n=== Current Question ===');
    buffer.writeln('<start_of_turn>user');
    buffer.writeln(question);
    buffer.writeln('<end_of_turn>');
    buffer.write('<start_of_turn>model\n');

    final result = buffer.toString();
    log_util.log.i('🔨 [PromptBuilder] Hoàn tất build prompt (${result.length} chars):\n$result');
    return result;
  }
}