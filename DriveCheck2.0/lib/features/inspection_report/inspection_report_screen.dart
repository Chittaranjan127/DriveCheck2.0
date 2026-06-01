import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/translations.dart';
import '../../core/models/inspection_report.dart';
import '../../core/services/inspections_service.dart';
import '../../core/services/language_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../home/inspections_provider.dart';
import '../inspection_flow/state/assistant_utterance_provider.dart';
import '../inspection_flow/widgets/assistant_bottom_bar.dart';
import 'inspection_report_provider.dart';

/// Post-inspection report shown after the test-drive saves. Pulls the
/// aggregated report from `/inspections/{id}/report` — the Lambda
/// runs gpt-4o to produce a low-anchored price + a negotiation pitch
/// the jockey can read out — then offers two CTAs:
///   - "Customer agreed"     → writes an InspectionLead (closed deal)
///   - "Customer not agreed" → opens a sheet for the customer's
///                             counter-price, then writes an
///                             InspectionTicket for follow-up
///
/// The jockey pitch is playable through ElevenLabs TTS so the jockey
/// can rehearse it before reading it out to the customer, and replay
/// it as many times as they want.
class InspectionReportScreen extends ConsumerStatefulWidget {
  final String inspectionId;
  const InspectionReportScreen({super.key, required this.inspectionId});

  @override
  ConsumerState<InspectionReportScreen> createState() =>
      _InspectionReportScreenState();
}

