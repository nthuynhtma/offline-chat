import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/widgets/error_banner.dart';
import 'package:offline_chat/features/chat/widgets/message_list.dart';

/// Body chính của chat: hiển thị loading / error / messages dựa trên ChatState.
class ChatBody extends StatelessWidget {
  final String sessionId;
  
  const ChatBody({
    required this.sessionId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (prev, curr) {
        if (curr is ChatThinking && prev is ChatThinking) return false;
        return true;
      },
      builder: (context, state) {
        // Loading state
        if (state is ChatLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Error state (non-model-download)
        if (state is ChatError && !state.needsModelDownload) {
          if (state.messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppColors.error),
                  const SizedBox(height: AppSpacing.md),
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: () => context
                        .read<ChatBloc>()
                        .add(SessionInitialized(sessionId)),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              ErrorBanner(message: state.message),
              Expanded(
                child: MessageList(
                  messages: state.messages,
                  sessionId: sessionId,
                  showThinkingIndicator: false,
                ),
              ),
            ],
          );
        }

        // Extract messages from state
        List<MessageModel> messages = [];
        bool showThinking = false;
        if (state is ChatLoaded) {
          messages = state.messages;
          showThinking = false;
        } else if (state is ChatThinking) {
          messages = state.messages;
          showThinking = true;
        } else if (state is ChatStreaming) {
          messages = state.messages;
          showThinking = false;
        }

        // Empty state
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64, color: AppColors.subtleLight),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Bắt đầu cuộc trò chuyện',
                  style: TextStyle(color: AppColors.subtleLight),
                ),
              ],
            ),
          );
        }

        // Messages with optional streaming/thinking bubble
        return MessageList(
          messages: messages,
          sessionId: sessionId,
          showThinkingIndicator: showThinking,
        );
      },
    );
  }
}
