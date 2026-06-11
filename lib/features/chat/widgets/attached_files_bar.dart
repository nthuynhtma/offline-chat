import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/database/tables/documents_table.dart';
import 'package:offline_chat/features/knowledge/bloc/session_files_cubit.dart';
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';

/// Thanh hiển thị danh sách file đã attach vào session.
/// Nằm giữa ChatBody và ChatInputBar.
class AttachedFilesBar extends StatefulWidget {
  final String sessionId;

  const AttachedFilesBar({
    required this.sessionId,
    super.key,
  });

  @override
  State<AttachedFilesBar> createState() => _AttachedFilesBarState();
}

class _AttachedFilesBarState extends State<AttachedFilesBar> {
  @override
  void initState() {
    super.initState();
    // Set session cho cubit để watch đúng files
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionFilesCubit>().setSession(widget.sessionId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionFilesCubit, SessionFilesState>(
      buildWhen: (prev, curr) {
        if (curr is SessionFilesLoaded) {
          return prev is SessionFilesLoaded &&
              (prev.files.length != curr.files.length ||
                  prev.queueState != curr.queueState);
        }
        return false;
      },
      builder: (context, state) {
        if (state is! SessionFilesLoaded || state.files.isEmpty) {
          return const SizedBox.shrink();
        }
        final files = state.files;
        final cubit = context.read<SessionFilesCubit>();
        final hasProcessing = files.any(
          (f) =>
              f.status == IndexStatus.processing ||
              f.status == IndexStatus.pending,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning khi có file đang indexing
            if (hasProcessing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                color: AppColors.warning.withOpacity(0.1),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: AppColors.warning),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Some attached files are still being indexed.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // File chips
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: files.map((file) => FileChip(
                  file: file,
                  onRemove: () {
                    cubit.detachDocument(file.id);
                    // Focus lại input để user có thể nhập tiếp
                    FocusScope.of(context).requestFocus(FocusNode());
                  },
                  onRetry: () =>
                      sl<DocumentUploadQueue>().retry(file.id),
                )).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Chip hiển thị một file với trạng thái và popup menu.
class FileChip extends StatelessWidget {
  final SessionFileItem file;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  const FileChip({
    required this.file,
    required this.onRemove,
    required this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          Icon(_statusIcon, size: 14, color: _statusColor),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              file.name,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (file.status == IndexStatus.processing) ...[
            const SizedBox(width: 4),
            Text(
              '${(file.progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 10, color: AppColors.primaryLight),
            ),
          ],
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: const Icon(Icons.more_horiz, size: 16),
            onSelected: (value) {
              if (value == 'remove') onRemove();
              if (value == 'retry') onRetry();
            },
            itemBuilder: (context) => [
              if (file.status == IndexStatus.failed)
                const PopupMenuItem(
                  value: 'retry',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 16),
                      SizedBox(width: 6),
                      Text('Retry', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(Icons.remove_circle_outline, size: 16, color: AppColors.error),
                    SizedBox(width: 6),
                    Text('Remove', style: TextStyle(fontSize: 13, color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  Color get _bgColor {
    return _statusColor.withOpacity(0.08);
  }

  Color get _borderColor {
    return _statusColor.withOpacity(0.2);
  }

  IconData get _statusIcon {
    switch (file.status) {
      case IndexStatus.pending:
        return Icons.hourglass_empty;
      case IndexStatus.processing:
        return Icons.sync;
      case IndexStatus.completed:
        return Icons.check_circle;
      case IndexStatus.failed:
        return Icons.error;
    }
  }
}
