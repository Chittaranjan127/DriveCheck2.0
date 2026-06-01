import 'package:flutter/material.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Slim step indicator: "Step N of M" + filled bar.
class StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final Translations t;

  const StepProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final progress = currentStep / totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${t.step} $currentStep ${t.of} $totalSteps',
                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            Text('${(progress * 100).round()}%',
                style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}
