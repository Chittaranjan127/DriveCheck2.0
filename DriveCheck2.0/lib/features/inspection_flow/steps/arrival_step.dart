import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/services/inspections_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/auth_provider.dart';
import '../../auth/auth_state.dart';
import '../../home/inspections_provider.dart';
import '../inspection_flow_provider.dart';
import '../prompts/step_intro_prompts.dart';
import '../state/assistant_utterance_provider.dart';

/// First checkpoint: "Have you arrived?". Tapping "Yes, I've arrived":
///   1. Marks the `arrival` step as completed on the backend (bumps the
///      parent inspection's completedStepCount and flips its status from
///      `scheduled` → `inProgress`).
///   2. Refreshes the home list so the inspection card immediately reflects
///      "In progress".
///   3. Advances to step 2.
///
/// A "Directions" CTA hands off to Google Maps with the pickup coordinates
/// (or area text as a fallback when coords are missing).
class ArrivalStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final String customerArea;
  final double? latitude;
  final double? longitude;
  final String? address;
  final VoidCallback onArrived;

  const ArrivalStep({
    super.key,
    required this.inspectionId,
    required this.customerArea,
    required this.onArrived,
    this.latitude,
    this.longitude,
    this.address,
  });

  @override
  ConsumerState<ArrivalStep> createState() => _ArrivalStepState();
}

class _ArrivalStepState extends ConsumerState<ArrivalStep> {
  static const _stepId = 'arrival';
  final _service = InspectionsService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Fire the per-step intro through the shell-level assistant bubble.
    // PostFrame so Riverpod's NotifierProvider has finished its first
    // build before we mutate it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Always push the intro so the bubble reflects the active step on
      // back-nav. If arrival was already confirmed (server-side or earlier
      // in this session — the flow notifier seeds arrivedAt from
      // completedStepCount), update silently so we don't auto-play
      // "have you arrived?" again.
      final flowState = ref.read(inspectionFlowProvider(widget.inspectionId));
      final alreadyArrived = flowState.arrivedAt != null;
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      final t = ref.read(translationsProvider);
      final auth = ref.read(authProvider);
      final name = auth is AuthAuthenticated ? auth.user.name : null;
      final intro = stepIntroFor(_stepId, lang, t: t, name: name);
      ref.read(assistantUtteranceProvider.notifier).say(
            intro.spokenSsml,
            display: intro.display,
            autoplay: !alreadyArrived,
          );
    });
  }

  Future<void> _confirmArrival() async {
    final state = ref.read(inspectionFlowProvider(widget.inspectionId));
    if (state.arrivedAt != null) {
      // User already confirmed earlier in this session — just move on,
      // no extra backend write.
      widget.onArrived();
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.updateStep(
        widget.inspectionId,
        _stepId,
        status: 'completed',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.couldNotSave}: $e',
            style: t.style(AppTextStyles.body))),
      );
      return;
    }

    if (!mounted) return;
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).markArrived();
    // Re-fetch /inspections so the home card shows "In progress" the next
    // time the user backs out of the flow.
    unawaited(ref.read(inspectionsAsyncProvider.notifier).refresh());

    setState(() => _saving = false);
    widget.onArrived();
  }

  Future<void> _openDirections() async {
    final hasCoords = widget.latitude != null && widget.longitude != null;
    final coordPair = hasCoords ? '${widget.latitude},${widget.longitude}' : null;
    final placeQuery = (widget.address?.trim().isNotEmpty == true
            ? widget.address!
            : widget.customerArea)
        .trim();
    final encodedQuery = Uri.encodeComponent(placeQuery);

    // Try in order: native Google Maps app → web Google Maps → Apple Maps.
    final candidates = <Uri>[
      if (hasCoords)
        Uri.parse('comgooglemaps://?daddr=$coordPair&directionsmode=driving'),
      Uri.parse('comgooglemaps://?daddr=$encodedQuery&directionsmode=driving'),
      Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${hasCoords ? coordPair : encodedQuery}&travelmode=driving'),
      Uri.parse(
          'https://maps.apple.com/?daddr=${hasCoords ? coordPair : encodedQuery}&dirflg=d'),
    ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {
        // Try the next candidate.
      }
    }

    if (mounted) {
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.couldNotOpenMaps,
            style: t.style(AppTextStyles.body))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final state = ref.watch(inspectionFlowProvider(widget.inspectionId));
    final arrived = state.arrivedAt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.location_on_rounded,
                    color: AppColors.onPrimary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.customerLocation,
                        style: AppTextStyles.caption
                            .copyWith(letterSpacing: 0.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(widget.customerArea, style: t.style(AppTextStyles.heading3)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(t.arrivalQuestion,
            style: t.style(AppTextStyles.heading1), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          t.arrivalHelp,
          style: t.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        _BigAnswerButton(
          label: arrived ? t.arrivedConfirmed : t.yesArrived,
          icon: arrived ? Icons.check_circle_rounded : Icons.where_to_vote_rounded,
          color: AppColors.success,
          filled: true,
          loading: _saving,
          onTap: _saving ? null : _confirmArrival,
        ),
        const SizedBox(height: 12),
        _BigAnswerButton(
          label: t.getDirections,
          icon: Icons.directions_rounded,
          color: AppColors.primary,
          filled: false,
          onTap: _saving ? null : _openDirections,
        ),
      ],
    );
  }
}

/// Fire-and-forget for futures we don't want to await. Same intent as
/// `package:pedantic/unawaited.dart` but without the dep.
void unawaited(Future<void> _) {}

class _BigAnswerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _BigAnswerButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onCtaDark : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Opacity(
        opacity: onTap == null && !loading ? 0.55 : 1,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: filled ? 0 : 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                )
              else
                Icon(icon, color: fg, size: 26),
              const SizedBox(width: 12),
              Text(
                label,
                style: AppTextStyles.button.copyWith(color: fg, fontSize: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
