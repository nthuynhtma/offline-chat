import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/core/constants/model_constants.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

class ModelManagerPage extends StatelessWidget {
  const ModelManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ModelManagerView();
  }
}

class _ModelManagerView extends StatelessWidget {
  const _ModelManagerView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Model'),
      ),
      body: BlocBuilder<ModelBloc, ModelState>(
        builder: (context, state) {
          switch (state) {
            case ModelInitial():
            case ModelLoading():
              return const Center(child: CircularProgressIndicator());
            case ModelLoaded(:final llmModels, :final geckoInfo, :final activeLlmFileName, :final gemmaReady, :final geckoReady):
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _SectionHeader(title: 'Language Models (LLM)'),
                  const SizedBox(height: AppSpacing.sm),
                  ...llmModels.map((model) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ModelStatusCard(
                      modelInfo: model,
                      isActive: model.fileName == activeLlmFileName,
                      isReady: model.fileName == activeLlmFileName ? gemmaReady : false,
                      onDownload: () => context
                          .read<ModelBloc>()
                          .add(ModelDownloadRequested(model.fileName)),
                      onActivate: model.status == ModelStatus.downloaded
                          ? () => context
                              .read<ModelBloc>()
                              .add(ActiveModelChanged(model.fileName))
                          : null,
                      onDelete: model.fileName != kDefaultModelFileName
                          ? () => _confirmDeleteModel(context, model)
                          : null,
                    ),
                  )),
                  const SizedBox(height: AppSpacing.lg),
                  _SectionHeader(title: 'Embedding Model'),
                  const SizedBox(height: AppSpacing.sm),
                  _ModelStatusCard(
                    modelInfo: geckoInfo,
                    isActive: false,
                    isReady: geckoReady,
                    onDownload: () => context
                        .read<ModelBloc>()
                        .add(const GeckoDownloadStarted()),
                    onCancel: () => context
                        .read<ModelBloc>()
                        .add(DownloadCancelled(geckoInfo.fileName)),
                    onActivate: null,
                    onDelete: null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _PrivacyNote(),
                ],
              );
            case ModelError(:final message):
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.error),
                      const SizedBox(height: AppSpacing.md),
                      Text(message, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () => context
                            .read<ModelBloc>()
                            .add(const StatusChecked()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              );
          }
        },
      ),
    );
  }

  void _confirmDeleteModel(BuildContext context, ModelInfo model) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
        title: Text('Xoá model "${model.name}"?'),
        content: const Text(
          'File model sẽ bị xoá khỏi thiết bị. '
          'Bạn có thể tải lại sau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<ModelBloc>().add(ModelDeleted(model.fileName));
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text('Xoá'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  final ModelInfo modelInfo;
  final bool isActive;
  final bool isReady;
  final VoidCallback? onDownload;
  final VoidCallback? onActivate;
  final VoidCallback? onDelete;
  final VoidCallback? onCancel;

  const _ModelStatusCard({
    required this.modelInfo,
    required this.isActive,
    required this.isReady,
    this.onDownload,
    this.onActivate,
    this.onDelete,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  modelInfo.modelType == ModelType.embedding
                      ? Icons.auto_fix_high
                      : Icons.model_training,
                  color: _statusColor,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    modelInfo.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                _StatusBadge(status: modelInfo.status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  _formatBytes(modelInfo.fileSizeBytes),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.subtleLight,
                      ),
                ),
                const Spacer(),
                // Active indicator
                if (modelInfo.modelType == ModelType.llm && isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Đang dùng',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            if (modelInfo.status == ModelStatus.downloading) ...[
              const SizedBox(height: AppSpacing.sm),
              _DownloadProgressCard(
                progress: modelInfo.progress,
                onCancel: onCancel ?? () {},
              ),
            ],
            if (modelInfo.status == ModelStatus.error &&
                modelInfo.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                modelInfo.errorMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),

            // Download / Active / Delete buttons
            if (modelInfo.status == ModelStatus.notDownloaded && onDownload != null)
              FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download),
                label: const Text('Tải xuống'),
              ),
            if (modelInfo.status == ModelStatus.downloaded) ...[
              // Active radio button
              if (modelInfo.modelType == ModelType.llm && !isActive && onActivate != null)
                OutlinedButton.icon(
                  onPressed: onActivate,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Chọn làm model mặc định'),
                ),
              if (isActive && modelInfo.modelType == ModelType.llm)
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: AppColors.success),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isReady ? 'Sẵn sàng' : 'Chưa nạp',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isReady
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                    ),
                  ],
                ),
              // Delete button
              if (onDelete != null)
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xoá'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (modelInfo.status) {
      case ModelStatus.downloaded:
        return AppColors.success;
      case ModelStatus.downloading:
        return AppColors.warning;
      case ModelStatus.error:
        return AppColors.error;
      case ModelStatus.notDownloaded:
        return AppColors.subtleLight;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    } else if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    } else {
      return '$bytes B';
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final ModelStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      ModelStatus.notDownloaded => ('Chưa tải', AppColors.subtleLight),
      ModelStatus.downloading => ('Đang tải...', AppColors.warning),
      ModelStatus.downloaded => ('Sẵn sàng', AppColors.success),
      ModelStatus.error => ('Lỗi', AppColors.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _DownloadProgressCard extends StatelessWidget {
  final double progress;
  final VoidCallback onCancel;

  const _DownloadProgressCard({
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Đang tải... ${(progress * 100).toInt()}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.subtleLight,
                        ),
                  ),
                ),
                Text(
                  '${_formatProgress(progress)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Huỷ'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatProgress(double progress) {
    return '${(progress * 100).toInt()}%';
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.backgroundLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.security, size: 20, color: AppColors.subtleLight),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Models được lưu trên thiết bị và không bao giờ được gửi lên server. '
                'Toàn bộ dữ liệu xử lý local, hoàn toàn offline.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.subtleLight,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}