class _InspectionReportScreenState
    extends ConsumerState<InspectionReportScreen> {
  final _service = InspectionsService();

  // Pitch playback. Shared singleton TtsService so the bubble lifecycle
  // already cleans up audio on dispose; this widget just subscribes to
  // its state stream to flip the play/pause icon.
  final _tts = TtsService.instance;
  StreamSubscription<PlayerState>? _ttsSub;
  bool _pitchPlaying = false;
  // True from the moment the user taps Play until the audio actually
  // starts coming out of the speaker. Covers the ElevenLabs fetch
  // round-trip (~1-3s for a fresh script). The play button shows a
  // spinner while this is true so the jockey doesn't think the tap
  // missed.
  bool _pitchLoading = false;
  // Fires the "inspection complete — tap play to hear the pitch"
  // announcement exactly once per landing on this screen, after the
  // report data resolves. Re-landing (back-nav into a completed
  // inspection) re-mounts and re-fires, which is what we want.
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _ttsSub = _tts.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _pitchPlaying = s == PlayerState.playing;
        // Loading clears the moment we hear ANY player state — playing
        // means TTS started; stopped/completed means it ended or
        // never began (the speak call short-circuited).
        if (s != PlayerState.disposed) _pitchLoading = false;
      });
    });
  }

  ReportKey _key() {
    final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.english;
    return ReportKey(widget.inspectionId, _langCode(lang));
  }

  @override
  void dispose() {
    _ttsSub?.cancel();
    unawaited(_tts.stop());
    // Wipe the AI bar so the announcement doesn't linger on the
    // next screen (back-nav to home). Wrapped in try/catch because
    // the providerContainer can be torn down before us.
    try {
      ref.read(assistantUtteranceProvider.notifier).clear();
    } catch (_) {}
    super.dispose();
  }

  /// Fires once when the report data first resolves: the AI bar reads
  /// "inspection complete — tap play to hear the pitch" out loud, then
  /// the jockey can tap the Play button on the pitch card to hear the
  /// actual negotiation script.
  void _maybeAnnounce() {
    if (_announced) return;
    _announced = true;
    final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.english;
    final intro = _reportArrivalIntro(lang);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(assistantUtteranceProvider.notifier).say(
            intro.spoken,
            display: intro.display,
            autoplay: true,
          );
    });
  }

  Future<void> _retry() async {
    // Explicit re-fetch through the cached provider — refreshes the
    // backend pricing call (one new gpt-4o roundtrip) and updates
    // every listener of the cache.
    await ref.read(inspectionReportProvider(_key()).notifier).refresh();
  }

  Future<void> _playPitch(ReportJockeyPitch pitch) async {
    if (_pitchPlaying || _pitchLoading) {
      // Either currently playing or fetching — second tap stops.
      setState(() => _pitchLoading = false);
      await _tts.stop();
      return;
    }
    if (pitch.script.trim().isEmpty) return;
    setState(() => _pitchLoading = true);
    // Wrap in SSML so ElevenLabs respects natural pacing. The script
    // is already one cohesive paragraph from the model — no need to
    // stitch sub-fields together.
    final ssml = '<speak>${pitch.script}</speak>';
    try {
      await _tts.speak(ssml);
    } finally {
      // Belt-and-suspenders: the playerState listener will normally
      // flip loading off when `playing` arrives, but if `speak()`
      // throws or returns without ever firing a state event we'd
      // otherwise be stuck on the spinner.
      if (mounted && _pitchLoading && !_pitchPlaying) {
        setState(() => _pitchLoading = false);
      }
    }
  }

  Future<void> _submitLead(InspectionReport report) async {
    final price = report.pricing?.estimatedPriceInr ?? 0;
    try {
      await _service.createLead(
        widget.inspectionId,
        agreedPriceInr: price,
        aiPriceInr: price,
      );
    } catch (_) {
      if (!mounted) return;
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.submitFailed,
            style: t.style(AppTextStyles.body))),
      );
      return;
    }
    unawaited(ref.read(inspectionsAsyncProvider.notifier).refresh());
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _submitTicket(
    InspectionReport report, {
    required int customerPriceInr,
    String? notes,
  }) async {
    final price = report.pricing?.estimatedPriceInr ?? 0;
    try {
      await _service.createTicket(
        widget.inspectionId,
        outcome: TicketOutcome.countered,
        aiPriceInr: price,
        customerPriceInr: customerPriceInr,
        notes: notes,
      );
    } catch (_) {
      if (!mounted) return;
      final t = ref.read(translationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.submitFailed,
            style: t.style(AppTextStyles.body))),
      );
      return;
    }
    unawaited(ref.read(inspectionsAsyncProvider.notifier).refresh());
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportTitle, style: t.style(AppTextStyles.heading3)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        // ref.watch on the cached AsyncNotifierProvider — the first
        // mount fires the actual HTTP/gpt-4o roundtrip; every revisit
        // reads the already-resolved [AsyncData] from the provider
        // cache. No more "again and again" requests for the same
        // inspection + language.
        child: ref.watch(inspectionReportProvider(_key())).when(
              loading: () => _Loading(t: t),
              error: (e, _) => _ErrorPane(
                t: t,
                message: e.toString(),
                onRetry: _retry,
              ),
              data: (report) {
                _maybeAnnounce();
                return _ReportBody(
                  t: t,
                  report: report,
                  pitchPlaying: _pitchPlaying,
                  pitchLoading: _pitchLoading,
                  onPlayPitch: () {
                    final pitch = report.jockeyPitch;
                    if (pitch != null) _playPitch(pitch);
                  },
                  onAgreed: () => _submitLead(report),
                  onNotAgreed: () => _openCounterSheet(report),
                );
              },
            ),
      ),
    );
  }

  Future<void> _openCounterSheet(InspectionReport report) async {
    final t = ref.read(translationsProvider);
    final result = await showModalBottomSheet<_CounterResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _CounterSheet(
          t: t,
          aiPriceInr: report.pricing?.estimatedPriceInr ?? 0,
        ),
      ),
    );
    if (result != null) {
      await _submitTicket(report,
          customerPriceInr: result.priceInr, notes: result.notes);
    }
  }
}

String _langCode(AppLanguage l) {
  switch (l) {
    case AppLanguage.english: return 'en';
    case AppLanguage.hindi:   return 'hi';
    case AppLanguage.telugu:  return 'te';
    case AppLanguage.bengali: return 'bn';
  }
}

