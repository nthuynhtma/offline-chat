import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/repositories/message_repository.dart';
import 'package:offline_chat/services/prompt/prompt_builder_service.dart';

class ContextManagerService {
  final MessageRepository _messageRepo;

  ContextManagerService(this._messageRepo);

  static const int totalBudget = 8000;
  static const int ragBudget = 4000;
  static const int historyBudget = 3000;
  static const int questionBudget = 1000;

  Future<BuiltContext> buildContext({
    required String question,
    required String sessionId,
    required List<SearchResult> ragResults,
  }) async {
    var history =
        await _messageRepo.getRecentMessages(sessionId, limit: 20);

    // Estimate token count
    int estimatedTokens = _estimateTokens(question);
    for (final msg in history) {
      estimatedTokens += _estimateTokens(msg.content);
    }

    bool historyTrimmed = false;

    // Trim history if over budget
    if (estimatedTokens > (historyBudget + questionBudget)) {
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
    }

    return BuiltContext(
      question: question,
      relevantChunks: ragResults,
      history: history,
      historyWasTrimmed: historyTrimmed,
      estimatedTokens: estimatedTokens,
    );
  }

  int _estimateTokens(String text) {
    return (text.length / 3).ceil();
  }
}