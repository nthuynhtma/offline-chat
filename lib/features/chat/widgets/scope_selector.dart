import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/document_constants.dart';
import 'package:offline_chat/features/chat/bloc/chat_bloc.dart';

/// PopupMenu chọn KnowledgeScope cho session hiện tại.
class ScopeSelector extends StatelessWidget {
  const ScopeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (prev, curr) =>
          prev.knowledgeScope != curr.knowledgeScope,
      builder: (context, state) {
        final currentScope = state.knowledgeScope;
        return PopupMenuButton<KnowledgeScope>(
          tooltip: 'Phạm vi kiến thức',
          icon: Icon(
            Icons.travel_explore,
            color: currentScope == KnowledgeScope.attachedAndGlobal
                ? AppColors.primaryLight
                : null,
          ),
          onSelected: (scope) {
            context.read<ChatBloc>().add(KnowledgeScopeChanged(scope));
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: KnowledgeScope.attachedOnly,
              child: ScopeOption(
                icon: Icons.attach_file,
                label: 'Chỉ session này',
                subtitle: 'Chỉ tài liệu gắn vào session',
                isSelected: currentScope == KnowledgeScope.attachedOnly,
              ),
            ),
            PopupMenuItem(
              value: KnowledgeScope.globalOnly,
              child: ScopeOption(
                icon: Icons.language,
                label: 'Chỉ toàn cục',
                subtitle: 'Tài liệu chia sẻ chung',
                isSelected: currentScope == KnowledgeScope.globalOnly,
              ),
            ),
            PopupMenuItem(
              value: KnowledgeScope.attachedAndGlobal,
              child: ScopeOption(
                icon: Icons.explore,
                label: 'Tất cả',
                subtitle: 'Session + toàn cục',
                isSelected: currentScope == KnowledgeScope.attachedAndGlobal,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ScopeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;

  const ScopeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isSelected ? AppColors.primaryLight : AppColors.subtleLight,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primaryLight : null,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.subtleLight,
                ),
              ),
            ],
          ),
        ),
        if (isSelected)
          const Icon(Icons.check, size: 18, color: AppColors.primaryLight),
      ],
    );
  }
}
