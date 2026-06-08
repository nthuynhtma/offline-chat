import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/services/vectorstore/vector_store_service.dart';

class BuiltContext {
  final String question;
  final List<SearchResult> relevantChunks;
  final List<MessageModel> history;
  final bool historyWasTrimmed;
  final int estimatedTokens;

  const BuiltContext({
    required this.question,
    required this.relevantChunks,
    required this.history,
    required this.historyWasTrimmed,
    required this.estimatedTokens,
  });
}

abstract interface class PromptBuilderService {
  String build(BuiltContext context);
}

class PromptBuilderServiceImpl implements PromptBuilderService {
  @override
  String build(BuiltContext context) {
    final buffer = StringBuffer();

    // System turn
    buffer.writeln('<start_of_turn>system');
    buffer.writeln(
        'You are a helpful AI assistant. Answer clearly and concisely.');
    buffer.writeln('Answer in the same language as the user\'s question.');

    if (context.relevantChunks.isNotEmpty) {
      buffer.writeln('\nRelevant context from documents:');
      for (int i = 0; i < context.relevantChunks.length; i++) {
        buffer.writeln('[${i + 1}] ${context.relevantChunks[i].chunkText}');
      }
    }

    buffer.writeln('<end_of_turn>');

    // History turns
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

    return buffer.toString();
  }
}