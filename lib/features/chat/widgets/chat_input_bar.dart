import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/database/app_database.dart';
import 'package:offline_chat/database/tables/documents_table.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/knowledge/views/session_files_panel.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/chunker/document_upload_queue.dart';

class ChatInputBar extends StatefulWidget {
  final String sessionId;
  
  const ChatInputBar({
    required this.sessionId,
    super.key,
  });

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

  Future<void> _onAttachFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        final filePath = file.path;
        if (filePath == null) continue;

        final uuid = Uuid();
        final docId = uuid.v4();

        // Insert document vào DB với status=pending
        await sl<AppDatabase>().documentsDao.insertDocument(
          DocumentsCompanion(
            id: Value(docId),
            name: Value(file.name),
            path: Value(filePath),
            sizeBytes: Value(file.size),
            mimeType: Value(file.extension ?? ''),
            sessionId: Value(widget.sessionId),
            status: Value(IndexStatus.pending.toInt),
            createdAt: Value(DateTime.now()),
          ),
        );

        // Enqueue job vào upload queue
        sl<DocumentUploadQueue>().enqueue(
          DocumentUploadJob(
            documentId: docId,
            filePath: filePath,
            name: file.name,
            sizeBytes: file.size,
            mimeType: file.extension ?? '',
            sessionId: widget.sessionId,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải file: $e')),
        );
      }
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: _buildAttachMenuColumn(ctx),
      ),
    );
  }

  Widget _buildAttachMenuColumn(BuildContext ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Tải file mới'),
          subtitle: const Text('PDF, DOCX, TXT, MD'),
          onTap: () {
            Navigator.of(ctx).pop();
            _onAttachFile();
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_copy_outlined),
          title: const Text('Xem tài liệu đính kèm'),
          onTap: () {
            Navigator.of(ctx).pop();
            SessionFilesPanel.show(context, widget.sessionId);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelState = context.watch<ModelBloc>().state;
    final isGeckoReady = switch (modelState) {
      ModelLoaded(:final geckoReady) => geckoReady,
      _ => false,
    };

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
              // Nút attach file
              IconButton(
                onPressed: (_isStreaming || !isGeckoReady) ? null : _showAttachMenu,
                icon: const Icon(Icons.attach_file),
                color: (_isStreaming || !isGeckoReady)
                    ? AppColors.subtleLight.withOpacity(0.4)
                    : AppColors.subtleLight,
                tooltip: !isGeckoReady
                    ? 'Preparing AI models...'
                    : 'Đính kèm tài liệu',
              ),
              const SizedBox(width: 4),
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
                        : 'Ask a question or chat about attached files...',
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
