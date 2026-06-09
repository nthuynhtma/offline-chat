import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

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

abstract interface class PromptBuilderService {
  String build(BuiltContext context);
}

class PromptBuilderServiceImpl implements PromptBuilderService {
  @override
  String build(BuiltContext context) {
    log_util.log.d('🔨 [PromptBuilder] Bắt đầu build prompt...');

    final buffer = StringBuffer();

    // System turn
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

    if (context.relevantChunks.isNotEmpty) {
      buffer.writeln('\nDocument Context (Highest Priority):');
      buffer.writeln('The following information comes from the user\'s agricultural documents.');
      buffer.writeln('Use this information as the primary source when answering.');
      buffer.writeln('If the answer can be found in the document context, do not ignore it.');
      buffer.writeln('If the document context is insufficient, then use your general agricultural knowledge.');

      log_util.log.d('🔨 [PromptBuilder] Thêm ${context.relevantChunks.length} chunks vào prompt');

      for (int i = 0; i < context.relevantChunks.length; i++) {
        buffer.writeln('\n[Document ${i + 1}]');
        buffer.writeln(context.relevantChunks[i].chunkText);
      }
    } else {
      log_util.log.d('🔨 [PromptBuilder] Không có relevant chunks — bỏ qua RAG context');
    }

    if (context.summary != null && context.summary!.isNotEmpty) {
      buffer.writeln('\nConversation summary (condensed history):');
      buffer.writeln(context.summary);
      log_util.log.d('🔨 [PromptBuilder] Đã thêm conversation summary (${context.summary!.length} chars)');
    } else {
      log_util.log.d('🔨 [PromptBuilder] Không có summary');
    }

    buffer.writeln('<end_of_turn>');

    // History turns
    // Bỏ qua message cuối cùng trong history nếu nó trùng với context.question
    // (vì message này sẽ được thêm riêng ở bước "Current question" bên dưới)
    final historyToInclude = (context.history.isNotEmpty &&
            context.history.last.role.name == 'user' &&
            context.history.last.content == context.question)
        ? context.history.sublist(0, context.history.length - 1)
        : context.history;

    log_util.log.d('🔨 [PromptBuilder] Thêm ${historyToInclude.length} history turns vào prompt (bỏ qua ${context.history.length - historyToInclude.length} message cuối trùng với question)');
    for (final msg in historyToInclude) {
      buffer.writeln('<start_of_turn>${msg.role.name}');
      buffer.writeln(msg.content);
      buffer.writeln('<end_of_turn>');
    }

    // Current question
    buffer.writeln('<start_of_turn>user');
    buffer.writeln(context.question);
    buffer.writeln('<end_of_turn>');
    buffer.write('<start_of_turn>model\n');

    final result = buffer.toString();
    log_util.log.d('🔨 [PromptBuilder] Hoàn tất build prompt (${result.length} chars)');
    return result;
  }
}
