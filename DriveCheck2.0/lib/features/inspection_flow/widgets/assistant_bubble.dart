import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../state/assistant_utterance_provider.dart';

/// Floating AI-assistant widget pinned to the bottom-right of the
/// inspection-flow shell. Renders as a small circular icon when idle
/// or closed; expands into a chat callout the moment the active step
/// pushes a new utterance through [assistantUtteranceProvider].
///
/// Auto-opens on new utterance, can be dismissed via the × button
/// (which also stops any in-flight TTS), and can be re-opened by
/// tapping the icon again. The icon glows while audio is playing.
class AssistantBubble extends ConsumerWidget {
  const AssistantBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final utterance = ref.watch(assistantUtteranceProvider);
    if (utterance == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider);

    return _FloatingBubble(
      // ValueKey on issuedAt so every new utterance forces a fresh
      // State (auto-opens, restarts the thinking → speaking → done
      // cycle, resets the user-closed flag).
      key: ValueKey(utterance.issuedAt),
      utterance: utterance,
      t: t,
    );
  }
}

class _FloatingBubble extends StatefulWidget {
  final AssistantUtterance utterance;
  final Translations t;
  const _FloatingBubble({super.key, required this.utterance, required this.t});

  @override
  State<_FloatingBubble> createState() => _FloatingBubbleState();
}

enum _BubblePhase { thinking, speaking, paused, done }

/// Strips SSML tags (`<speak>`, `<break.../>`, etc.) for visual display
/// while the original string is sent intact to ElevenLabs for TTS.
String _stripSsml(String s) =>
    s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

