import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/knowledge/bloc/knowledge_bloc.dart';
import 'package:offline_chat/features/knowledge/models/document_model.dart';

class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const KnowledgeView();
  }
}

class KnowledgeView extends StatelessWidget {
  const KnowledgeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        actions: [
          // FIX: Disable import khi đang indexing
          BlocBuilder<KnowledgeBloc, KnowledgeState>(
            buildWhen: (prev, curr) =>
                (prev is KnowledgeIndexing) != (curr is KnowledgeIndexing),
            builder: (context, state) {
              final isIndexing = state is KnowledgeIndexing;
              return IconButton(
                icon: Icon(
                  Icons.add,
                  color: isIndexing
                      ? AppColors.subtleLight.withOpacity(0.4)
                      : null,
                ),
                onPressed:
                    isIndexing ? null : () => _pickAndImportFile(context),
                tooltip: 'Import tài liệu',
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<KnowledgeBloc, KnowledgeState>(
        builder: (context, state) {
          if (state is KnowledgeInitial || state is KnowledgeLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is KnowledgeIndexing) {
            return _IndexingProgressView(
              documentName: state.documentName,
              progress: state.progress,
            );
          }

          // FIX #5: KnowledgeError có documents → hiển thị list + error banner
          if (state is KnowledgeError) {
            if (state.documents.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: AppSpacing.md),
                    Text(state.message, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: () => context
                          .read<KnowledgeBloc>()
                          .add(const DocumentsLoaded()),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              );
            }
            // Có documents cũ: hiển thị chúng + error banner nhỏ
            return Column(
              children: [
                _KnowledgeErrorBanner(
                  message: state.message,
                  onRetry: () => context
                      .read<KnowledgeBloc>()
                      .add(const DocumentsLoaded()),
                ),
                Expanded(
                  child: _DocumentList(documents: state.documents),
                ),
              ],
            );
          }

          if (state is KnowledgeLoaded) {
            if (state.documents.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.library_books_outlined,
                        size: 64, color: AppColors.subtleLight),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Chưa có tài liệu nào',
                      style: TextStyle(color: AppColors.subtleLight),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Nhấn + để import PDF, DOCX, TXT, MD',
                      style: TextStyle(
                        color: AppColors.subtleLight,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton.icon(
                      onPressed: () => _pickAndImportFile(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Import tài liệu'),
                    ),
                  ],
                ),
              );
            }

            return _DocumentList(documents: state.documents);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _pickAndImportFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    if (context.mounted) {
      context
          .read<KnowledgeBloc>()
          .add(DocumentImportRequested(filePath));
    }
  }
}

class _KnowledgeErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _KnowledgeErrorBanner({
    required this.message,
    required this.onRetry,
  });

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
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Thử lại', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  final List<DocumentModel> documents;
  const _DocumentList({required this.documents});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: documents.length,
      itemBuilder: (context, index) =>
          _DocumentCard(doc: documents[index]),
    );
  }
}

class _IndexingProgressView extends StatelessWidget {
  final String documentName;
  final double progress;

  const _IndexingProgressView({
    required this.documentName,
    required this.progress,
  });

  String _progressLabel(double p) {
    if (p < 0.1) return 'Đang copy file...';
    if (p < 0.2) return 'Đang phân tích...';
    if (p < 0.3) return 'Đang chia chunks...';
    if (p < 0.4) return 'Đang lưu chunks...';
    if (p < 0.9) return 'Đang embedding (${(p * 100).toInt()}%)...';
    if (p < 1.0) return 'Đang lưu vectors...';
    return 'Hoàn tất';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.library_books_outlined,
              size: 48,
              color: AppColors.primaryLight,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Đang xử lý',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              documentName,
              style: const TextStyle(
                color: AppColors.subtleLight,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: AppColors.backgroundLight,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _progressLabel(progress),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentModel doc;

  const _DocumentCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final icon = _getIcon(doc.mimeType);
    final sizeStr = _formatSize(doc.sizeBytes);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryLight),
        title: Text(
          doc.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$sizeStr • ${doc.chunkCount} chunks',
          style: const TextStyle(fontSize: 12, color: AppColors.subtleLight),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.error),
          onPressed: () => _confirmDelete(context, doc),
        ),
      ),
    );
  }

  IconData _getIcon(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('text')) return Icons.text_snippet;
    return Icons.insert_drive_file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _confirmDelete(BuildContext context, DocumentModel doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tài liệu'),
        content: Text('Xóa "${doc.name}" khỏi knowledge base?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              context
                  .read<KnowledgeBloc>()
                  .add(DocumentDeleteRequested(doc.id));
              Navigator.of(ctx).pop();
            },
            child: const Text('Xóa', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
