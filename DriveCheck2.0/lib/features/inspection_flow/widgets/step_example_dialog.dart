import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/models/inspection_step.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// "Here's what a good capture looks like" preview the jockey sees the
/// first time they land on a step. Shows the reference image (when one
/// is bundled) + step title + the spec's instruction, with a small
/// countdown ring that auto-dismisses the modal after a few seconds.
///
/// Designed to be unobtrusive — tap anywhere to dismiss early, or
/// wait for the timer. Used by [inspection_flow_screen] which tracks
/// "seen" steps per session so a back-nav doesn't re-pop the modal.
class StepExampleDialog extends StatefulWidget {
  final InspectionStep step;
  final Translations t;
  final String title;
  final String instruction;

  /// How long the modal stays up before auto-dismissing. Long enough
  /// to read a short instruction, short enough to not be annoying.
  static const Duration autoDismiss = Duration(seconds: 5);

  const StepExampleDialog({
    super.key,
    required this.step,
    required this.t,
    required this.title,
    required this.instruction,
  });

  @override
  State<StepExampleDialog> createState() => _StepExampleDialogState();

  /// Convenience: pops the modal as a [showDialog] entry. Returns the
  /// future from `showDialog` so the caller can `await` if it cares.
  static Future<void> show(
    BuildContext context, {
    required InspectionStep step,
    required Translations t,
    required String title,
    required String instruction,
  }) {
    return showDialog<void>(
      context: context,
      // Barrier dismiss + low-opacity scrim — the modal is informational,
      // not a question. The user shouldn't feel trapped.
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => StepExampleDialog(
        step: step,
        t: t,
        title: title,
        instruction: instruction,
      ),
    );
  }
}

class _StepExampleDialogState extends State<StepExampleDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _countdown = AnimationController(
      vsync: this,
      duration: StepExampleDialog.autoDismiss,
    )..forward();
    _autoCloseTimer = Timer(StepExampleDialog.autoDismiss, _close);
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _countdown.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final hasRef = (widget.step.referenceImagePath ?? '').isNotEmpty;
    return GestureDetector(
      // Tap-to-dismiss covers both the scrim (handled by showDialog's
      // barrierDismissible) AND the modal itself, so the jockey
      // doesn't have to aim for a specific button.
      onTap: _close,
      behavior: HitTestBehavior.opaque,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasRef)
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.asset(
                    widget.step.referenceImagePath!,
                    fit: BoxFit.cover,
                    // No bundled file → fall back to a soft placeholder
                    // so the modal still looks deliberate.
                    errorBuilder: (_, _, _) => const _PlaceholderHero(),
                  ),
                )
              else
                const _PlaceholderHero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            t.example.toUpperCase(),
                            style: t.style(const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            )),
                          ),
                        ),
                        const Spacer(),
                        // Countdown ring — visually previews the
                        // auto-dismiss; rebuilds via AnimatedBuilder
                        // off the same controller that fires _close.
                        AnimatedBuilder(
                          animation: _countdown,
                          builder: (_, _) {
                            return SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                value: 1 - _countdown.value,
                                backgroundColor: AppColors.border,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        AppColors.primary),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(widget.title,
                        style: t.style(AppTextStyles.heading2)
                            .copyWith(fontSize: 20)),
                    const SizedBox(height: 6),
                    Text(
                      widget.instruction,
                      style: t.style(AppTextStyles.body).copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft brand-tinted block with the step's icon — rendered when the
/// reference image isn't bundled (most steps in dev). Same aspect
/// ratio as the real hero so the modal doesn't reflow if/when an
/// image is added later.
class _PlaceholderHero extends StatelessWidget {
  const _PlaceholderHero();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryLight, AppColors.primary],
          ),
        ),
        child: const Center(
          child: Icon(Icons.image_search_rounded,
              size: 56, color: Colors.white),
        ),
      ),
    );
  }
}
