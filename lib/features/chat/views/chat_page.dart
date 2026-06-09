import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/views/message_bubble.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

class ChatPage extends StatelessWidget {
  final String sessionId;
  const ChatPage({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey('chat_$sessionId'),
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: ChatView(sessionId: sessionId),
    );
  }
}

/// Quản lý dialog loading model khi vào màn hình chat.
/// Dùng StatefulWidget để có lifecycle initState/dispose cho dialog.
class ChatView extends StatefulWidget {
  final String sessionId;
  const ChatView({required this.sessionId, super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  @override
  void initState() {
    super.initState();
    // Kiểm tra trạng thái model ngay sau khi build frame đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkModelAndShowDialog(context);
    });
  }

  void _checkModelAndShowDialog(BuildContext context) {
    if (!mounted) return;

    final modelBloc = context.read<ModelBloc>();
    final modelState = modelBloc.state;

    if (modelState is ModelLoaded) {
      final isDownloaded =
          modelState.gemmaInfo.status == ModelStatus.downloaded;

      // Nếu model chưa download → ChatBloc sẽ emit ChatError.needsModelDownload
      // → banner warning xử lý, không cần dialog
      if (!isDownloaded) return;
      if (modelState.gemmaReady) return; // Đã sẵn sàng rồi

      // Nếu init chưa từng chạy hoặc đã fail → dispatch StatusChecked để retry
      if (!modelBloc.isInitializingGemma) {
        modelBloc.add(const StatusChecked());
      }

      // Show dialog loading — BlocListener bên trong sẽ tự đóng khi gemmaReady
      _showLoadingDialog();
    } else if (modelState is ModelLoading) {
      // ModelBloc đang loading → chờ init xong
    }
  }

  void _showLoadingDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return BlocListener<ModelBloc, ModelState>(
          listener: (context, state) {
            if (state is ModelLoaded && state.gemmaReady) {
              Navigator.of(context).pop();
              context.read<ChatBloc>().add(const ModelBecameReady());
            }
            if (state is ModelError) {
              Navigator.of(context).pop();
            }
          },
          child: AlertDialog(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Đang nạp model AI vào bộ nhớ...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Model Gemma (2.8GB) đang được load. '
                  'Vui lòng đợi trong giây lát.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.subtleLight,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Chat'),
        actions: [
          _ClearButton(sessionId: widget.sessionId),
        ],
      ),
      body: Column(
        children: [
          // ─── Banner "Chưa tải model" ──────────────────────────────────
          _ModelNotInstalledBanner(),

          // Chat body (loading / error / messages)
          Expanded(
            child: _ChatBody(sessionId: widget.sessionId),
          ),

          // Input bar
          ChatInputBar(sessionId: widget.sessionId),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget con riêng — mỗi widget chỉ rebuild khi state liên quan thay đổi
// ─────────────────────────────────────────────────────────────────────────────

/// Banner hiển thị khi model chưa được tải.
class _ModelNotInstalledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (prev, curr) {
        final prevNeeds = prev is ChatError && prev.needsModelDownload;
        final currNeeds = curr is ChatError && curr.needsModelDownload;
        return prevNeeds != currNeeds;
      },
      builder: (context, state) {
        if (state is ChatError && state.needsModelDownload) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: AppColors.warning.withOpacity(0.2),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(child: Text('Model AI chưa được tải')),
                TextButton(
                  onPressed: () => context.push('/settings/models'),
                  child: const Text('Tải'),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Nút xoá trong app bar (chỉ rebuild khi trạng thái streaming thay đổi).
class _ClearButton extends StatelessWidget {
  final String sessionId;
  const _ClearButton({required this.sessionId});

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

/// Body chính của chat: hiển thị loading / error / messages dựa trên ChatState.
class _ChatBody extends StatelessWidget {
  final String sessionId;
  const _ChatBody({required this.sessionId});

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
              _ErrorBanner(message: state.message),
              Expanded(
                child: _MessageList(
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
        return _MessageList(
          messages: messages,
          sessionId: sessionId,
          showThinkingIndicator: showThinking,
        );
      },
    );
  }
}

/// Danh sách tin nhắn + streaming/thinking bubble + auto-scroll.
/// Dùng ListView.builder + scrollview_observer để scroll mượt và phát hiện vị trí.
class _MessageList extends StatefulWidget {
  final List<MessageModel> messages;
  final String sessionId;
  final bool showThinkingIndicator;

  const _MessageList({
    required this.messages,
    required this.sessionId,
    this.showThinkingIndicator = false,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
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
  void didUpdateWidget(covariant _MessageList oldWidget) {
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
                return _LastBubble(sessionId: widget.sessionId);
              }
              return MessageBubble(message: widget.messages[index]);
            },
          ),
        ),

        // Nút "⬇ Mới nhất" — chỉ hiển thị khi user không ở cuối
        _ScrollToBottomButton(
          isVisible: !_isNearBottom,
          onTap: _scrollToBottom,
        ),
      ],
    );
  }
}

/// Nút nổi "⬇ Mới nhất" ở góc dưới phải.
class _ScrollToBottomButton extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onTap;

