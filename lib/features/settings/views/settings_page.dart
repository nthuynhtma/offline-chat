import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/features/knowledge/bloc/knowledge_bloc.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/features/session/bloc/session_bloc.dart';
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';
import 'package:offline_chat/services/gemma/gemma_service.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
              subtitle: const Text('Tải, xoá và chuyển đổi AI models'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/models'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Default Model Section
          _SectionHeader(title: 'Model mặc định'),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Model sẽ được tự động tải khi cài đặt app lần đầu.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  BlocBuilder<ModelBloc, ModelState>(
                    builder: (context, state) {
                      if (state is! ModelLoaded) {
                        return const SizedBox(
                          height: 48,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }

                      return DropdownButtonFormField<String>(
                        initialValue: state.activeLlmFileName,
                        decoration: const InputDecoration(
                          labelText: 'Model chat mặc định',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: state.llmModels.map((model) {
                          return DropdownMenuItem(
                            value: model.fileName,
                            child: SizedBox(
                              width: 240, // Giới hạn chiều rộng cho dropdown
                              child: Text(
                                '${model.name} (${model.status == ModelStatus.downloaded ? "đã tải" : "chưa tải"})',
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            context.read<ModelBloc>().add(ActiveModelChanged(value));
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Available Models
          _SectionHeader(title: 'Các model có sẵn'),
          const SizedBox(height: AppSpacing.sm),
          BlocBuilder<ModelBloc, ModelState>(
            builder: (context, state) {
              if (state is! ModelLoaded) return const SizedBox.shrink();

              return Column(
                children: [
                  ...state.llmModels.map((model) => Card(
                    child: ListTile(
                      leading: Icon(
                        model.status == ModelStatus.downloaded
                            ? Icons.check_circle
                            : Icons.cloud_download_outlined,
                        color: model.status == ModelStatus.downloaded
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: Text(
                        model.name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      subtitle: Text(
                        '${_formatBytes(model.fileSizeBytes)} — ${model.status == ModelStatus.downloaded ? "đã tải" : "chưa tải"}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: model.status == ModelStatus.notDownloaded
                          ? IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () => context
                                  .read<ModelBloc>()
                                  .add(ModelDownloadRequested(model.fileName)),
                            )
                          : null,
                    ),
                  )),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // Danger Zone
          _SectionHeader(
            title: 'Vùng nguy hiểm',
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep, color: Colors.red),
                  title: const Text('Xoá tất cả dữ liệu'),
                  subtitle: const Text('Xoá toàn bộ sessions, messages, và documents'),
                  onTap: () => _showClearAllDataDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh, color: Colors.red),
                  title: const Text('Đánh chỉ mục lại tất cả'),
                  subtitle: const Text('Re-embed toàn bộ documents'),
                  onTap: () => _showReindexDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  void _showClearAllDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            size: 48, color: Colors.red),
        title: const Text('Xoá tất cả dữ liệu?'),
        content: const Text(
          'Hành động này không thể hoàn tác.\n\n'
          '• Toàn bộ lịch sử chat\n'
          '• Tài liệu đã import\n'
          '• Vectors và chỉ mục BM25\n'
          '• Session memory và user memory\n\n'
          'Model AI files sẽ được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeClearAllData();
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text('Xoá tất cả'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeClearAllData() async {
    try {
      log_util.log.i('[Settings] Bắt đầu xoá tất cả dữ liệu...');

      // Đóng Gemma session trước
      final gemmaService = sl<GemmaService>();
      await gemmaService.closeSession();

      // Xoá database — dùng DAOs
      final db = sl<AppDatabase>();

      // Xoá FTS5 index trước
      try {
        await db.customSelect('DELETE FROM chunks_fts').get();
      } catch (_) {}

      // Xoá data bằng raw SQL (tránh FK constraints)
      await db.customSelect('DELETE FROM vectors').get();
      await db.customSelect('DELETE FROM chunks').get();
      await db.customSelect('DELETE FROM messages').get();
      await db.customSelect('DELETE FROM session_document_refs').get();
      await db.customSelect('DELETE FROM session_memory').get();
      await db.customSelect('DELETE FROM user_memory').get();
      await db.customSelect('DELETE FROM documents').get();
      await db.customSelect('DELETE FROM sessions').get();

      // Reset SharedPreferences model settings
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_llm_model');
      await prefs.remove('hasSeenModelOnboarding');

      log_util.log.i('[Settings] Đã xoá toàn bộ dữ liệu thành công');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xoá toàn bộ dữ liệu'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Refresh state
        context.read<ModelBloc>().add(const StatusChecked());
        context.read<SessionBloc>().add(const SessionsLoaded());
        context.read<KnowledgeBloc>().add(const DocumentsLoaded());
      }
    } catch (e) {
      log_util.log.e('[Settings] Lỗi khi xoá dữ liệu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showReindexDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.refresh, size: 48, color: Colors.orange),
        title: const Text('Đánh chỉ mục lại?'),
        content: const Text(
          'Toàn bộ documents đã import sẽ được re-parse, re-chunk, '
          're-embed và re-index BM25.\n\n'
          'Quá trình này có thể mất vài phút nếu có nhiều documents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeReindex();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Bắt đầu'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeReindex() async {
    try {
      log_util.log.i('[Settings] Bắt đầu đánh chỉ mục lại...');

      final db = sl<AppDatabase>();

      // Xoá vectors + chunks cũ (giữ documents)
      await db.customSelect('DELETE FROM vectors').get();
      await db.customSelect('DELETE FROM chunks').get();
      try {
        await db.customSelect('DELETE FROM chunks_fts').get();
      } catch (_) {}

      // Reset document status về pending (raw SQL)
      await db.customSelect(
        'UPDATE documents SET status = 0, progress = 0.0, last_processed_at = NULL',
      ).get();

      // Enqueue lại tất cả documents qua upload queue
      final docs = await db.documentsDao.getAllDocuments();
      for (final doc in docs) {
        sl<DocumentUploadQueue>().enqueue(DocumentUploadJob(
          documentId: doc.id,
          filePath: doc.path,
          name: doc.name,
          sizeBytes: doc.sizeBytes,
          mimeType: doc.mimeType,
          sessionId: doc.sessionId,
        ));
      }

      log_util.log.i('[Settings] Đã enqueue ${docs.length} documents để re-index');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã bắt đầu đánh chỉ mục lại ${docs.length} documents'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      log_util.log.e('[Settings] Lỗi reindex: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
    );
  }
}