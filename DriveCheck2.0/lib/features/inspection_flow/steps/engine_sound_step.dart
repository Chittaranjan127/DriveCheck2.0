import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/services/inspections_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../ai/engine_sound_analysis.dart';
import '../inspection_flow_provider.dart';
import '../prompts/step_intro_prompts.dart';
import '../state/assistant_utterance_provider.dart';
import '../state/step_rows_provider.dart';

/// Step 12: engine sound. Records ~15 seconds of WAV audio while the
/// engine idles, then sends it to gpt-4o-audio-preview via
/// `/ai/analyze-engine-sound` for a health verdict + detected acoustic
/// issues (knock, tick, misfire, etc.). On a clean read, uploads the
/// clip to S3 and persists the verdict on the step row.
class EngineSoundStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final VoidCallback onAdvance;

  const EngineSoundStep({
    super.key,
    required this.inspectionId,
    required this.onAdvance,
  });

  @override
  ConsumerState<EngineSoundStep> createState() => _EngineSoundStepState();
}

/// Pipeline phases. Mirrors the photo step's model with `recording` in
/// place of `idle` and a playable `persisted` view at the end.
enum _Phase {
  idle,
  permissionDenied,
  recording,
  analyzing,
  readyToConfirm,
  badQuality,
  uploading,
  saving,
  saved,
  error,
  persisted,
}

/// Fixed-length engine clip. 15 seconds matches the audioSeconds spec
/// in inspection_steps.dart — long enough to capture an idle cycle's
/// worth of acoustic cues without bloating the upload.
const Duration _kRecordDuration = Duration(seconds: 15);

class _EngineSoundStepState extends ConsumerState<EngineSoundStep> {
  static const _stepId = 'engine_sound';

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _service = InspectionsService();
  final _analyzer = EngineSoundAnalyzer();

  _Phase _phase = _Phase.idle;
  File? _recording;            // local WAV pending confirm/discard
  String? _persistedAudioUrl;  // S3 URL on revisit
  EngineSoundResult? _result;
  String? _error;

  // Recording countdown — drives the visible "12s" label and triggers
  // an auto-stop the moment we hit zero. Cancelled on stop or dispose.
  Timer? _tickTimer;
  Duration _elapsed = Duration.zero;

  // Persisted-view playback state. Subscribed to AudioPlayer events so
  // the play/pause button stays in sync with the actual audio output.
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _playerSub;

  @override
  void initState() {
    super.initState();
    if (!_hydrateFromSaved()) {
      // Fresh capture mode — bubble intro fires automatically.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      final t = ref.read(translationsProvider);
      final intro = stepIntroFor(_stepId, lang, t: t);
      ref.read(assistantUtteranceProvider.notifier).say(
            intro.spokenSsml,
            display: intro.display,
            autoplay: _phase != _Phase.persisted,
          );
    });

