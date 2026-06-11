import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';
import 'package:offline_chat/features/chat/widgets/attached_files_bar.dart';
import 'package:offline_chat/features/chat/widgets/chat_body.dart';
import 'package:offline_chat/features/chat/widgets/chat_input_bar.dart';
import 'package:offline_chat/features/chat/widgets/clear_button.dart';
import 'package:offline_chat/features/chat/widgets/model_not_installed_banner.dart';
import 'package:offline_chat/features/chat/widgets/scope_selector.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/injection/service_locator.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';

class ChatPage extends StatelessWidget {
  final String sessionId;
  const ChatPage({required this.sessionId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey('chat_$sessionId'),
      create: (_) => sl<ChatBloc>()..add(SessionInitialized(sessionId)),
      child: ChatView(sessionId: sessionId),
    );
  }
}

/// Quản lý dialog loading model khi vào màn hình chat.
/// Dùng StatefulWidget để có lifecycle initState/dispose cho dialog.
class ChatView extends StatefulWidget {
  final String sessionId;
  const ChatView({required this.sessionId, super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  @override
  void initState() {
    super.initState();
    // Kiểm tra trạng thái model ngay sau khi build frame đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkModelAndShowDialog(context);
    });
  }

  void _checkModelAndShowDialog(BuildContext context) {
    if (!mounted) return;

    final modelBloc = context.read<ModelBloc>();
    final modelState = modelBloc.state;

    if (modelState is ModelLoaded) {
      final isDownloaded =
          modelState.gemmaInfo.status == ModelStatus.downloaded;

      // Nếu model chưa download → ChatBloc sẽ emit ChatError.needsModelDownload
      // → banner warning xử lý, không cần dialog
      if (!isDownloaded) return;
      // Chỉ coi là sẵn sàng khi cả Gemma và Gecko đều ready
      if (modelState.gemmaReady && modelState.geckoReady) return;

      // Dispatch StatusChecked để init phần chưa ready (idempotent)
      if (!modelBloc.isInitializingGemma) {
        modelBloc.add(const StatusChecked());
      }

      // Show dialog loading — BlocListener bên trong sẽ tự đóng khi gemmaReady
      _showLoadingDialog();
    } else if (modelState is ModelLoading) {
      // ModelBloc đang loading → chờ init xong
    }
  }

  void _showLoadingDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return BlocListener<ModelBloc, ModelState>(
          listener: (context, state) {
            if (state is ModelLoaded && state.gemmaReady) {
              Navigator.of(context).pop();
              context.read<ChatBloc>().add(const ModelBecameReady());
            }
            if (state is ModelError) {
              Navigator.of(context).pop();
            }
          },
          child: AlertDialog(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Đang nạp model AI vào bộ nhớ...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Model Gemma (2.8GB) đang được load. '
                  'Vui lòng đợi trong giây lát.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.subtleLight,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
          const ScopeSelector(),
          ClearButton(sessionId: widget.sessionId),
        ],
      ),
      body: Column(
        children: [
          // ─── Banner "Chưa tải model" ──────────────────────────────────
          const ModelNotInstalledBanner(),

          // Chat body (loading / error / messages)
          Expanded(
            child: ChatBody(sessionId: widget.sessionId),
          ),

          // Attached files bar
          AttachedFilesBar(sessionId: widget.sessionId),

          // Input bar
          ChatInputBar(sessionId: widget.sessionId),
        ],
      ),
    );
  }
}