class _Loading extends StatelessWidget {
  final Translations t;
  const _Loading({required this.t});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 36, height: 36,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 16),
            Text(t.preparingReport,
                textAlign: TextAlign.center,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final Translations t;
  final String message;
  final VoidCallback onRetry;
  const _ErrorPane({
    required this.t,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded,
                  color: AppColors.onCtaDark),
              label: Text(t.tryAgain,
                  style: t.style(AppTextStyles.button)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Body ------------------------------------------------------

class _ReportBody extends StatelessWidget {
  final Translations t;
  final InspectionReport report;
  final bool pitchPlaying;
  final bool pitchLoading;
  final VoidCallback onPlayPitch;
  final VoidCallback onAgreed;
  final VoidCallback onNotAgreed;

  const _ReportBody({
    required this.t,
    required this.report,
    required this.pitchPlaying,
    required this.pitchLoading,
    required this.onPlayPitch,
    required this.onAgreed,
    required this.onNotAgreed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CarHeader(report: report, t: t),
                const SizedBox(height: 16),
                _PriceCard(
                  t: t,
                  pricing: report.pricing,
                  quotedPriceInr: report.car.quotedPriceInr,
                  marketReference: report.marketReference,
                ),
                if (report.bridgeToAsk != null) ...[
                  const SizedBox(height: 16),
                  _BridgeToAskCard(t: t, bridge: report.bridgeToAsk!),
                ],
                if (report.nextSteps != null) ...[
                  const SizedBox(height: 16),
                  _NextStepsCard(t: t, nextSteps: report.nextSteps!),
                ],
                if (report.jockeyPitch != null) ...[
                  const SizedBox(height: 16),
                  _JockeyPitchCard(
                    t: t,
                    pitch: report.jockeyPitch!,
                    isPlaying: pitchPlaying,
                    isLoading: pitchLoading,
                    onPlay: onPlayPitch,
                  ),
                ],
              ],
            ),
          ),
        ),
        // AI bar reads the "inspection complete — tap play to hear the
        // pitch" announcement on landing. Sits above the action footer
        // so the jockey sees it without scrolling.
        const AssistantBottomBar(),
        _Footer(
          t: t,
          aiPriceInr: report.pricing?.estimatedPriceInr,
          onAgreed: onAgreed,
          onNotAgreed: onNotAgreed,
        ),
      ],
    );
  }
}

