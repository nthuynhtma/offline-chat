import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/features/knowledge/bloc/session_files_cubit.dart';
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';

/// Panel hiển thị danh sách files attach trong session.
///
/// Gọi từ ChatPage Attach button → showModalBottomSheet.
class SessionFilesPanel extends StatelessWidget {
  final String sessionId;

  const SessionFilesPanel({required this.sessionId, super.key});

  /// Show panel như một bottom sheet.
  static Future<void> show(BuildContext context, String sessionId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => BlocProvider.value(
        value: context.read<SessionFilesCubit>(),
        child: SessionFilesPanel(sessionId: sessionId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Inject sessionId để Cubit filter đúng
    context.read<SessionFilesCubit>().setSession(sessionId);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Handle bar ──────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.subtleLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ─── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.folder_copy_outlined,
                      color: AppColors.primaryLight),
                  const SizedBox(width: AppSpacing.sm),
                  const Text(
                    'Tài liệu đính kèm',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  BlocBuilder<SessionFilesCubit, SessionFilesState>(
                    buildWhen: (prev, curr) {
                      if (curr is SessionFilesLoaded) {
                        return prev is SessionFilesLoaded &&
                            (prev.pendingCount != curr.pendingCount ||
                                prev.files.length != curr.files.length);
                      }
                      return true;
                    },
                    builder: (context, state) {
                      if (state is SessionFilesLoaded &&
                          state.pendingCount > 0) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${state.pendingCount} đang chờ',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryLight,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
            const Divider(),

            // ─── File list ───────────────────────────────────────────────
            Expanded(
              child: BlocBuilder<SessionFilesCubit, SessionFilesState>(
                builder: (context, state) {
                  if (state is SessionFilesLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is SessionFilesError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.error),
                          const SizedBox(height: AppSpacing.sm),
                          Text(state.message),
                        ],
                      ),
                    );
                  }

                  if (state is SessionFilesLoaded) {
                    if (state.files.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.attach_file,
                                size: 64, color: AppColors.subtleLight),
                            const SizedBox(height: AppSpacing.md),
                            const Text(
                              'Chưa có tài liệu nào',
                              style: TextStyle(
                                color: AppColors.subtleLight,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const Text(
                              'Nhấn + để thêm tài liệu vào session',
                              style: TextStyle(
                                color: AppColors.subtleLight,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      itemCount: state.files.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 52),
                      itemBuilder: (context, index) {
                        final file = state.files[index];
                        return _FileTile(file: file);
                      },
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Tile hiển thị một file với trạng thái.
class _FileTile extends StatelessWidget {
  final SessionFileItem file;

  const _FileTile({required this.file});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: _statusColor.withOpacity(0.1),
        child: Icon(_statusIcon, color: _statusColor, size: 20),
      ),
      title: Text(
        file.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _buildSubtitle(),
      trailing: _buildTrailing(),
    );
  }

  Widget? _buildSubtitle() {
    switch (file.status) {
      case IndexStatus.pending:
        return const Text(
          'Đang chờ xử lý',
          style: TextStyle(fontSize: 12, color: AppColors.subtleLight),
        );
      case IndexStatus.processing:
        return Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              '${(file.progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primaryLight,
              ),
            ),
          ],
        );
      case IndexStatus.completed:
        return Text(
          'Sẵn sàng',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.success.withOpacity(0.8),
          ),
        );
      case IndexStatus.failed:
        return Text(
          file.errorMessage ?? 'Lỗi',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.error,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget? _buildTrailing() {
    if (file.status == IndexStatus.processing) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          value: file.progress,
          strokeWidth: 2,
          color: AppColors.primaryLight,
        ),
      );
    }
    if (file.status == IndexStatus.failed) {
      return IconButton(
        icon: const Icon(Icons.refresh, size: 18, color: AppColors.error),
        onPressed: () => sl<DocumentUploadQueue>().retry(file.id),
        tooltip: 'Thử lại',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
    }
    return null;
  }

  Color get _statusColor {
    switch (file.status) {
      case IndexStatus.pending:
        return AppColors.subtleLight;
      case IndexStatus.processing:
        return AppColors.primaryLight;
      case IndexStatus.completed:
        return AppColors.success;
      case IndexStatus.failed:
        return AppColors.error;
    }
  }

  IconData get _statusIcon {
    switch (file.status) {
      case IndexStatus.pending:
        return Icons.hourglass_empty;
      case IndexStatus.processing:
        return Icons.sync;
      case IndexStatus.completed:
        return Icons.check_circle_outline;
      case IndexStatus.failed:
        return Icons.error_outline;
    }
  }
}