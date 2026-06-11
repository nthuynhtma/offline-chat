import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/views/message_bubble.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/widgets/thinking_bubble.dart';

/// Bubble cuối cùng: hiển thị thinking indicator (3 chấm) hoặc text đang stream.
/// Dùng BlocBuilder chỉ rebuild khi cần.
class LastBubble extends StatelessWidget {
  final String sessionId;
  
  const LastBubble({
    required this.sessionId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (prev, curr) {
        // Rebuild khi streamingText thay đổi
        if (prev is ChatStreaming && curr is ChatStreaming) {
          return prev.streamingText != curr.streamingText;
        }
        // Rebuild khi chuyển từ Thinking → Streaming (giữ bubble, đổi nội dung)
        if (curr is ChatStreaming && prev is ChatThinking) return true;
        // Rebuild khi bắt đầu Thinking
        if (curr is ChatThinking && prev is! ChatThinking) return true;
        // Rebuild khi bắt đầu stream (Loaded/Thinking → Streaming)
        if (curr is ChatStreaming && prev is! ChatStreaming) return true;
        // Rebuild khi kết thúc stream (Streaming → Loaded)
        if (curr is! ChatStreaming && prev is ChatStreaming) return true;
        return false;
      },
      builder: (context, state) {
        if (state is ChatThinking) {
          return ThinkingBubble(sessionId: sessionId);
        }
        if (state is ChatStreaming) {
          return MessageBubble(
            message: MessageModel(
              id: state.streamingId,
              sessionId: sessionId,
              role: MessageRole.assistant,
              content: state.streamingText,
              createdAt: DateTime.now(),
            ),
            isStreaming: true,
          );
        }
        // Stream/Thinking đã kết thúc → hiển thị empty (đã có MessageBubble thật từ messages)
        return const SizedBox.shrink();
      },
    );
  }
}
