import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/models/inspection_step.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../prompts/step_intro_prompts.dart';
import '../state/assistant_utterance_provider.dart';

/// Stand-in for not-yet-built step types. Shows step info + a "Skip" advance.
/// Also fires the shell-level assistant intro on mount so even unbuilt
/// steps get a friendly voice prompt.
class PlaceholderStep extends ConsumerStatefulWidget {
  final InspectionStep step;
  final String title;
  final String instruction;
  final VoidCallback onAdvance;

  const PlaceholderStep({
    super.key,
    required this.step,
    required this.title,
    required this.instruction,
    required this.onAdvance,
  });

  @override
  ConsumerState<PlaceholderStep> createState() => _PlaceholderStepState();
}

class _PlaceholderStepState extends ConsumerState<PlaceholderStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      final t = ref.read(translationsProvider);
      final intro = stepIntroFor(widget.step.id, lang, t: t);
      ref.read(assistantUtteranceProvider.notifier)
          .say(intro.spokenSsml, display: intro.display);
    });
  }

  IconData _iconFor() {
    switch (widget.step.type) {
      case StepType.arrival:    return Icons.where_to_vote_rounded;
      case StepType.photo:      return Icons.photo_camera_rounded;
      case StepType.multiPhoto: return Icons.burst_mode_rounded;
      case StepType.audio:      return Icons.mic_rounded;
      case StepType.voiceQA:    return Icons.record_voice_over_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
            child: Icon(_iconFor(), size: 64, color: AppColors.textHint),
          ),
        ),
        const SizedBox(height: 24),
        Text(widget.title, style: t.style(AppTextStyles.heading2)),
        const SizedBox(height: 6),
        Text(widget.instruction,
            style: t.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary)),
        const Spacer(),
        ElevatedButton(onPressed: widget.onAdvance, child: Text(t.next, style: AppTextStyles.button)),
      ],
    );
  }
}