class _FloatingBubbleState extends State<_FloatingBubble>
    with SingleTickerProviderStateMixin {
  StreamSubscription<PlayerState>? _sub;
  late final AnimationController _pulse;
  _BubblePhase _phase = _BubblePhase.thinking;
  Timer? _loadingFallback;

  // Defaults to true so a fresh utterance is visible immediately. User
  // can close the callout, leaving only the floating icon behind; new
  // utterances re-mount the State (ValueKey), which resets this to true.
  bool _isOpen = true;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // Silent utterance (autoplay: false) — used when revisiting a
    // completed step. Skip the "thinking" dots; show the text + play
    // button immediately so the user can tap to hear it on demand.
    if (!widget.utterance.autoplay) {
      _phase = _BubblePhase.done;
    }

    _sub = TtsService.instance.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s == PlayerState.playing) {
        _loadingFallback?.cancel();
        if (_phase != _BubblePhase.speaking) {
          setState(() => _phase = _BubblePhase.speaking);
        }
      } else if (s == PlayerState.paused && _phase == _BubblePhase.speaking) {
        setState(() => _phase = _BubblePhase.paused);
      } else if (s == PlayerState.completed &&
          (_phase == _BubblePhase.speaking || _phase == _BubblePhase.paused)) {
        setState(() => _phase = _BubblePhase.done);
      }
    });

    _loadingFallback = Timer(const Duration(seconds: 4), () {
      if (mounted && _phase == _BubblePhase.thinking) {
        setState(() => _phase = _BubblePhase.done);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _loadingFallback?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _toggleOpen() => setState(() => _isOpen = !_isOpen);

  void _close() {
    // Stop in-flight TTS so the user actually gets silence on close —
    // otherwise audio keeps playing while the callout is gone, which
    // is jarring (you've dismissed the message but it's still talking).
    unawaited(TtsService.instance.stop());
    setState(() {
      _isOpen = false;
      // Treat "I closed it" as "this utterance is done" so re-opening
      // the same one shows the replay button rather than the equalizer.
      if (_phase == _BubblePhase.speaking) _phase = _BubblePhase.done;
    });
  }

  /// One button, three behaviours driven by current playback state:
  ///   - speaking → pause the audio (icon flips to play)
  ///   - paused   → resume from where we left off
  ///   - done     → replay from the top (audio is in cache, no re-fetch)
  /// Always leaves the callout open so the user can see what's happening.
  void _togglePlayback() {
    setState(() => _isOpen = true);
    switch (_phase) {
      case _BubblePhase.speaking:
        unawaited(TtsService.instance.pause());
        // Optimistic flip — the actual `paused` PlayerState event will
        // confirm. If pause() failed the listener never fires and we'd
        // be stuck; keeping the listener's setState as the source of
        // truth would feel laggy, so we flip here and let the listener
        // converge.
        setState(() => _phase = _BubblePhase.paused);
        break;
      case _BubblePhase.paused:
        unawaited(TtsService.instance.resume());
        setState(() => _phase = _BubblePhase.speaking);
        break;
      case _BubblePhase.done:
      case _BubblePhase.thinking:
        setState(() => _phase = _BubblePhase.speaking);
        unawaited(TtsService.instance.speak(widget.utterance.spokenSsml));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Animated callout — slides up from the icon and fades in.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: _isOpen
              ? _Callout(
                  display: widget.utterance.displayOverride ??
                      _stripSsml(widget.utterance.spokenSsml),
                  phase: _phase,
                  pulse: _pulse,
                  t: widget.t,
                  onClose: _close,
                  onReplay: _togglePlayback,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        _AssistantIcon(
          speaking: _phase == _BubblePhase.speaking,
          pulse: _pulse,
          onTap: _toggleOpen,
        ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  final String display;
  final _BubblePhase phase;
  final AnimationController pulse;
  final Translations t;
  final VoidCallback onClose;
  final VoidCallback onReplay;

  const _Callout({
    required this.display,
    required this.phase,
    required this.pulse,
    required this.t,
    required this.onClose,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Cap the width so a long Hindi/Telugu/Bengali sentence wraps
      // nicely inside the callout rather than stretching across the
      // whole screen. Min width keeps the dots/equalizer readable when
      // the bubble is in the "thinking" state with no text yet.
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 160),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: tiny close button on the right.
            Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                InkResponse(
                  onTap: onClose,
                  radius: 18,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: phase == _BubblePhase.thinking
                  ? _TypingDots(pulse: pulse)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          display,
                          style: t.style(AppTextStyles.body).copyWith(
                                color: AppColors.textPrimary,
                                height: 1.4,
                                fontSize: 14,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (phase == _BubblePhase.speaking)
                              _Equalizer(pulse: pulse)
                            else
                              const SizedBox.shrink(),
                            _PlayPauseButton(phase: phase, onTap: onReplay),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantIcon extends StatelessWidget {
  final bool speaking;
  final AnimationController pulse;
  final VoidCallback onTap;
  const _AssistantIcon({
    required this.speaking,
    required this.pulse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) {
        final glow = speaking ? (0.55 + 0.35 * pulse.value) : 0.0;
        return Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkResponse(
            onTap: onTap,
            radius: 32,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  if (glow > 0)
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: glow * 0.5),
                      blurRadius: 14 * glow,
                      spreadRadius: 2 * glow,
                    ),
                ],
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: AppColors.onPrimary,
                size: 26,
              ),
            ),
          ),
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
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = (pulse.value + i / 3) % 1.0;
              final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: opacity),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _Equalizer extends StatelessWidget {
  final AnimationController pulse;
  const _Equalizer({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final phase = (pulse.value + i / 5) % 1.0;
            final h = 4 + 14 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(right: i == 4 ? 0 : 3),
              child: Container(
                width: 3,
                height: h,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Single button that swaps between play/pause based on the current
/// playback phase. Shows pause while audio is playing; shows play when
/// paused (resumes) or done (replays).
class _PlayPauseButton extends StatelessWidget {
  final _BubblePhase phase;
  final VoidCallback onTap;
  const _PlayPauseButton({required this.phase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSpeaking = phase == _BubblePhase.speaking;
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
        ),
        child: Icon(
          isSpeaking ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: AppColors.onPrimary,
          size: 20,
        ),
      ),
    );
  }
}
