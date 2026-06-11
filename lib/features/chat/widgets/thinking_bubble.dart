import 'package:flutter/material.dart';

import 'package:offline_chat/core/constants/app_colors.dart';
import 'package:offline_chat/core/constants/app_spacing.dart';

/// Bubble "AI đang suy nghĩ..." với 3 chấm animation.
class ThinkingBubble extends StatefulWidget {
  final String sessionId;
  
  const ThinkingBubble({
    required this.sessionId,
    super.key,
  });

  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar AI
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryLight.withOpacity(0.1),
            child: const Icon(Icons.agriculture, size: 18, color: AppColors.primaryLight),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Bubble với 3 chấm
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) {
                      final delay = index * 0.2;
                      final t = (_animationController.value - delay)
                          .clamp(0.0, 1.0);
                      final scale = (t < 0.5)
                          ? (t / 0.5) * 0.5 + 0.5   // 0.5 → 1.0
                          : (1.0 - (t - 0.5) / 0.5) * 0.5 + 0.5; // 1.0 → 0.5
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Transform.scale(
                          scale: scale,
                          child: const CircleAvatar(
                            radius: 4,
                            backgroundColor: AppColors.subtleLight,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
