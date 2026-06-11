import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';

/// Banner hiển thị khi model chưa được tải.
class ModelNotInstalledBanner extends StatelessWidget {
  const ModelNotInstalledBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (prev, curr) {
        final prevNeeds = prev is ChatError && prev.needsModelDownload;
        final currNeeds = curr is ChatError && curr.needsModelDownload;
        return prevNeeds != currNeeds;
      },
      builder: (context, state) {
        if (state is ChatError && state.needsModelDownload) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: AppColors.warning.withOpacity(0.2),
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