    _playerSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
    });
  }

  bool _hydrateFromSaved() {
    final attempt =
        ref.read(inspectionFlowProvider(widget.inspectionId)).stepAttempt;
    if (attempt != 0) return false;
    final rows = ref.read(stepRowsProvider(widget.inspectionId)).valueOrNull;
    if (rows == null) return false;
    final row = rows.where((r) => r.stepId == _stepId).firstOrNull;
    if (row == null || !row.isCompleted) return false;
    if (row.mediaUrls.isEmpty) return false;

    _persistedAudioUrl = row.mediaUrls.first;
    final ai = row.aiAnalysis;
    if (ai != null) {
      try {
        _result = EngineSoundResult.fromJson(ai);
      } catch (_) {
        // Stored shape is older than our parser — fall back to media-only
        // playback; the verdict card just won't render.
      }
    }
    _phase = _Phase.persisted;
    return true;
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _playerSub?.cancel();
    _player.dispose();
    // Best-effort stop on the recorder; ignore errors so dispose stays
    // synchronous-safe (the platform call returns a Future).
    unawaited(_recorder.stop().catchError((_) => null));
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (!mounted) return;
      setState(() => _phase = _Phase.permissionDenied);
      return;
    }
    final tmpDir = await getTemporaryDirectory();
    final path =
        '${tmpDir.path}/engine_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        // 16-bit PCM WAV at 16 kHz, mono. The model only needs
        // intelligibility on engine frequencies (mostly <1 kHz with
        // harmonics up to ~5 kHz), and this config keeps a 15-second
        // clip under ~480 KB raw → ~640 KB base64.
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          // Acoustic anomalies (knock, valve tick) are what we want
          // the model to hear — DSP filters would smooth them out.
          autoGain: false,
          noiseSuppress: false,
          echoCancel: false,
        ),
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start recorder: $e';
        _phase = _Phase.error;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _phase = _Phase.recording;
      _elapsed = Duration.zero;
      _recording = null;
      _error = null;
    });

    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 200));
      if (_elapsed >= _kRecordDuration) _stopRecording(auto: true);
    });
  }

  Future<void> _stopRecording({bool auto = false}) async {
    _tickTimer?.cancel();
    _tickTimer = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Recorder stop failed: $e';
        _phase = _Phase.error;
      });
      return;
    }
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _error = 'No recording produced';
        _phase = _Phase.error;
      });
      return;
    }
    final file = File(path);
    setState(() {
      _recording = file;
      _phase = _Phase.analyzing;
    });
    await _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final clip = _recording;
    if (clip == null) return;
    EngineSoundResult result;
    try {
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      result = await _analyzer.analyze(clip, language: lang);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Engine analysis failed: $e';
        _phase = _Phase.error;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _result = result);

    if (!result.isUsable) {
      setState(() => _phase = _Phase.badQuality);
      final spoken = result.qualityReasonSpoken;
      if (spoken != null && spoken.trim().isNotEmpty) {
        ref.read(assistantUtteranceProvider.notifier)
            .say(spoken, display: result.qualityReasonDisplay);
      }
      return;
    }
    setState(() => _phase = _Phase.readyToConfirm);
    final spoken = result.summarySpoken;
    if (spoken != null && spoken.trim().isNotEmpty) {
      ref.read(assistantUtteranceProvider.notifier)
          .say(spoken, display: result.summaryDisplay);
    }
    // Hold here. The verdict card is now visible and the bubble is
    // announcing the result; the user reviews it and taps Next when
    // ready — which fires _confirmAndAdvance() (upload + save). This
    // is the same review-before-commit pattern as the photo steps.
  }

  Future<void> _reRecord() async {
    setState(() {
      _recording = null;
      _result = null;
      _error = null;
      _elapsed = Duration.zero;
      _phase = _Phase.idle;
    });
  }

  /// User tapped Cancel mid-recording. Stops the recorder but skips
  /// the analyzer call — a 2-second clip would burn an OpenAI charge
  /// just to come back as `tooShort`. We drop the partial file on the
  /// floor and reset to the idle state.
  Future<void> _cancelRecording() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Recorder may already be stopped; nothing to recover from.
    }
    if (!mounted) return;
    setState(() {
      _recording = null;
      _result = null;
      _error = null;
      _elapsed = Duration.zero;
      _phase = _Phase.idle;
    });
  }

  void _redo() {
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).retry();
  }

  /// Upload the WAV to S3 + mark the step completed + persist the
  /// engine verdict. Identical control flow to SimplePhotoStep — the
  /// difference is the mime type and the aiAnalysis payload.
  Future<void> _confirmAndAdvance() async {
    final clip = _recording;
    final result = _result;
    if (clip == null || result == null) return;

    setState(() => _phase = _Phase.uploading);
    String mediaUrl;
    try {
      final bytes = await clip.readAsBytes();
      mediaUrl = await _service.uploadStepMedia(
        widget.inspectionId,
        _stepId,
        bytes,
        mimeType: 'audio/wav',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Upload failed: $e';
        _phase = _Phase.error;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.saving);
    try {
      await _service.updateStep(
        widget.inspectionId,
        _stepId,
        mediaUrls: [mediaUrl],
        aiAnalysis: result.toAiAnalysis(),
        status: 'completed',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Save failed: $e';
        _phase = _Phase.error;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.saved);
    unawaited(ref.read(stepRowsProvider(widget.inspectionId).notifier).refresh());
    widget.onAdvance();
  }

  /// Plays whichever clip the user is currently looking at. In
  /// [_Phase.readyToConfirm] that's the just-recorded local WAV (no
  /// upload yet); in [_Phase.persisted] it's the S3-hosted clip from
  /// a previous session. Same player instance + isPlaying stream so
  /// the button stays in sync in both cases.
  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    final localClip = _recording;
    final remoteUrl = _persistedAudioUrl;
    if (localClip != null && (_phase == _Phase.readyToConfirm ||
        _phase == _Phase.badQuality)) {
      // DeviceFileSource works on both Android and iOS for local paths
      // returned by the `record` package — no need to wrap in a file://
      // URL or copy into the app sandbox first.
      await _player.play(DeviceFileSource(localClip.path));
    } else if (remoteUrl != null) {
      await _player.play(UrlSource(remoteUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SoundStage(
            phase: _phase,
            elapsed: _elapsed,
            duration: _kRecordDuration,
            result: _result,
            isPlaying: _isPlaying,
            onPlayPause: _togglePlayback,
          ),
          const SizedBox(height: 16),
          if (_phase == _Phase.error && _error != null)
            _ErrorCard(message: _error!, onRetry: _reRecord),
          if (_result != null && _result!.isUsable && _phase != _Phase.idle)
            _VerdictCard(result: _result!),
          const SizedBox(height: 16),
          _PrimaryAction(
            t: t,
            phase: _phase,
            onStart: _startRecording,
            onCancel: _cancelRecording,
            onReRecord: _reRecord,
            onContinue: _phase == _Phase.persisted
                ? widget.onAdvance
                : _confirmAndAdvance,
            onRedo: _redo,
            onOpenSettings: _startRecording, // re-request perms via the picker
          ),
        ],
      ),
    );
  }
}

