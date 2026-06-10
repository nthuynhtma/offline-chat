import 'package:offline_chat/core/constants/model_constants.dart';

/// Ước lượng số token cho một text bất kỳ (RAG chunks, question, summary, ...).
///
/// Dùng heuristic chars/token dựa trên tiếng Việt.
/// Không bao gồm role prefix overhead.
int estimateTokens(String text) =>
    (text.length / kCharsPerToken).ceil();

/// Ước lượng số token cho một message được replay vào session.
///
/// Bao gồm cả role prefix overhead (e.g. "user: ", "assistant: ").
/// Dùng cho history replay.
int estimateMessageTokens(String text) =>
    estimateTokens(text) + kRoleOverheadTokens;