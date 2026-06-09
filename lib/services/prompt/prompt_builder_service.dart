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
    buffer.writeln(
        'You are a helpful AI assistant. Answer clearly and concisely.');
    buffer.writeln('Answer in the same language as the user\'s question.');

    if (context.relevantChunks.isNotEmpty) {
      buffer.writeln('\nRelevant context from documents:');
      log_util.log.d('🔨 [PromptBuilder] Thêm ${context.relevantChunks.length} chunks vào prompt');
      for (int i = 0; i < context.relevantChunks.length; i++) {
        buffer.writeln('[${i + 1}] ${context.relevantChunks[i].chunkText}');
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
    log_util.log.d('🔨 [PromptBuilder] Thêm ${context.history.length} history turns vào prompt');
    for (final msg in context.history) {
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