/// The visual stage that sits where the camera preview would sit on a
/// photo step. Renders one of: mic prompt (idle), countdown
/// (recording), busy spinner (analyzing/uploading), success/fail icon
/// (badQuality/error), playable player (persisted).
class _SoundStage extends StatelessWidget {
  final _Phase phase;
  final Duration elapsed;
  final Duration duration;
  final EngineSoundResult? result;
  final bool isPlaying;
  final VoidCallback onPlayPause;

  const _SoundStage({
    required this.phase,
    required this.elapsed,
    required this.duration,
    required this.result,
    required this.isPlaying,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // Squat landscape banner — matches the visual weight of the photo
      // steps' frames so the screen rhythm stays consistent.
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(child: _content()),
      ),
    );
  }

  Widget _content() {
    switch (phase) {
      case _Phase.idle:
        return const _IdleMicHint();
      case _Phase.permissionDenied:
        return const _DeniedHint();
      case _Phase.recording:
        return _Countdown(elapsed: elapsed, duration: duration);
      case _Phase.analyzing:
        return const _BusyLabel(label: 'Analysing engine sound…');
      case _Phase.uploading:
        return const _BusyLabel(label: 'Uploading recording…');
      case _Phase.saving:
        return const _BusyLabel(label: 'Saving…');
      case _Phase.badQuality:
        // Bad-quality clips are still playable — the user might want
        // to hear *why* the model rejected it before re-recording.
        return _ClipPlayer(
          isPlaying: isPlaying,
          onTap: onPlayPause,
          accent: AppColors.error,
          icon: Icons.warning_amber_rounded,
          captionPlaying: 'Playing your recording…',
          captionIdle: 'Tap to listen back',
        );
      case _Phase.readyToConfirm:
      case _Phase.saved:
        return _ClipPlayer(
          isPlaying: isPlaying,
          onTap: onPlayPause,
          accent: AppColors.success,
          icon: Icons.check_circle_rounded,
          captionPlaying: 'Playing your recording…',
          captionIdle: 'Tap to listen back',
        );
      case _Phase.error:
        return const _VerdictIcon(
            icon: Icons.error_outline_rounded,
            color: AppColors.error,
            label: 'Something went wrong');
      case _Phase.persisted:
        return _ClipPlayer(
          isPlaying: isPlaying,
          onTap: onPlayPause,
          accent: AppColors.primary,
          icon: Icons.graphic_eq_rounded,
          captionPlaying: 'Playing…',
          captionIdle: 'Saved recording',
        );
    }
  }
}