  const _ScrollToBottomButton({
    required this.isVisible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AnimatedSlide(
            offset: isVisible ? Offset.zero : const Offset(0, 2),
            duration: const Duration(milliseconds: 200),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: isVisible ? onTap : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: AppColors.primaryLight,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Mới nhất',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bubble cuối cùng: hiển thị thinking indicator (3 chấm) hoặc text đang stream.
/// Dùng BlocBuilder chỉ rebuild khi cần.
class _LastBubble extends StatelessWidget {
  final String sessionId;
  const _LastBubble({required this.sessionId});

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
          return _ThinkingBubble(sessionId: sessionId);
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

/// Bubble "AI đang suy nghĩ..." với 3 chấm animation.
class _ThinkingBubble extends StatefulWidget {
  final String sessionId;
  const _ThinkingBubble({required this.sessionId});

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar AI
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryLight.withOpacity(0.1),
            child: const Icon(Icons.agriculture, size: 18, color: AppColors.primaryLight),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Bubble với 3 chấm
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) {
                      final delay = index * 0.2;
                      final t = (_animationController.value - delay)
                          .clamp(0.0, 1.0);
                      final scale = (t < 0.5)
                          ? (t / 0.5) * 0.5 + 0.5   // 0.5 → 1.0
                          : (1.0 - (t - 0.5) / 0.5) * 0.5 + 0.5; // 1.0 → 0.5
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Transform.scale(
                          scale: scale,
                          child: const CircleAvatar(
                            radius: 4,
                            backgroundColor: AppColors.subtleLight,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Banner lỗi nhỏ, không chiếm toàn màn hình
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: AppColors.error.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatInputBar extends StatefulWidget {
  final String sessionId;
  const ChatInputBar({required this.sessionId, super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _isStreaming = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<ChatBloc>().add(SendMessageRequested(text));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatBloc, ChatState>(
      listener: (context, state) {
        if (mounted) {
          setState(() {
            _isStreaming = state is ChatStreaming;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_isStreaming,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText:
                        _isStreaming ? 'Đang trả lời...' : 'Nhập tin nhắn...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.backgroundLight,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  onSubmitted: _isStreaming ? null : (_) => _onSend(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (_isStreaming)
                IconButton(
                  onPressed: () =>
                      context.read<ChatBloc>().add(const StreamingCancelled()),
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: AppColors.error,
                  tooltip: 'Dừng',
                )
              else
                IconButton(
                  onPressed: _onSend,
                  icon: const Icon(Icons.send_rounded),
                  color: AppColors.primaryLight,
                  tooltip: 'Gửi',
                ),
            ],
          ),
        ),
      ),
    );
  }
}