import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';

/// Nút xoá trong app bar (chỉ rebuild khi trạng thái streaming thay đổi).
class ClearButton extends StatelessWidget {
  final String sessionId;
  
  const ClearButton({
    required this.sessionId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (prev, curr) =>
          (prev is ChatStreaming) != (curr is ChatStreaming) ||
          (prev is ChatThinking) != (curr is ChatThinking),
      builder: (context, state) {
        final isBusy = state is ChatStreaming || state is ChatThinking;
        return IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: isBusy
                ? AppColors.subtleLight.withOpacity(0.4)
                : null,
          ),
          onPressed: isBusy
              ? null
              : () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xóa tin nhắn'),
                      content: const Text(
                        'Xóa toàn bộ tin nhắn trong cuộc trò chuyện này?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Hủy'),
                        ),
                        TextButton(
                          onPressed: () {
                            context.read<ChatBloc>().add(const MessagesCleared());
                            Navigator.of(ctx).pop();
                          },
                          child: const Text(
                            'Xóa',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
        );
      },
    );
  }
}