class _IdleMicHint extends ConsumerWidget {
  const _IdleMicHint();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mic_rounded,
              color: AppColors.primary, size: 32),
        ),
        const SizedBox(height: 10),
        Text(t.tapToRecord,
            style: t.style(AppTextStyles.body)
                .copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _DeniedHint extends StatelessWidget {
  const _DeniedHint();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_off_rounded,
              color: AppColors.textSecondary, size: 36),
          SizedBox(height: 8),
          Text(
            'Microphone access is needed. Please allow it in Settings.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  final Duration elapsed;
  final Duration duration;
  const _Countdown({required this.elapsed, required this.duration});

  @override
  Widget build(BuildContext context) {
    final remaining = duration - elapsed;
    final secs = remaining.inMilliseconds < 0 ? 0 : remaining.inSeconds;
    final progress = (elapsed.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 96, height: 96,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 6,
                backgroundColor: AppColors.surfaceMuted,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$secs',
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 36, color: AppColors.primary,
                    )),
                Text('seconds left',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Hold the phone near the engine',
          style: AppTextStyles.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        // Pivotal hint — tells the user the rest is automatic so they
        // don't reach for a stop button (there isn't one any more).
        Text(
          'Recording stops and uploads on its own',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _BusyLabel extends StatelessWidget {
  final String label;
  const _BusyLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(height: 12),
        Text(label,
            style: AppTextStyles.body
                .copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _VerdictIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _VerdictIcon({
    required this.icon,
    required this.color,
    required this.label,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 48),
        const SizedBox(height: 8),
        Text(label,
            style: AppTextStyles.body
                .copyWith(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Big play/pause control + accent indicator. Shared between the
/// just-recorded review state (plays the local WAV) and the persisted-
/// view state (streams the S3 URL); the parent decides the source via
/// the `onTap` callback. [icon] + [accent] colour-code the moment —
/// green check after a clean read, red warning on a bad-quality clip,
/// brand primary on a persisted revisit.
class _ClipPlayer extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  final Color accent;
  final IconData icon;
  final String captionPlaying;
  final String captionIdle;

  const _ClipPlayer({
    required this.isPlaying,
    required this.onTap,
    required this.accent,
    required this.icon,
    required this.captionPlaying,
    required this.captionIdle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.onPrimary,
                  size: 36,
                ),
              ),
            ),
            // Tiny status badge — anchors the moment ("clean read",
            // "rejected", "saved") without taking attention from the
            // primary play action.
            Positioned(
              right: -2, bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          isPlaying ? captionPlaying : captionIdle,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Below-the-stage verdict summary — colour-graded by health score and
/// followed by a row of chips for each acoustic issue the model
/// detected. Only rendered when [EngineSoundResult.isUsable].
class _VerdictCard extends StatelessWidget {
  final EngineSoundResult result;
  const _VerdictCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(result.verdict);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_iconFor(result.verdict), color: tone, size: 22),
            const SizedBox(width: 8),
            Text(_labelFor(result.verdict),
                style: AppTextStyles.heading3.copyWith(color: tone)),
            const Spacer(),
            Text('${result.healthScore}/100',
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.textPrimary, fontSize: 18,
                )),
          ]),
          if (result.detectedIssues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Detected (${result.detectedIssues.length})',
                style: AppTextStyles.caption
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.detectedIssues
                  .map((e) => _IssueChip(e))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _toneFor(EngineHealthVerdict v) {
    switch (v) {
      case EngineHealthVerdict.smooth:        return AppColors.success;
      case EngineHealthVerdict.minorIssue:    return AppColors.warning;
      case EngineHealthVerdict.concern:       return AppColors.warning;
      case EngineHealthVerdict.criticalIssue: return AppColors.error;
      case EngineHealthVerdict.inconclusive:  return AppColors.textSecondary;
    }
  }

  IconData _iconFor(EngineHealthVerdict v) {
    switch (v) {
      case EngineHealthVerdict.smooth:        return Icons.check_circle_rounded;
      case EngineHealthVerdict.minorIssue:    return Icons.info_rounded;
      case EngineHealthVerdict.concern:       return Icons.warning_rounded;
      case EngineHealthVerdict.criticalIssue: return Icons.error_rounded;
      case EngineHealthVerdict.inconclusive:  return Icons.help_outline_rounded;
    }
  }

  String _labelFor(EngineHealthVerdict v) {
    switch (v) {
      case EngineHealthVerdict.smooth:        return 'Engine sounds smooth';
      case EngineHealthVerdict.minorIssue:    return 'Minor noise';
      case EngineHealthVerdict.concern:       return 'Needs attention';
      case EngineHealthVerdict.criticalIssue: return 'Critical issue';
      case EngineHealthVerdict.inconclusive:  return 'Inconclusive';
    }
  }
}

class _IssueChip extends StatelessWidget {
  final EngineIssue issue;
  const _IssueChip(this.issue);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Text(
        issue.displayName,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorCard extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.error)),
          ),
          TextButton(onPressed: onRetry,
              child: Text(t.tryAgain,
                  style: t.style(AppTextStyles.button)
                      .copyWith(color: AppColors.primary))),
        ],
      ),
    );
  }
}

