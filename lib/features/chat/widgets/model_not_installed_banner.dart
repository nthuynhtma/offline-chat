import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/model_manager/bloc/model_bloc.dart';
import 'package:offline_chat/services/model_manager/model_manager_service.dart';

/// Banner hiển thị khi model chưa được tải.
/// Đọc trực tiếp từ ModelBloc thay vì ChatBloc để hiển thị độc lập.
class ModelNotInstalledBanner extends StatelessWidget {
  const ModelNotInstalledBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ModelBloc, ModelState>(
      buildWhen: (prev, curr) {
        final prevNeeds = prev is ModelLoaded &&
            prev.llmModels.every((m) => m.status != ModelStatus.downloaded);
        final currNeeds = curr is ModelLoaded &&
            curr.llmModels.every((m) => m.status != ModelStatus.downloaded);
        return prevNeeds != currNeeds;
      },
      builder: (context, state) {
        final shouldShow = state is ModelLoaded &&
            state.llmModels.every((m) => m.status != ModelStatus.downloaded);

        if (shouldShow) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: AppColors.warning.withValues(alpha: 0.2),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(child: Text('Model AI chưa được tải')),
                TextButton(
                  onPressed: () => context.push('/settings/models'),
                  child: const Text('Tải'),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}