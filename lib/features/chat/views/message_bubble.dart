import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' show MarkdownStyleSheet, MarkdownBody;
import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: AppColors.assistantBubble,
              radius: 16,
              child: const Icon(Icons.smart_toy, size: 18, color: AppColors.assistantBubbleText),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(AppSpacing.sm + 4),
              decoration: BoxDecoration(
                color: isUser ? AppColors.userBubble : AppColors.assistantBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    Text(
                      message.content,
                      style: TextStyle(
                        color: AppColors.userBubbleText,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.content + (isStreaming ? ' ▊' : ''),
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: AppColors.assistantBubbleText,
                          fontSize: 16,
                          height: 1.4,
                        ),
                        h1: TextStyle(
                          color: AppColors.assistantBubbleText,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                        h2: TextStyle(
                          color: AppColors.assistantBubbleText,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                        h3: TextStyle(
                          color: AppColors.assistantBubbleText,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                        code: TextStyle(
                          color: AppColors.assistantBubbleText,
                          backgroundColor: Colors.black12,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: AppColors.primaryLight.withOpacity(0.5),
                              width: 3,
                            ),
                          ),
                          color: Colors.black.withOpacity(0.03),
                        ),
                        blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                        listBullet: TextStyle(
                          color: AppColors.assistantBubbleText,
                          fontSize: 16,
                        ),
                        a: TextStyle(
                          color: AppColors.primaryLight,
                          decoration: TextDecoration.underline,
                        ),
                        strong: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.assistantBubbleText,
                        ),
                        em: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: AppColors.assistantBubbleText,
                        ),
                        del: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.assistantBubbleText,
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: AppColors.assistantBubbleText.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isUser
                          ? AppColors.userBubbleText.withOpacity(0.7)
                          : AppColors.subtleLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AppSpacing.sm),
            CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              radius: 16,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

