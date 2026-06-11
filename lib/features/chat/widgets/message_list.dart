import 'package:flutter/material.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/views/message_bubble.dart';
import 'package:offline_chat/features/chat/widgets/last_bubble.dart';
import 'package:offline_chat/features/chat/widgets/scroll_to_bottom_button.dart';

/// Danh sách tin nhắn + streaming/thinking bubble + auto-scroll.
/// Dùng ListView.builder + scrollview_observer để scroll mượt và phát hiện vị trí.
class MessageList extends StatefulWidget {
  final List<MessageModel> messages;
  final String sessionId;
  final bool showThinkingIndicator;

  const MessageList({
    required this.messages,
    required this.sessionId,
    this.showThinkingIndicator = false,
    super.key,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();

  /// true nếu user đang ở sát cuối danh sách (cho phép auto-scroll).
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();
    // Scroll xuống tin nhắn cuối khi vừa vào màn hình
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  /// Scroll xuống tin nhắn cuối cùng.
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-scroll xuống cuối khi user đang ở cuối và có message mới / streaming
    if (_isNearBottom) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-scroll mỗi lần widget rebuild (streaming text thay đổi)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isNearBottom && mounted) {
        _scrollToBottom();
      }
    });

    return Stack(
      children: [
        ListViewObserver(
          controller: ListObserverController(controller: _scrollController),
          onObserve: (result) {
            if (!mounted) return;
            // Kiểm tra item cuối (messages.length = index của bubble cuối)
            final lastIndex = widget.messages.length;
            final visibleList = result.displayingChildModelList;
            final isLastVisible = visibleList.any((model) =>
                model.index == lastIndex);
            if (_isNearBottom != isLastVisible) {
              setState(() {
                _isNearBottom = isLastVisible;
              });
            }
          },
          child: ListView.builder(
            controller: _scrollController,
            padding:
                const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
            itemCount: widget.messages.length + 1, // +1 cho streaming/thinking bubble
            itemBuilder: (context, index) {
              if (index == widget.messages.length) {
                // Streaming/thinking bubble — rebuild riêng
                return LastBubble(sessionId: widget.sessionId);
              }
              return MessageBubble(message: widget.messages[index]);
            },
          ),
        ),

        // Nút "⬇ Mới nhất" — chỉ hiển thị khi user không ở cuối
        ScrollToBottomButton(
          isVisible: !_isNearBottom,
          onTap: _scrollToBottom,
        ),
      ],
    );
  }
}
