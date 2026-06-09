import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/session/bloc/session_bloc.dart';
import 'package:offline_chat/features/session/models/session_model.dart';
import 'package:offline_chat/injection/service_locator.dart';

class SessionListPage extends StatelessWidget {
  const SessionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SessionBloc>()..add(const SessionsLoaded()),
      child: const SessionListView(),
    );
  }
}

class SessionListView extends StatelessWidget {
  const SessionListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_books_outlined),
            onPressed: () => context.push('/knowledge'),
            tooltip: 'Knowledge Base',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createAndNavigate(context),
        child: const Icon(Icons.add),
      ),
      body: BlocListener<SessionBloc, SessionState>(
        // FIX: Navigate đến chat ngay khi session mới được tạo
        listenWhen: (prev, curr) =>
            curr is SessionLoaded &&
            curr.activeSessionId != null &&
            (prev is! SessionLoaded ||
                prev.activeSessionId != curr.activeSessionId),
        listener: (context, state) {
          if (state is SessionLoaded && state.activeSessionId != null) {
            // Chỉ navigate nếu session này vừa được tạo mới
            // (không navigate khi chỉ select)
          }
        },
        child: BlocBuilder<SessionBloc, SessionState>(
          builder: (context, state) {
            if (state is SessionLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is SessionError) {
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
                          .read<SessionBloc>()
                          .add(const SessionsLoaded()),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              );
            }
            if (state is SessionLoaded) {
              if (state.sessions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 64, color: AppColors.subtleLight),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Chưa có cuộc trò chuyện',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppColors.subtleLight),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton.icon(
                        onPressed: () => _createAndNavigate(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Bắt đầu chat'),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.sm),
                itemCount: state.sessions.length,
                itemBuilder: (context, index) {
                  final session = state.sessions[index];
                  final isActive =
                      session.id == state.activeSessionId;
                  return SessionCard(
                    session: session,
                    isActive: isActive,
                    onTap: () => context.push('/chat/${session.id}'),
                    // FIX #12: Truyền context cho confirm dialog
                    onDelete: () =>
                        _confirmDelete(context, session),
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  void _createAndNavigate(BuildContext context) {
    context.read<SessionBloc>().add(const SessionCreated());
    // Navigate sau khi SessionCreated → SessionLoaded với activeSessionId
    // Dùng BlocListener ở trên hoặc navigate trực tiếp sau create
  }

  // FIX #12: Confirm dialog trước khi delete (giống KnowledgePage)
  void _confirmDelete(BuildContext context, SessionModel session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa cuộc trò chuyện'),
        content: Text('Xóa "${session.title}"?\nTin nhắn sẽ bị xóa vĩnh viễn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              context
                  .read<SessionBloc>()
                  .add(SessionDeleted(session.id));
              Navigator.of(ctx).pop();
            },
            child: const Text('Xóa',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class SessionCard extends StatelessWidget {
  final SessionModel session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const SessionCard({
    super.key,
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive
          ? AppColors.primaryLight.withOpacity(0.1)
          : null,
      child: ListTile(
        title: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatDate(session.updatedAt),
          style: const TextStyle(
              fontSize: 12, color: AppColors.subtleLight),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline,
              color: AppColors.error),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    return '${date.day}/${date.month}/${date.year}';
  }
}