/// One button-row per phase. Kept inline rather than split per-state
/// because the buttons all need the same shared callbacks and there's
/// no rendering reuse across phases.
class _PrimaryAction extends StatelessWidget {
  final Translations t;
  final _Phase phase;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onReRecord;
  final VoidCallback onContinue;
  final VoidCallback onRedo;
  final VoidCallback onOpenSettings;

  const _PrimaryAction({
    required this.t,
    required this.phase,
    required this.onStart,
    required this.onCancel,
    required this.onReRecord,
    required this.onContinue,
    required this.onRedo,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case _Phase.analyzing:
      case _Phase.uploading:
      case _Phase.saving:
      case _Phase.saved:
        return const SizedBox.shrink();

      case _Phase.idle:
        return Column(
          children: [
            _BigCta(
              label: 'Record for 15 seconds',
              icon: Icons.fiber_manual_record_rounded,
              colour: AppColors.primary,
              onTap: onStart,
            ),
            const SizedBox(height: 8),
            // Sets expectation up-front so the user understands they
            // don't have to babysit the recording or tap submit.
            Text(
              'Auto-stops and analyses on its own',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case _Phase.permissionDenied:
        return _BigCta(
          label: 'Try again',
          icon: Icons.mic_rounded,
          colour: AppColors.primary,
          onTap: onOpenSettings,
        );

      case _Phase.recording:
        // No primary CTA while recording — the timer auto-stops and
        // auto-uploads. A small Cancel link is the only escape hatch
        // (e.g. user noticed the phone is in the wrong place).
        return Center(
          child: TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary),
            label: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );

      case _Phase.badQuality:
      case _Phase.error:
        return _BigCta(
          label: t.reRecord,
          icon: Icons.replay_rounded,
          colour: AppColors.error,
          onTap: onReRecord,
        );

      case _Phase.readyToConfirm:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onReRecord,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t.reRecord,
                    style: t.style(AppTextStyles.button)
                        .copyWith(color: AppColors.primary)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.onCtaDark),
                label: Text(t.next, style: AppTextStyles.button),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        );

      case _Phase.persisted:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRedo,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t.redo, style: t.style(AppTextStyles.button).copyWith(color: AppColors.primary)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.onCtaDark),
                label: Text(t.next, style: AppTextStyles.button),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _BigCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;
  const _BigCta({
    required this.label,
    required this.icon,
    required this.colour,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.onCtaDark),
        label: Text(label, style: AppTextStyles.button),
        style: ElevatedButton.styleFrom(
          backgroundColor: colour,
          minimumSize: const Size.fromHeight(56),
        ),
      ),
    );
  }
}
