import 'package:flutter/material.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Voice instruction strip. Will auto-play TTS audio when ElevenLabs wired.
/// For now: visual bar with speaker icon + text — tappable to "replay".
class VoiceInstructionBar extends StatelessWidget {
  final String instruction;
  final Translations t;
  final VoidCallback? onReplay;

  const VoiceInstructionBar({
    super.key,
    required this.instruction,
    required this.t,
    this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: const Icon(Icons.volume_up_rounded, color: AppColors.onPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(instruction,
                style: t.style(AppTextStyles.body).copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500, height: 1.4)),
          ),
          if (onReplay != null)
            IconButton(
              icon: const Icon(Icons.replay_rounded, color: AppColors.primary, size: 20),
              onPressed: onReplay,
            ),
        ],
      ),
    );
  }
}