class _CarHeader extends StatelessWidget {
  final InspectionReport report;
  final Translations t;
  const _CarHeader({required this.report, required this.t});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (report.car.model != null && report.car.model!.isNotEmpty) report.car.model!,
      if (report.car.yearOfMake != null) report.car.yearOfMake.toString(),
      if (report.car.fuelType != null && report.car.fuelType!.isNotEmpty)
        report.car.fuelType!,
      if (report.car.kmDriven != null) '${_formatNum(report.car.kmDriven!)} km',
    ];
    final subtitle = parts.join(' · ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.car.title,
              style: t.style(AppTextStyles.heading2).copyWith(fontSize: 22)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary)),
          ],
          if (report.customer.name != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(report.customer.name!,
                    style: t.style(AppTextStyles.caption)
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final Translations t;
  final ReportPricing? pricing;
  // Seller's asking price from the booking, if it was captured. Shown
  // as a small "Seller quoted: ₹X" subline above the AI estimate so
  // the jockey sees both numbers and can defend the gap.
  final int? quotedPriceInr;
  // Condition-neutral market band for the make/model/year/km. Shown
  // as a sub-line under the fair range so the jockey can answer
  // "but cars like this sell for so much more!" with concrete numbers.
  final ReportMarketReference? marketReference;
  const _PriceCard({
    required this.t,
    required this.pricing,
    this.quotedPriceInr,
    this.marketReference,
  });

  @override
  Widget build(BuildContext context) {
    if (pricing == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          t.reportLoadFailed,
          style: t.style(AppTextStyles.body)
              .copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.ctaDark],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seller's asking price — small subline above the big AI
          // estimate. Hidden when there's no quote on file so the
          // card stays clean for unsolicited inspections.
          if (quotedPriceInr != null) ...[
            Row(
              children: [
                Text(t.sellerQuoted.toUpperCase(),
                    style: t.style(const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ))),
                const SizedBox(width: 6),
                Text(
                  _formatInr(quotedPriceInr!),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Text(t.estimatedPrice.toUpperCase(),
              style: t.style(const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ))),
          const SizedBox(height: 6),
          Text(_formatInr(pricing!.estimatedPriceInr),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              )),
          const SizedBox(height: 4),
          Text(
            '${t.fairRange}: ${_formatInr(pricing!.rangeLowInr)} – '
            '${_formatInr(pricing!.rangeHighInr)}',
            style: t.style(const TextStyle(
              color: Colors.white70, fontSize: 13,
            )),
          ),
          if (marketReference != null && marketReference!.rangeHighInr > 0) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 6),
                  child: Icon(Icons.storefront_rounded,
                      size: 13, color: Colors.white60),
                ),
                Expanded(
                  child: Text(
                    '${t.marketRange}: '
                    '${_formatInr(marketReference!.rangeLowInr)} – '
                    '${_formatInr(marketReference!.rangeHighInr)}',
                    style: t.style(const TextStyle(
                      color: Colors.white60, fontSize: 12,
                    )),
                  ),
                ),
              ],
            ),
          ],
          if (pricing!.factors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            ...pricing!.factors.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 6, color: Colors.white70),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(f,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${t.aiConfidence}: ${(pricing!.confidence * 100).round()}%',
              style: t.style(const TextStyle(
                color: Colors.white70, fontSize: 11,
              )),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bridge-to-ask card. Surfaces the AI's gap-closing offer when the
/// seller's quoted price is above the recommended offer: a short
/// pitch line plus the specific repairable issues that, if fixed,
/// would let Cars24 match the seller's number.
class _BridgeToAskCard extends StatelessWidget {
  final Translations t;
  final ReportBridgeToAsk bridge;
  const _BridgeToAskCard({required this.t, required this.bridge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handshake_rounded,
                  color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t.bridgeToAskTitle} · ${_formatInr(bridge.targetPriceInr)}',
                  style: t.style(const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
          if (bridge.pitchLine.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(bridge.pitchLine,
                style: t.style(const TextStyle(
                    fontSize: 14, height: 1.45,
                    color: AppColors.textPrimary))),
          ],
          if (bridge.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...bridge.issues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.build_circle_rounded,
                          size: 16, color: AppColors.success),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(issue,
                          style: t.style(const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: AppColors.textPrimary))),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextStepsCard extends StatelessWidget {
  final Translations t;
  final ReportNextSteps nextSteps;
  const _NextStepsCard({required this.t, required this.nextSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.flag_rounded, color: AppColors.warning, size: 22),
            const SizedBox(width: 8),
            Text(t.whatToDoNext,
                style: t.style(const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          const SizedBox(height: 8),
          Text(nextSteps.instruction,
              style: t.style(const TextStyle(height: 1.4, fontSize: 14))),
          if (nextSteps.etiquetteTips.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...nextSteps.etiquetteTips.map(
              (tip) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tip,
                          style: t.style(AppTextStyles.caption).copyWith(
                              color: AppColors.textPrimary, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JockeyPitchCard extends StatelessWidget {
  final Translations t;
  final ReportJockeyPitch pitch;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPlay;
  const _JockeyPitchCard({
    required this.t,
    required this.pitch,
    required this.isPlaying,
    required this.isLoading,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.record_voice_over_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t.whatToTellCustomer,
                  style: t.style(const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15))),
            ),
            // Replayable TTS — speaks the single AI-generated pitch
            // script verbatim. minimumSize override + shrinkWrap so
            // the button sizes to its content (otherwise Material 3
            // forces infinite width inside the Row).
            ElevatedButton.icon(
              onPressed: onPlay,
              // Three states: loading (spinner while ElevenLabs fetch
              // is in flight), playing (stop icon), idle (play icon).
              icon: isLoading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.onCtaDark),
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: AppColors.onCtaDark, size: 18,
                    ),
              label: Text(
                isLoading
                    ? '…'
                    : (isPlaying ? t.stopPitch : t.playPitch),
                style: t.style(AppTextStyles.button)
                    .copyWith(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // One cohesive paragraph the jockey reads out — opens with
          // the price, names the inspection faults that justify it,
          // closes softly. Copy icon stashes it to the clipboard for
          // pasting into WhatsApp / SMS.
          if (pitch.script.isNotEmpty)
            _CopyBlock(t: t, label: t.whatToTellCustomer, text: pitch.script),
        ],
      ),
    );
  }
}

/// One copy-to-clipboard text block. Tap the icon to copy the inner
/// text into the clipboard — handy when the jockey wants to paste it
/// into WhatsApp/SMS to share with a supervisor or the customer.
class _CopyBlock extends StatelessWidget {
  final Translations t;
  final String label;
  final String text;
  const _CopyBlock({
    required this.t,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(),
                    style: t.style(const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ))),
              ),
              InkResponse(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t.copiedToClipboard),
                          duration: const Duration(seconds: 1)),
                    );
                  }
                },
                radius: 18,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.copy_rounded,
                      size: 16, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(text,
              style: t.style(const TextStyle(fontSize: 14, height: 1.45))),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final Translations t;
  final int? aiPriceInr;
  final VoidCallback onAgreed;
  final VoidCallback onNotAgreed;

  const _Footer({
    required this.t,
    required this.aiPriceInr,
    required this.onAgreed,
    required this.onNotAgreed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: aiPriceInr == null ? null : onAgreed,
              icon: const Icon(Icons.check_circle_rounded,
                  color: AppColors.onCtaDark),
              label: Text(
                aiPriceInr == null
                    ? t.customerAgreed
                    : '${t.customerAgreed} — ${_formatInr(aiPriceInr!)}',
                style: t.style(AppTextStyles.button),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            // AppTextStyles.button bakes in AppColors.onCtaDark (white)
            // — fine on an elevated dark CTA, but invisible on this
            // outlined white button. Override the icon + label colour
            // to the brand primary so the text is legible.
            child: OutlinedButton.icon(
              onPressed: onNotAgreed,
              icon: const Icon(Icons.handshake_rounded,
                  color: AppColors.primary),
              label: Text(t.customerNotAgreed,
                  style: t.style(AppTextStyles.button)
                      .copyWith(color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Counter-offer sheet ---------------------------------------

class _CounterResult {
  final int priceInr;
  final String? notes;
  _CounterResult(this.priceInr, this.notes);
}

class _CounterSheet extends StatefulWidget {
  final Translations t;
  final int aiPriceInr;
  const _CounterSheet({required this.t, required this.aiPriceInr});

  @override
  State<_CounterSheet> createState() => _CounterSheetState();
}

class _CounterSheetState extends State<_CounterSheet> {
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool get _valid => int.tryParse(_priceCtrl.text.replaceAll(',', '')) != null;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(t.counterOfferTitle,
              style: t.style(const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 18))),
          const SizedBox(height: 4),
          Text(
            '${t.counterOfferHint} (AI: ${_formatInr(widget.aiPriceInr)})',
            style: t.style(AppTextStyles.body)
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t.customerPriceLabel,
              border: const OutlineInputBorder(),
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: t.notesLabel,
              hintText: t.notesHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _valid
                  ? () {
                      final price = int.parse(
                          _priceCtrl.text.replaceAll(',', ''));
                      final notes = _notesCtrl.text.trim();
                      Navigator.of(context).pop(_CounterResult(
                        price,
                        notes.isEmpty ? null : notes,
                      ));
                    }
                  : null,
              icon: const Icon(Icons.send_rounded, color: AppColors.onCtaDark),
              label: Text(t.submitTicket,
                  style: t.style(AppTextStyles.button)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Formatting ------------------------------------------------

/// Indian-style INR formatter: 480000 → "₹4,80,000". Hand-rolled so
/// we don't pull in the intl package just for this one usage.
String _formatInr(int n) {
  if (n < 1000) return '₹$n';
  final s = n.toString();
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '₹${groups.join(',')},$last3';
}

String _formatNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Display + spoken pair for the on-arrival AI bar utterance.
class _ReportIntro {
  final String display;
  final String spoken;
  const _ReportIntro(this.display, this.spoken);
}

/// Localised "inspection complete — tap play to hear the pitch" line.
/// Pitch / play / customer stay in English in non-English variants —
/// they're product nouns the jockey already reads on the buttons.
_ReportIntro _reportArrivalIntro(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      const display = 'Inspection complete. Tap the play button below '
          'to hear how to convince the customer about the price.';
      return const _ReportIntro(
        display,
        '<speak>Inspection complete. <break time="300ms"/> '
        'Tap the play button below to hear how to convince '
        'the customer about the price.</speak>',
      );
    case AppLanguage.hindi:
      const display = 'Inspection पूरा हो गया। नीचे play button दबाकर सुनिए '
          'कि customer को price कैसे समझाना है।';
      return const _ReportIntro(
        display,
        '<speak>Inspection पूरा हो गया। <break time="300ms"/> '
        'नीचे play button दबाकर सुनिए कि customer को '
        'price कैसे समझाना है।</speak>',
      );
    case AppLanguage.telugu:
      const display = 'Inspection పూర్తయింది. కింది play button నొక్కి '
          'customer కి price ఎలా చెప్పాలో వినండి.';
      return const _ReportIntro(
        display,
        '<speak>Inspection పూర్తయింది. <break time="300ms"/> '
        'కింది play button నొక్కి customer కి price ఎలా '
        'చెప్పాలో వినండి.</speak>',
      );
    case AppLanguage.bengali:
      const display = 'Inspection শেষ। নিচের play button চেপে শুনুন '
          'customer-কে price কীভাবে বোঝাবেন।';
      return const _ReportIntro(
        display,
        '<speak>Inspection শেষ। <break time="300ms"/> '
        'নিচের play button চেপে শুনুন customer-কে price '
        'কীভাবে বোঝাবেন।</speak>',
      );
  }
}
