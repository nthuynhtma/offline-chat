import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/chat/views/message_bubble.dart';
import 'package:offline_chat/injection/service_locator.dart';

class ChatPage extends StatelessWidget {
  final String sessionId;
  const ChatPage({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: ChatView(sessionId: sessionId),
    );
  }
}

class ChatView extends StatelessWidget {
  final String sessionId;
  const ChatView({required this.sessionId, super.key});

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
          // FIX #11: Disable delete button khi đang streaming
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (prev, curr) =>
                (prev is ChatStreaming) != (curr is ChatStreaming),
            builder: (context, state) {
              final isStreaming = state is ChatStreaming;
              return IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: isStreaming
                      ? AppColors.subtleLight.withOpacity(0.4)
                      : null,
                ),
                onPressed: isStreaming
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Xóa tin nhắn'),
                            content: const Text(
                                'Xóa toàn bộ tin nhắn trong cuộc trò chuyện này?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Hủy'),
                              ),
                              TextButton(
                                onPressed: () {
                                  context
                                      .read<ChatBloc>()
                                      .add(const MessagesCleared());
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('Xóa',
                                    style:
                                        TextStyle(color: AppColors.error)),
                              ),
                            ],
                          ),
                        ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // FIX #2: buildWhen đúng — rebuild khi chuyển vào/ra ChatError.needsModelDownload
          BlocBuilder<ChatBloc, ChatState>(
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
                      const Icon(Icons.warning_amber,
                          color: AppColors.warning),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Text('Model AI chưa được tải'),
                      ),
                      TextButton(
                        onPressed: () =>
                            context.push('/settings/models'),
                        child: const Text('Tải'),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Messages
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                // FIX #2: ChatError có thể có messages → hiển thị chúng + error toast
                // Không còn trả về full-screen error khi có messages
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
                  // Có messages: hiển thị list + error banner nhỏ phía trên
                  return Column(
                    children: [
                      _ErrorBanner(message: state.message),
                      Expanded(
                        child: _MessageList(
                          messages: state.messages,
                          sessionId: sessionId,
                        ),
                      ),
                    ],
                  );
                }

                List<MessageModel> messages = [];
                String? streamingText;
                String? streamingId;

                if (state is ChatLoaded) {
                  messages = state.messages;
                } else if (state is ChatStreaming) {
                  messages = state.messages;
                  streamingText = state.streamingText;
                  streamingId = state.streamingId;
                }

                if (messages.isEmpty && streamingText == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: AppColors.subtleLight),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Bắt đầu cuộc trò chuyện',
                          style:
                              TextStyle(color: AppColors.subtleLight),
                        ),
                      ],
                    ),
                  );
                }

                return _MessageList(
                  messages: messages,
                  sessionId: sessionId,
                  streamingText: streamingText,
                  streamingId: streamingId,
                );
              },
            ),
          ),
          // Input bar
          ChatInputBar(sessionId: sessionId),
        ],
      ),
    );
  }
}

// Widget riêng để tránh code duplicate
class _MessageList extends StatelessWidget {
  final List<MessageModel> messages;
  final String sessionId;
  final String? streamingText;
  final String? streamingId;

  const _MessageList({
    required this.messages,
    required this.sessionId,
    this.streamingText,
    this.streamingId,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding:
          const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      itemCount: messages.length + (streamingText != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (streamingText != null && index == messages.length) {
          return MessageBubble(
            message: MessageModel(
              id: streamingId!,
              sessionId: sessionId,
              role: MessageRole.assistant,
              content: streamingText!,
              createdAt: DateTime.now(),
            ),
            isStreaming: true,
          );
        }
        return MessageBubble(message: messages[index]);
      },
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
          const Icon(Icons.error_outline,
              size: 16, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.error),
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
        // FIX: Reset _isStreaming chính xác cho mọi state
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
                    hintText: _isStreaming
                        ? 'Đang trả lời...'
                        : 'Nhập tin nhắn...',
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
              // FIX: Khi streaming hiện nút Cancel thay vì nút Send bị disable
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
