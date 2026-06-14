import 'dart:async';

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

class ChatView extends StatefulWidget {
  final String sessionId;
  const ChatView({required this.sessionId, super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  bool _isModelLoadingDialogVisible = false;
  NavigatorState? _modelLoadingDialogNavigator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkModelAndShowDialog(context);
    });
  }

  void _checkModelAndShowDialog(BuildContext context) {
    if (!mounted) return;

    final modelBloc = context.read<ModelBloc>();
    final modelState = modelBloc.state;

    if (modelState is ModelLoaded) {
      // Kiểm tra active model đã download chưa
      final activeModel = modelState.llmModels.firstWhere(
        (m) => m.fileName == modelState.activeLlmFileName,
        orElse: () => modelState.llmModels.first,
      );
      final isLlmDownloaded =
          activeModel.status == ModelStatus.downloaded;

      if (!isLlmDownloaded) {
        _hideLoadingDialog();
        return;
      }

      if (modelState.gemmaReady) {
        _hideLoadingDialog();
        return;
      }

      if (!modelBloc.isInitializingGemma) {
        modelBloc.add(const StatusChecked());
      }

      _showLoadingDialog();
    } else if (modelState is ModelLoading) {
      // ModelBloc đang loading → chờ init xong
    }
  }

  void _handleModelStateChanged(BuildContext context, ModelState state) {
    if (!mounted) return;

    if (state is ModelLoaded) {
      final activeModel = state.llmModels.firstWhere(
        (m) => m.fileName == state.activeLlmFileName,
        orElse: () => state.llmModels.first,
      );
      final isLlmDownloaded =
          activeModel.status == ModelStatus.downloaded;

      if (!isLlmDownloaded) {
        _hideLoadingDialog();
        return;
      }

      if (state.gemmaReady) {
        final wasShowingDialog = _isModelLoadingDialogVisible;
        _hideLoadingDialog();
        if (wasShowingDialog) {
          context.read<ChatBloc>().add(const ModelBecameReady());
        }
        return;
      }

      if (!context.read<ModelBloc>().isInitializingGemma) {
        _hideLoadingDialog();
      }
    } else if (state is ModelError) {
      _hideLoadingDialog();
    }
  }

  void _showLoadingDialog() {
    if (!mounted) return;
    if (_isModelLoadingDialogVisible) return;

    _isModelLoadingDialogVisible = true;
    _modelLoadingDialogNavigator = Navigator.of(context, rootNavigator: true);

    unawaited(showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return const AlertDialog(
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                'Đang nạp model AI vào bộ nhớ...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Model AI đang được load. '
                'Vui lòng đợi trong giây lát.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.subtleLight,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      _isModelLoadingDialogVisible = false;
      _modelLoadingDialogNavigator = null;
    }));
  }

  void _hideLoadingDialog() {
    if (!_isModelLoadingDialogVisible) return;

    final navigator = _modelLoadingDialogNavigator;
    _isModelLoadingDialogVisible = false;
    _modelLoadingDialogNavigator = null;

    if (navigator != null && navigator.mounted && navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void dispose() {
    _hideLoadingDialog();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ModelBloc, ModelState>(
      listener: _handleModelStateChanged,
      child: Scaffold(
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
            const ModelNotInstalledBanner(),
            Expanded(
              child: ChatBody(sessionId: widget.sessionId),
            ),
            AttachedFilesBar(sessionId: widget.sessionId),
            ChatInputBar(sessionId: widget.sessionId),
          ],
        ),
      ),
    );
  }
}