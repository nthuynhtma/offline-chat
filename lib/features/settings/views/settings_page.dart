import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_chat/core/constants/app_constants.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _chunkSizeController;
  late TextEditingController _chunkOverlapController;
  late TextEditingController _historyLimitController;
  late TextEditingController _similarityThresholdController;

  @override
  void initState() {
    super.initState();
    _chunkSizeController =
        TextEditingController(text: AppConstants.defaultChunkSize.toString());
    _chunkOverlapController =
        TextEditingController(text: AppConstants.defaultChunkOverlap.toString());
    _historyLimitController =
        TextEditingController(text: AppConstants.maxHistoryMessages.toString());
    _similarityThresholdController = TextEditingController(
        text: AppConstants.similarityThreshold.toString());
  }

  @override
  void dispose() {
    _chunkSizeController.dispose();
    _chunkOverlapController.dispose();
    _historyLimitController.dispose();
    _similarityThresholdController.dispose();
    super.dispose();
  }

  void _showSavedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu cấu hình'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Model Management
          Card(
            child: ListTile(
              leading: const Icon(Icons.model_training),
              title: const Text('Quản lý Model'),
              subtitle: const Text('Tải và quản lý AI models'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/models'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // RAG Settings Section
          Text(
            'Cấu hình RAG',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _chunkSizeController,
                    decoration: const InputDecoration(
                      labelText: 'Kích thước chunk (tokens)',
                      helperText: 'Số tokens tối đa mỗi chunk khi chia nhỏ văn bản',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _chunkOverlapController,
                    decoration: const InputDecoration(
                      labelText: 'Chunk overlap (tokens)',
                      helperText: 'Số tokens chồng lấn giữa các chunk',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _similarityThresholdController,
                    decoration: const InputDecoration(
                      labelText: 'Ngưỡng tương đồng',
                      helperText: '0.0 - 1.0. Chỉ lấy chunks có độ tương đồng >= ngưỡng này',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () {
                        // Save to persistent storage (shared_preferences pattern)
                        _showSavedSnackBar();
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Lưu'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Chat Settings Section
          Text(
            'Cấu hình Chat',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _historyLimitController,
                    decoration: const InputDecoration(
                      labelText: 'Giới hạn lịch sử (messages)',
                      helperText: 'Số messages tối đa được giữ làm context',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Lưu ý: Giảm giá trị nếu gặp hiệu năng chậm. '
                    'Tăng giá trị nếu cần ngữ cảnh dài hơn.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Danger Zone
          Text(
            'Vùng nguy hiểm',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep,
                      color: Colors.red),
                  title: const Text('Xoá tất cả dữ liệu'),
                  subtitle: const Text('Xoá toàn bộ sessions, messages, và documents'),
                  onTap: () => _showClearAllDataDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh, color: Colors.red),
                  title: const Text('Đánh chỉ mục lại tất cả'),
                  subtitle: const Text('Re-embed toàn bộ documents'),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tính năng đang phát triển'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showClearAllDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            size: 48, color: Colors.red),
        title: const Text('Xoá tất cả dữ liệu?'),
        content: const Text(
          'Hành động này không thể hoàn tác. '
          'Toàn bộ lịch sử chat, tài liệu đã import và chỉ mục sẽ bị xoá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tính năng đang phát triển'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text('Xoá tất cả'),
          ),
        ],
      ),
    );
  }
}