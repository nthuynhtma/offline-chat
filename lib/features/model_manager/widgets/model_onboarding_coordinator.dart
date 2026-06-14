import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

/// Key lưu trong SharedPreferences — đã xem onboarding hay chưa.
const String _kHasSeenOnboarding = 'hasSeenModelOnboarding';

/// Coordinator ở App level, chịu trách nhiệm show dialog onboarding
/// khi lần đầu mở app mà chưa có model AI.
///
/// Luồng:
///   1. Chờ ModelBloc emit ModelLoaded & gemma chưa download
///   2. Show confirm dialog → user chọn Tải hoặc Để sau
///   3. Nếu Tải → show progress dialog (BlocBuilder, barrierDismissible: false)
///   4. Nếu lỗi → show error dialog với [Để sau] / [Thử lại]
///   5. Nếu thành công → đóng dialog + SnackBar
class ModelOnboardingCoordinator extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const ModelOnboardingCoordinator({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<ModelOnboardingCoordinator> createState() =>
      _ModelOnboardingCoordinatorState();
}

class _ModelOnboardingCoordinatorState
    extends State<ModelOnboardingCoordinator> {
  bool _hasSeenOnboarding = false;
  bool _promptCompleted = false;
  bool _isDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_kHasSeenOnboarding) ?? false;
      log_util.log.i('[Onboarding] _loadPrefs: hasSeenOnboarding=$seen');
      if (!mounted) return;
      setState(() {
        _hasSeenOnboarding = seen;
      });
    } catch (e) {
      log_util.log.w('[Onboarding] Lỗi đọc SharedPreferences: $e');
      // Mặc định false — vẫn show onboarding nếu không đọc được prefs
    }
  }

  Future<void> _markSeenOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHasSeenOnboarding, true);
    } catch (e) {
      log_util.log.w('[Onboarding] Lỗi ghi SharedPreferences: $e');
    }
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = true;
      });
    }
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────

  void _showConfirmDialog() {
    // Dùng navigatorKey.currentContext để đảm bảo có Navigator
    final navigatorCtx = widget.navigatorKey.currentContext;
    if (navigatorCtx == null) {
      log_util.log.w('[Onboarding] _showConfirmDialog: navigatorCtx is null');
      return;
    }

    log_util.log.i(
        '[Onboarding] _showConfirmDialog called: _isDialogVisible=$_isDialogVisible, _promptCompleted=$_promptCompleted, mounted=$mounted');
    if (_isDialogVisible || _promptCompleted || !mounted) return;

    _isDialogVisible = true;

    log_util.log.i('[Onboarding] Showing confirm dialog now...');

    // Đánh dấu đã xem onboarding ngay khi dialog xuất hiện lần đầu
    _hasSeenOnboarding = true;
    _markSeenOnboarding();

    showDialog<void>(
      context: navigatorCtx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          title: const Row(
            children: [
              Icon(Icons.download_outlined, color: AppColors.primaryLight),
              SizedBox(width: AppSpacing.sm),
              Text('Tải model AI'),
            ],
          ),
          content: const Text(
            'Để chat được, vui lòng tải model AI.\n\n'
            '• Qwen2.5-1.5B (1.5GB) — model chat chính (mặc định)\n'
            '• Gecko (111MB) — model nhúng văn bản\n\n'
            'Cả hai sẽ được tải cùng lúc, một lần duy nhất và '
            'hoạt động hoàn toàn ngoại tuyến.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                _isDialogVisible = false;
                _promptCompleted = true;
                Navigator.of(ctx, rootNavigator: true).pop();
              },
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx, rootNavigator: true).pop();
                _showProgressDialog();
              },
              child: const Text('Tải xuống'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _isDialogVisible = false;
    });
  }

  void _showProgressDialog() {
    final navigatorCtx = widget.navigatorKey.currentContext;
    if (navigatorCtx == null) {
      log_util.log.w('[Onboarding] _showProgressDialog: navigatorCtx is null');
      return;
    }

    if (!mounted) return;
    log_util.log.i('[Onboarding] _showProgressDialog: dispatching downloads...');
    _isDialogVisible = true;

    showDialog<void>(
      context: navigatorCtx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return BlocBuilder<ModelBloc, ModelState>(
          builder: (innerContext, state) {
            if (state is! ModelLoaded) {
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
                    Text('Đang chuẩn bị tải...'),
                  ],
                ),
              );
            }

            // Lấy active LLM model (default = Qwen2.5)
            final llmModel = state.llmModels.isNotEmpty
                ? state.llmModels.first
                : null;
            final geckoInfo = state.geckoInfo;

            final llmDone = llmModel?.status == ModelStatus.downloaded;
            final geckoDone = geckoInfo.status == ModelStatus.downloaded;
            final llmError = llmModel?.status == ModelStatus.error;
            final geckoError = geckoInfo.status == ModelStatus.error;
            final anyError = llmError || geckoError;
            final allDone = llmDone && geckoDone;

            // Cả hai hoàn tất → đóng dialog + SnackBar
            if (allDone) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) {
                  Navigator.of(ctx, rootNavigator: true).pop();
                  _isDialogVisible = false;
                  _promptCompleted = true;
                  ScaffoldMessenger.of(innerContext).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.white, size: 20),
                          SizedBox(width: AppSpacing.sm),
                          Text(
                              '✅ Model AI đã sẵn sàng! Bạn có thể chat ngay.'),
                        ],
                      ),
                    ),
                  );
                }
              });
            }

            return AlertDialog(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              title: Row(
                children: [
                  Icon(
                    anyError ? Icons.error_outline : Icons.download_outlined,
                    color: anyError ? AppColors.error : AppColors.primaryLight,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(anyError ? 'Tải thất bại' : 'Đang tải model AI'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Qwen2.5 progress ──
                  _buildModelProgressRow(
                    context: innerContext,
                    name: llmModel?.name ?? 'LLM (chat)',
                    info: llmModel ?? const ModelInfo(name: 'Unknown', fileName: '', downloadUrl: '', fileSizeBytes: 0, modelType: ModelType.llm),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // ── Gecko progress ──
                  _buildModelProgressRow(
                    context: innerContext,
                    name: 'Gecko (nhúng)',
                    info: geckoInfo,
                  ),
                ],
              ),
              actions: anyError
                  ? [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          _isDialogVisible = false;
                          _promptCompleted = true;
                        },
                        child: const Text('Để sau'),
                      ),
                      FilledButton(
                        onPressed: () {
                          // Thử lại cả hai
              // Tải active LLM model (Qwen2.5 mặc định)
              final activeFile = innerContext
                  .read<ModelBloc>()
                  .state;
              if (activeFile is ModelLoaded) {
                innerContext
                    .read<ModelBloc>()
                    .add(ModelDownloadRequested(activeFile.activeLlmFileName));
              }
                          innerContext
                              .read<ModelBloc>()
                              .add(const GeckoDownloadStarted());
                        },
                        child: const Text('Thử lại'),
                      ),
                    ]
                  : null,
            );
          },
        );
      },
    ).whenComplete(() {
      _isDialogVisible = false;
    });

    // Dispatch download cả hai model (idempotent — service có guard)
    final blocCtx = widget.navigatorKey.currentContext;
    if (blocCtx != null && mounted) {
      // Lấy active LLM model từ state và download
      final modelState = blocCtx.read<ModelBloc>().state;
      if (modelState is ModelLoaded) {
        blocCtx.read<ModelBloc>().add(ModelDownloadRequested(modelState.activeLlmFileName));
      }
      blocCtx.read<ModelBloc>().add(const GeckoDownloadStarted());
    }
  }

  /// Helper hiển thị progress của từng model.
  Widget _buildModelProgressRow({
    required BuildContext context,
    required String name,
    required ModelInfo info,
  }) {
    final isDone = info.status == ModelStatus.downloaded;
    final isError = info.status == ModelStatus.error;
    final isDownloading = info.status == ModelStatus.downloading;
    final isPending = info.status == ModelStatus.notDownloaded;
    final progress = (info.progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              isDone
                  ? Icons.check_circle
                  : isError
                      ? Icons.error
                      : Icons.hourglass_bottom,
              size: 16,
              color: isDone
                  ? AppColors.success
                  : isError
                      ? AppColors.error
                      : AppColors.subtleLight,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              name,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (isDone)
              const Text(
                ' ✓',
                style: TextStyle(color: AppColors.success, fontSize: 12),
              ),
          ],
        ),
        if (isDownloading) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: info.progress,
              minHeight: 6,
              backgroundColor:
                  AppColors.primaryLight.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$progress%',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.subtleLight, fontSize: 11),
          ),
        ],
        if (isPending)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Đang chờ tải...',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.subtleLight, fontSize: 11),
            ),
          ),
        if (isError)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              info.errorMessage ?? 'Lỗi',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.error, fontSize: 11),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // BlocBuilder chỉ để log — không ảnh hưởng UI
    context.watch<ModelBloc>().state; // trigger rebuild khi state thay đổi

    log_util.log.i(
        '[Onboarding] build() called, flags: _promptCompleted=$_promptCompleted, _isDialogVisible=$_isDialogVisible, _hasSeenOnboarding=$_hasSeenOnboarding, state=${context.read<ModelBloc>().state.runtimeType}');

    return BlocListener<ModelBloc, ModelState>(
      listenWhen: (prev, curr) {
        final p0 = !_promptCompleted;
        final p1 = !_isDialogVisible;
        final p2 = !_hasSeenOnboarding;
        final p3 = curr is ModelLoaded;
        final p4 = curr is ModelLoaded &&
            curr.llmModels.every((m) => m.status == ModelStatus.notDownloaded);
        final result = p0 && p1 && p2 && p3 && p4;

        final llmStatuses = curr is ModelLoaded
            ? curr.llmModels.map((m) => '${m.fileName}=${m.status.name}').join(', ')
            : 'N/A';
        log_util.log.i(
            '[Onboarding] listenWhen check: '
            '_promptCompleted=$_promptCompleted(p0=$p0), '
            '_isDialogVisible=$_isDialogVisible(p1=$p1), '
            '_hasSeenOnboarding=$_hasSeenOnboarding(p2=$p2), '
            'curr=ModelLoaded(p3=$p3), '
            'llmStatuses=[$llmStatuses](p4=$p4) '
            '→ result=$result');

        return result;
      },
      listener: (context, state) {
        log_util.log.i(
            '[Onboarding] listener triggered! Showing confirm dialog...');
        // Dùng postFrameCallback để đảm bảo Navigator/Overlay sẵn sàng
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showConfirmDialog();
          }
        });
      },
      child: widget.child,
    );
  }
}