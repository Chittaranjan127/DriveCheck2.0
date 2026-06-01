import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/services/ai_assistant_service.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../state/assistant_utterance_provider.dart';

/// Apple-Intelligence-inspired AI status bar pinned to the bottom of
/// the inspection-flow shell. Replaces the old [AssistantBubble]:
/// instead of a floating circle that hides over content, this is a
/// full-width capsule with an animated rainbow border, a sparkle
/// icon on the left, the current utterance text in the middle, and a
/// play/pause control on the right.
///
/// Visible whenever there's a non-null utterance in
/// [assistantUtteranceProvider]. Slides in/out via [AnimatedSize] so
/// step bodies above it reflow without a layout jolt.
class AssistantBottomBar extends ConsumerWidget {
  const AssistantBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assistantEnabled =
        ref.watch(aiAssistantEnabledProvider).valueOrNull ?? true;
    // User opted out — collapse the bar entirely. The companion
    // gating in [AssistantUtteranceNotifier.say] already prevents any
    // utterance from being pushed, so this is just visual cleanup.
    if (!assistantEnabled) return const SizedBox.shrink();
    final utterance = ref.watch(assistantUtteranceProvider);
    final t = ref.watch(translationsProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: utterance == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              // Top padding leaves a clear breathing gap between the
              // step body and the bar so it doesn't collide visually
              // with the step CTA above. Bottom padding is minimal so
              // the bar sticks to the bottom edge — the parent
              // SafeArea still keeps it clear of the home indicator.
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
              child: _Bar(
                // ValueKey on issuedAt so a new utterance resets the
                // bar's internal phase (thinking → speaking → done).
                key: ValueKey(utterance.issuedAt),
                utterance: utterance,
                t: t,
              ),
            ),
    );
  }
}

enum _Phase { thinking, speaking, paused, done }

class _Bar extends StatefulWidget {
  final AssistantUtterance utterance;
  final Translations t;
  const _Bar({super.key, required this.utterance, required this.t});

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with TickerProviderStateMixin {
  late final AnimationController _shimmer; // rotates the border gradient
  late final AnimationController _pulse;   // drives typing dots / icon glow
  StreamSubscription<PlayerState>? _sub;
  Timer? _loadingFallback;
  _Phase _phase = _Phase.thinking;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // Silent utterance (autoplay: false on revisit) — jump straight to
    // done so the play button is available immediately, no typing dots.
    if (!widget.utterance.autoplay) {
      _phase = _Phase.done;
    }

    _sub = TtsService.instance.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s == PlayerState.playing) {
        _loadingFallback?.cancel();
        if (_phase != _Phase.speaking) {
          setState(() => _phase = _Phase.speaking);
        }
      } else if (s == PlayerState.paused && _phase == _Phase.speaking) {
        setState(() => _phase = _Phase.paused);
      } else if (s == PlayerState.completed &&
          (_phase == _Phase.speaking || _phase == _Phase.paused)) {
        setState(() => _phase = _Phase.done);
      }
    });

    // Same 4-second safety net as the old bubble — if the TTS fetch
    // dies silently we still leave the "thinking" state eventually.
    _loadingFallback = Timer(const Duration(seconds: 4), () {
      if (mounted && _phase == _Phase.thinking) {
        setState(() => _phase = _Phase.done);
      }
    });
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _pulse.dispose();
    _sub?.cancel();
    _loadingFallback?.cancel();
    super.dispose();
  }

  void _togglePlayback() {
    switch (_phase) {
      case _Phase.speaking:
        unawaited(TtsService.instance.pause());
        setState(() => _phase = _Phase.paused);
        break;
      case _Phase.paused:
        unawaited(TtsService.instance.resume());
        setState(() => _phase = _Phase.speaking);
        break;
      case _Phase.done:
      case _Phase.thinking:
        setState(() => _phase = _Phase.speaking);
        unawaited(TtsService.instance.speak(widget.utterance.spokenSsml));
        break;
    }
  }

  /// Strips SSML tags for on-screen display (the original string still
  /// goes to ElevenLabs intact).
  static String _stripSsml(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final display = widget.utterance.displayOverride
        ?? _stripSsml(widget.utterance.spokenSsml);

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) {
        return Container(
          decoration: BoxDecoration(
            // Rotating sweep gradient — Apple-Intelligence-ish
            // border. The same colour set the system uses on the
            // Siri activation halo, just slowed down.
            gradient: SweepGradient(
              colors: const [
                Color(0xFFFF6EC4), // pink
                Color(0xFF7873F5), // purple
                Color(0xFF53C4FF), // cyan
                Color(0xFFFFD361), // gold
                Color(0xFFFF6EC4), // back to pink (loop)
              ],
              transform:
                  GradientRotation(_shimmer.value * 2 * math.pi),
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color:
                    AppColors.primary.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.6),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30.4),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                _SparkleIcon(pulse: _pulse, speaking: _phase == _Phase.speaking),
                const SizedBox(width: 10),
                Expanded(
                  child: _phase == _Phase.thinking
                      ? _TypingDots(pulse: _pulse)
                      : Text(
                          display,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: widget.t
                              .style(AppTextStyles.body)
                              .copyWith(
                                fontSize: 13.5,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                        ),
                ),
                const SizedBox(width: 8),
                _PlayPauseButton(
                  phase: _phase,
                  enabled: _phase != _Phase.thinking,
                  onTap: _togglePlayback,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sparkle icon with a soft pulse + gradient fill. Acts as the bar's
/// "AI logo" — same identity as the brand mark but no full Cars24 lock-up.
class _SparkleIcon extends StatelessWidget {
  final AnimationController pulse;
  final bool speaking;
  const _SparkleIcon({required this.pulse, required this.speaking});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) {
        final glow = speaking ? (0.4 + 0.4 * pulse.value) : 0.2;
        return Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [
                Color(0xFFFF6EC4),
                Color(0xFF7873F5),
                Color(0xFF53C4FF),
                Color(0xFFFFD361),
                Color(0xFFFF6EC4),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7873F5)
                    .withValues(alpha: glow * 0.5),
                blurRadius: 10 * glow,
                spreadRadius: 1.5 * glow,
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 18),
        );
      },
    );
  }
}

class _TypingDots extends StatelessWidget {
  final AnimationController pulse;
  const _TypingDots({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (pulse.value + i / 3) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
              child: Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final _Phase phase;
  final bool enabled;
  final VoidCallback onTap;
  const _PlayPauseButton({
    required this.phase,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSpeaking = phase == _Phase.speaking;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 24,
        child: Container(
          width: 36, height: 36,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
          child: Icon(
            isSpeaking ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: AppColors.onPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
