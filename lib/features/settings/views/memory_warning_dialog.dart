import 'package:flutter/material.dart';
import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';

/// Dialog cảnh báo khi RAM không đủ để tải model
class MemoryWarningDialog extends StatelessWidget {
  final int requiredMB;
  final int? availableMB;

  const MemoryWarningDialog({
    super.key,
    required this.requiredMB,
    this.availableMB,
  });

  /// Hiển thị dialog, trả về true nếu user muốn thử lại
  static Future<bool> show(
    BuildContext context, {
    required int requiredMB,
    int? availableMB,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MemoryWarningDialog(
        requiredMB: requiredMB,
        availableMB: availableMB,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.memory,
        size: 48,
        color: AppColors.warning,
      ),
      title: const Text('Không đủ bộ nhớ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cần ít nhất $requiredMB MB RAM trống để tải model này.',
          ),
          if (availableMB != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Dung lượng khả dụng: ~$availableMB MB',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.subtleLight,
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Hãy thử:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _TipItem(text: 'Đóng các ứng dụng khác'),
          const _TipItem(text: 'Chọn model nhỏ hơn (nếu có)'),
          const _TipItem(text: 'Khởi động lại thiết bị'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Bỏ qua'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      ],
    );
  }
}

class _TipItem extends StatelessWidget {
  final String text;
  const _TipItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: AppColors.success),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}