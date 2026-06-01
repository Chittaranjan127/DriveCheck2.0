import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/models/inspection_step_row.dart';
import '../../../core/services/inspections_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../ai/test_drive_analysis.dart';
import '../inspection_flow_provider.dart';
import '../state/assistant_utterance_provider.dart';
import '../state/step_rows_provider.dart';

/// Step 13: hands-free conversational test drive.
///
/// One tap to start. From then on the AI asks 7 questions in order
/// (6 categorical checks + 1 open-ended overall), listens via the mic
/// after each, transcribes through Whisper, classifies through gpt-4o,
/// and reads back a confirmation before moving on. The driver never
/// touches the screen during the drive itself.
class TestDriveStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final VoidCallback onAdvance;

  const TestDriveStep({
    super.key,
    required this.inspectionId,
    required this.onAdvance,
  });

  @override
  ConsumerState<TestDriveStep> createState() => _TestDriveStepState();
}

/// Coarse phase enum used to render the right scene. Per-question
/// state (which Q we're on, the current answer file, the running
/// `_answers` list) is held in plain fields so we can mutate it
/// outside the strict enum.
enum _Phase {
  // Initial state while we wait to know whether the step is already
  // completed on the backend. Renders a small spinner — crucially we
  // DO NOT announce the "Ready for the test drive?" intro here,
  // because if the data shows the step is already saved we'll flip
  // straight to [persisted] and the audible welcome would be wrong.
  resolving,
  intro,        // "Tap Start to begin"
  conversing,   // active drive — sub-state tracked by [_subPhase]
  summary,      // all answers in; review + Save
  saving,
  saved,
  error,
  persisted,    // revisiting a completed step
}

enum _SubPhase {
  speakingQuestion,    // TTS reading the question aloud
  listening,           // recording the driver's answer
  transcribing,        // hitting /ai/transcribe
  parsing,             // hitting /ai/analyze-answer
  speakingAck,         // TTS reading the acknowledgment back
  speakingOverall,     // last-question prompt
  listeningOverall,    // 30s open recording
  summarising,         // condensing the overall answer
}

/// How many times we re-ask the same categorical question when the
/// parser returns `unclear`. Three keeps the conversation moving even
/// when the mic catches road noise; the fourth bail-out records the
/// answer as "unclear" so the jockey can see the gap on the summary.
const int _kMaxUnclearAttempts = 3;

class _TestDriveStepState extends ConsumerState<TestDriveStep> {
  static const _stepId = 'test_drive';

  final _recorder = AudioRecorder();
  final _service = InspectionsService();
  final _transcriber = TestDriveTranscriber();
  final _parser = TestDriveAnswerParser();
  final _player = AudioPlayer(); // persisted-view playback

  _Phase _phase = _Phase.resolving;
  _SubPhase _sub = _SubPhase.speakingQuestion;

  // Conversation state.
  int _qIndex = 0;
  final List<TestDriveAnswer> _answers = [];
  final List<File?> _answerAudioFiles = [];
  File? _overallAudioFile;
  String _overallTranscription = '';
  String _overallSummary = '';
  TestDriveSummary? _summary;
  TestDriveSummary? _persistedSummary;

  // Listening countdown.
  Timer? _tickTimer;
  Duration _listenElapsed = Duration.zero;
  Duration _listenTotal = Duration.zero;
  StreamSubscription<PlayerState>? _ttsSub;

  // Persisted playback.
  String? _playingUrl;
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _playerSub;

  String? _error;

  // Subscription to the step-rows provider so a delayed hydrate can
  // still flip us into the persisted view if the data lands AFTER
  // initState (cold app launch, deep-link straight to this step,
  // backend round-trip in flight). Without this the conversation
  // would start over even though the answers are already saved.
  ProviderSubscription<AsyncValue<List<InspectionStepRow>>>? _rowsSub;

  @override
  void initState() {
    super.initState();
    // Try synchronously first — if the rows are already in the cache
    // we can render the right view on the very first frame and skip
    // the spinner.
    final hydratedSync = _hydrateFromSaved();
    if (hydratedSync) {
      // Saved row found — landing on the result page. Wipe any
      // assistant utterance left over from an earlier step instead
      // of pushing the "Ready for the test drive?" intro: that text
      // is for a fresh capture, not a revisit, and the AI bar would
      // otherwise lie about what's happening.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(assistantUtteranceProvider.notifier).clear();
      });
    } else {
      // No cached data — fetch in the background. The view stays in
      // [_Phase.resolving] (spinner) until we know whether to land on
      // persisted (saved) or intro (fresh). Crucially we do NOT
      // announce the "Ready for the test drive?" intro yet — doing
      // that pre-emptively would make the AI speak even when the
      // data is about to tell us we're already done.
      unawaited(ref
          .read(stepRowsProvider(widget.inspectionId).notifier)
          .refresh());
      _rowsSub = ref.listenManual<AsyncValue<List<InspectionStepRow>>>(
        stepRowsProvider(widget.inspectionId),
        (_, next) {
          if (!mounted) return;
          if (_phase != _Phase.resolving) return;
          if (next.isLoading) return;
          _resolveInitialPhase();
        },
      );
      // Hard ceiling — if the provider keeps loading or errors out,
      // fall back to a fresh intro after 5s so the jockey isn't
      // stranded on the spinner.
      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        if (_phase == _Phase.resolving) _resolveInitialPhase();
      });
    }

    _playerSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
    });
  }

  /// Called after the step-rows fetch settles (success, error, or
  /// timeout). Flips us into the correct initial phase and announces
  /// the matching intro. Safe to call only when [_phase] is
  /// [_Phase.resolving] — guarded by the call sites.
  void _resolveInitialPhase() {
    final hydrated = _hydrateFromSaved();
    if (hydrated) {
      // Saved drive — show the summary with a clean AI bar. The
      // intro copy isn't relevant on the result page, so clear any
      // utterance instead of pushing the "Ready for the test drive?"
      // line.
      ref.read(assistantUtteranceProvider.notifier).clear();
      setState(() {});
    } else {
      // Fresh capture — switch to the intro view and play the welcome.
      setState(() => _phase = _Phase.intro);
      _announceIntro();
    }
  }

  bool _hydrateFromSaved() {
    final attempt =
        ref.read(inspectionFlowProvider(widget.inspectionId)).stepAttempt;
    if (attempt != 0) return false;
    final rows = ref.read(stepRowsProvider(widget.inspectionId)).valueOrNull;
    if (rows == null) return false;
    final row = rows.where((r) => r.stepId == _stepId).firstOrNull;
    if (row == null || !row.isCompleted) return false;
    if (row.data.isEmpty) return false;
    try {
      _persistedSummary = TestDriveSummary.fromJson(row.data);
    } catch (_) {
      return false;
    }
    _phase = _Phase.persisted;
    return true;
  }

  void _announceIntro({bool silent = false}) {
    final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
    final intro = _introFor(lang);
    ref.read(assistantUtteranceProvider.notifier).say(
          intro.spokenSsml,
          display: intro.display,
          autoplay: !silent,
        );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _ttsSub?.cancel();
    _playerSub?.cancel();
    _rowsSub?.close();
    unawaited(_recorder.stop().catchError((_) => null));
    _recorder.dispose();
    _player.dispose();
    unawaited(TtsService.instance.stop());
    super.dispose();
  }

  // ---------------- Conversation flow ----------------

  /// User tapped Start. From here on no further touches are needed
  /// until the summary screen — questions chain themselves.
  Future<void> _startDrive() async {
    if (!await _ensureMicPermission()) return;
    setState(() {
      _phase = _Phase.conversing;
      _qIndex = 0;
      _answers.clear();
      _answerAudioFiles.clear();
      _overallTranscription = '';
      _overallSummary = '';
      _error = null;
    });
    // Stop the intro bubble's audio before our own TTS starts so the
    // overlap doesn't confuse the driver.
    await TtsService.instance.stop();
    ref.read(assistantUtteranceProvider.notifier).clear();
    await _runQuestion(0);
  }

  Future<bool> _ensureMicPermission() async {
    final ok = await _recorder.hasPermission();
    if (!ok && mounted) {
      final t = ref.read(translationsProvider);
      setState(() {
        _error = t.tdMicPermissionNeeded;
        _phase = _Phase.error;
      });
    }
    return ok;
  }

  /// Drives one categorical question end-to-end. Recursive: on the
  /// last question it kicks off the overall prompt instead of
  /// looping back into itself.
  ///
  /// If the parser comes back with `value: "unclear"` (driver mumbled,
  /// answered something off-topic, mic cut out, etc.), we retry the
  /// question up to [_kMaxUnclearAttempts] times before accepting the
  /// unclear answer and moving on. Each retry plays a short "didn't
  /// catch that" intro so the driver knows to repeat themselves.
  Future<void> _runQuestion(int index) async {
    if (!mounted) return;
    if (index >= kTestDriveQuestions.length) {
      await _runOverall();
      return;
    }
    final q = kTestDriveQuestions[index];
    final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
    final ssml = q.spokenSsml[lang] ?? q.spokenSsml[AppLanguage.english]!;
    final display = q.display[lang] ?? q.display[AppLanguage.english]!;

    setState(() {
      _qIndex = index;
      _sub = _SubPhase.speakingQuestion;
    });

    TestDriveAnswer? answer;
    File? attemptFile;

    for (var attempt = 1; attempt <= _kMaxUnclearAttempts; attempt++) {
      if (!mounted) return;
      // First attempt plays the regular question SSML; later attempts
      // prepend a localised "didn't catch that" line so the driver
      // doesn't think the app glitched.
      if (attempt == 1) {
        ref.read(assistantUtteranceProvider.notifier).say(ssml, display: display);
      } else {
        final retry = _didntCatchThatFor(lang);
        ref.read(assistantUtteranceProvider.notifier).say(
              '<speak>${retry.spokenInner} <break time="400ms"/> ${_stripSpeakWrap(ssml)}</speak>',
              display: '${retry.display} $display',
            );
      }
      await _waitForTtsComplete();
      if (!mounted) return;

      // Listen window.
      attemptFile = await _record(q.listenDuration);
      if (!mounted) return;
      if (attemptFile == null) return; // error already surfaced

      setState(() => _sub = _SubPhase.transcribing);
      String transcription;
      try {
        transcription = await _transcriber.transcribe(attemptFile, language: lang);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Transcribe failed: $e';
          _phase = _Phase.error;
        });
        return;
      }

      setState(() => _sub = _SubPhase.parsing);
      Map<String, dynamic> parsed;
      try {
        parsed = await _parser.parse(
          transcription: transcription,
          questionText: display,
          expectedValues: q.categories,
          language: lang,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Parse failed: $e';
          _phase = _Phase.error;
        });
        return;
      }

      answer = TestDriveAnswer(
        questionId: q.id,
        questionText: display,
        transcription: transcription,
        value: (parsed['value'] as String?) ?? 'unclear',
        confidence: ((parsed['confidence'] as num?) ?? 0).toDouble(),
        notes: parsed['notes'] as String?,
        acknowledgment: parsed['acknowledgment'] as String?,
      );

      // Accept on the first clearly-classified answer; loop on unclear.
      if (answer.value != 'unclear') break;
    }

    // Either we got a clear answer OR we exhausted retries — in the
    // latter case `answer.value` is "unclear" and stays that way.
    if (answer == null || attemptFile == null) return;
    _answers.add(answer);
    _answerAudioFiles.add(attemptFile);

    // Speak the acknowledgment so the driver gets audible confirmation
    // of what was understood before the next question fires.
    final ack = answer.acknowledgment;
    if (ack != null && ack.trim().isNotEmpty) {
      setState(() => _sub = _SubPhase.speakingAck);
      final ackSsml = '<speak>$ack</speak>';
      ref.read(assistantUtteranceProvider.notifier)
          .say(ackSsml, display: ack);
      await _waitForTtsComplete();
    }
    if (!mounted) return;

    // Chain into the next question without a manual tap.
    await _runQuestion(index + 1);
  }

  /// Strips the outer `<speak>...</speak>` wrap so the inner can be
  /// concatenated with another snippet inside one `<speak>` envelope.
  String _stripSpeakWrap(String s) =>
      s.replaceAll(RegExp(r'^\s*<speak>\s*'), '')
          .replaceAll(RegExp(r'\s*</speak>\s*$'), '');

  /// Final open-ended question. Longer listen window, free-text
  /// answer, model condenses it into a one-line summary that lands on
  /// the summary card.
  Future<void> _runOverall() async {
    final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
    final ssml = kTestDriveOverall.spokenSsml[lang]
        ?? kTestDriveOverall.spokenSsml[AppLanguage.english]!;
    final display = kTestDriveOverall.display[lang]
        ?? kTestDriveOverall.display[AppLanguage.english]!;

    setState(() => _sub = _SubPhase.speakingOverall);
    ref.read(assistantUtteranceProvider.notifier).say(ssml, display: display);
    await _waitForTtsComplete();
    if (!mounted) return;

    final file = await _record(kTestDriveOverall.listenDuration,
        forOverall: true);
    if (!mounted) return;
    if (file == null) return;
    _overallAudioFile = file;

    setState(() => _sub = _SubPhase.transcribing);
    String transcription;
    try {
      transcription = await _transcriber.transcribe(file, language: lang);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Transcribe failed: $e';
        _phase = _Phase.error;
      });
      return;
    }
    _overallTranscription = transcription;

    // Lightweight "summary" — just truncate the transcription for now.
    // Could route through another /ai/analyze-answer call if a model-
    // condensed paraphrase becomes important later.
    _overallSummary = transcription.length > 240
        ? '${transcription.substring(0, 237)}…'
        : transcription;

    final summary = TestDriveSummary.fromAnswers(
      answers: List.of(_answers),
      overallTranscription: _overallTranscription,
      overallSummary: _overallSummary,
    );
    setState(() {
      _summary = summary;
      _phase = _Phase.summary;
    });

    // Speak a sign-off so the driver knows the conversation is done.
    final wrap = _wrapUpFor(lang);
    ref.read(assistantUtteranceProvider.notifier)
        .say(wrap.spokenSsml, display: wrap.display);
  }

  /// Awaits one TTS playback cycle to *fully* finish before resolving.
  ///
  /// Important nuance: [TtsService.speak] internally calls
  /// `_player.stop()` to clear the previous clip before queueing the
  /// new one. That emits a `stopped` event BEFORE the new clip starts
  /// playing — naively completing on `stopped` short-circuits this
  /// wait and the recorder starts on top of the question audio.
  ///
  /// The fix: only treat `completed` / `stopped` as "done" once we've
  /// actually observed a `playing` event from this utterance.
  Future<void> _waitForTtsComplete() async {
    final c = Completer<void>();
    var startedPlaying = false;
    _ttsSub?.cancel();
    _ttsSub = TtsService.instance.playerStateStream.listen((s) {
      if (s == PlayerState.playing) {
        startedPlaying = true;
        return;
      }
      if (!startedPlaying) return; // ignore the pre-play `stopped` flush
      if (s == PlayerState.completed || s == PlayerState.stopped) {
        if (!c.isCompleted) c.complete();
      }
    });
    // Hard ceiling — covers the rare case where the audio fetch fails
    // silently and `playing` never fires. 20s is comfortably longer
    // than the 8-12s a typical question utterance takes end-to-end.
    await c.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    await _ttsSub?.cancel();
    _ttsSub = null;
  }

  /// Records the driver's spoken answer with voice-activity-detection
  /// (VAD) auto-stop. The flow:
  ///
  /// 1. **Warmup** (~500ms): sample mic amplitude to learn the cabin's
  ///    ambient noise floor (engine, road, AC).
  /// 2. **Adaptive threshold**: speech is anything ≥ ambient + 8 dB,
  ///    clamped to a sensible band (−50 … −20 dBFS). This adapts to a
  ///    quiet showroom vs. a moving car without us hardcoding.
  /// 3. **Wait for voice**: keep recording until at least one sample
  ///    crosses the speech threshold (driver started talking).
  /// 4. **Wait for trailing silence**: once we've heard voice, the
  ///    recording auto-stops after [silenceStop] of sustained
  ///    sub-threshold samples — driver finished, no need to wait the
  ///    full window. Overall (open-ended) questions get a longer
  ///    pause budget because thinking mid-answer is normal.
  /// 5. **Floors + ceiling**: minimum recording length is honoured so
  ///    we never bail mid-syllable; [duration] is the hard ceiling if
  ///    the driver never speaks (timeout fallback).
  ///
  /// Same WAV config as engine_sound — Whisper handles it natively
  /// and file size stays modest.
  Future<File?> _record(Duration duration, {bool forOverall = false}) async {
    final tmpDir = await getTemporaryDirectory();
    final path = '${tmpDir.path}/drive_${forOverall ? 'overall' : 'q$_qIndex'}_'
        '${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          noiseSuppress: false,
          echoCancel: false,
        ),
        path: path,
      );
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _error = 'Recorder failed to start: $e';
        _phase = _Phase.error;
      });
      return null;
    }

    setState(() {
      _sub = forOverall ? _SubPhase.listeningOverall : _SubPhase.listening;
      _listenElapsed = Duration.zero;
      _listenTotal = duration;
    });

    // VAD configuration. Numbers tuned for hands-free use in a moving
    // car cabin — a short pause (1.2s) is enough on categorical Qs
    // where the answer is one or two words; open-ended ("overall
    // feedback") gets 2s so a thinking pause doesn't cut the driver
    // off mid-sentence.
    const sampleInterval = Duration(milliseconds: 100);
    const warmup = Duration(milliseconds: 500);
    const minRecording = Duration(milliseconds: 1500);
    final silenceStop = forOverall
        ? const Duration(milliseconds: 2000)
        : const Duration(milliseconds: 1200);
    const absoluteFloor = -45.0;

    final stopCompleter = Completer<void>();
    final startedAt = DateTime.now();
    final ambient = <double>[];
    var speechThreshold = absoluteFloor;
    var hasSpoken = false;
    DateTime? silenceStartedAt;

    StreamSubscription<Amplitude>? ampSub;
    try {
      ampSub = _recorder
          .onAmplitudeChanged(sampleInterval)
          .listen((amp) {
        if (stopCompleter.isCompleted) return;
        final now = DateTime.now();
        final elapsed = now.difference(startedAt);
        final db = amp.current;

        if (elapsed < warmup) {
          if (db.isFinite) ambient.add(db);
          return;
        }
        // First post-warmup sample: lock in adaptive threshold from
        // the ambient distribution's 70th percentile. Speaking has to
        // beat that by 8 dB to count.
        if (ambient.isNotEmpty && speechThreshold == absoluteFloor) {
          ambient.sort();
          final p70 = ambient[(ambient.length * 7 ~/ 10).clamp(0, ambient.length - 1)];
          speechThreshold = (p70 + 8.0).clamp(-50.0, -20.0);
        }

        final isVoice = db > speechThreshold;
        if (isVoice) {
          hasSpoken = true;
          silenceStartedAt = null;
          return;
        }
        // Silence path — only matters once the driver has actually
        // spoken AND we've recorded long enough that we won't truncate
        // their answer.
        if (!hasSpoken) return;
        if (elapsed < minRecording) return;
        silenceStartedAt ??= now;
        if (now.difference(silenceStartedAt!) >= silenceStop) {
          if (!stopCompleter.isCompleted) stopCompleter.complete();
        }
      }, onError: (_) {
        // If amplitude monitoring isn't supported, fall back to the
        // duration-only ceiling — the tick timer below still handles it.
      });
    } catch (_) {
      // Same fallback as the onError above. The tick timer enforces
      // the original fixed-duration cap.
    }

    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) {
        _tickTimer?.cancel();
        if (!stopCompleter.isCompleted) stopCompleter.complete();
        return;
      }
      setState(() => _listenElapsed += const Duration(milliseconds: 200));
      if (_listenElapsed >= duration) {
        _tickTimer?.cancel();
        if (!stopCompleter.isCompleted) stopCompleter.complete();
      }
    });
    await stopCompleter.future;
    _tickTimer?.cancel();
    _tickTimer = null;
    await ampSub?.cancel();

    String? finalPath;
    try {
      finalPath = await _recorder.stop();
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _error = 'Recorder stop failed: $e';
        _phase = _Phase.error;
      });
      return null;
    }
    return finalPath == null ? null : File(finalPath);
  }

  // ---------------- Save + persist ----------------

  /// Summary screen "Save & finish" — uploads every answer audio
  /// (best-effort) plus the overall audio, then PATCHes the step row
  /// with the structured TestDriveSummary. If uploads fail we still
  /// save the structured data so the rest of the inspection isn't
  /// blocked on flaky audio uploads.
  Future<void> _saveAndAdvance() async {
    final summary = _summary;
    if (summary == null) return;
    setState(() => _phase = _Phase.saving);

    final answerAudioUrls = <String, String>{};
    for (var i = 0; i < _answers.length; i++) {
      final file = i < _answerAudioFiles.length ? _answerAudioFiles[i] : null;
      if (file == null) continue;
      try {
        final bytes = await file.readAsBytes();
        final url = await _service.uploadStepMedia(
          widget.inspectionId,
          _stepId,
          bytes,
          mimeType: 'audio/wav',
        );
        answerAudioUrls[_answers[i].questionId] = url;
      } catch (_) {
        // Swallow — we'd rather persist the verdict than 500 the user
        // on a flaky per-answer upload.
      }
    }

    String? overallUrl;
    if (_overallAudioFile != null) {
      try {
        final bytes = await _overallAudioFile!.readAsBytes();
        overallUrl = await _service.uploadStepMedia(
          widget.inspectionId,
          _stepId,
          bytes,
          mimeType: 'audio/wav',
        );
      } catch (_) {/* same — soft-fail */}
    }

    final hydrated = summary.copyWithUrls(
      answerAudioUrls: answerAudioUrls,
      overallAudioUrl: overallUrl,
    );

    try {
      await _service.updateStep(
        widget.inspectionId,
        _stepId,
        mediaUrls: [
          ...answerAudioUrls.values,
          ?overallUrl,
        ],
        data: hydrated.toJson(),
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
    // After the final step saves, hand the jockey the full inspection
    // review (every captured step from RC through test drive). The AI
    // pricing call only fires once they tap "Confirm & get pricing" on
    // that screen — gives them one last look before we burn a gpt-4o
    // roundtrip on bad data.
    if (mounted) context.go('/inspection/${widget.inspectionId}/review');
  }

  void _redo() {
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).retry();
  }

  // ---------------- Persisted-view playback ----------------

  Future<void> _togglePlayback(String url) async {
    if (_isPlaying && _playingUrl == url) {
      await _player.pause();
      return;
    }
    _playingUrl = url;
    await _player.stop();
    await _player.play(UrlSource(url));
  }

  // ---------------- Render ----------------

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    switch (_phase) {
      case _Phase.resolving:
        return _BusyCenter(label: t.tdLoading);
      case _Phase.intro:
        return _IntroView(t: t, onStart: _startDrive);
      case _Phase.conversing:
        return _ConversingView(
          t: t,
          subPhase: _sub,
          questionIndex: _qIndex,
          totalQuestions: kTestDriveQuestions.length,
          listenElapsed: _listenElapsed,
          listenTotal: _listenTotal,
          answers: _answers,
        );
      case _Phase.summary:
        return _SummaryView(
          summary: _summary!,
          t: t,
          onSave: _saveAndAdvance,
        );
      case _Phase.saving:
        return _BusyCenter(label: t.tdSavingDrive);
      case _Phase.saved:
        return _BusyCenter(label: t.tdAdvancing);
      case _Phase.error:
        return _ErrorView(
          t: t,
          message: _error ?? t.tdSomethingWrong,
          onRetry: _startDrive,
        );
      case _Phase.persisted:
        return _PersistedView(
          summary: _persistedSummary!,
          t: t,
          isPlaying: _isPlaying,
          playingUrl: _playingUrl,
          onTogglePlay: _togglePlayback,
          onRedo: _redo,
          // Revisit-Continue jumps to the review screen — same path as
          // a fresh save — so the jockey can re-confirm the captured
          // data before re-running the AI pricing.
          onContinue: () =>
              context.go('/inspection/${widget.inspectionId}/review'),
        );
    }
  }
}

// ============================================================
// Sub-views
// ============================================================

class _IntroView extends StatelessWidget {
  final Translations t;
  final VoidCallback onStart;
  const _IntroView({required this.t, required this.onStart});

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.headset_mic_rounded,
                      color: AppColors.primary, size: 26),
                  const SizedBox(width: 10),
                  Text(t.tdHandsFreeTitle,
                      style: t.style(const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ))),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t.tdHandsFreeBody,
                style: t.style(const TextStyle(height: 1.4, fontSize: 14)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        SizedBox(
          height: 64,
          child: ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded,
                color: AppColors.onCtaDark, size: 28),
            label: Text(t.tdStartDrive,
                style: t.style(AppTextStyles.button)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(64),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t.tdNoMoreTaps,
          textAlign: TextAlign.center,
          style: t.style(AppTextStyles.caption)
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ConversingView extends StatelessWidget {
  final Translations t;
  final _SubPhase subPhase;
  final int questionIndex;
  final int totalQuestions;
  final Duration listenElapsed;
  final Duration listenTotal;
  final List<TestDriveAnswer> answers;

  const _ConversingView({
    required this.t,
    required this.subPhase,
    required this.questionIndex,
    required this.totalQuestions,
    required this.listenElapsed,
    required this.listenTotal,
    required this.answers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _isOverall(subPhase)
                ? t.tdOverallFeedbackHeader
                // Pattern: "Q 3 / 7" — language-neutral, reads
                // identically in every supported script and avoids
                // having to add another translation key per language.
                : '${t.tdAsking.replaceAll('…', '').trim()} ${questionIndex + 1} / $totalQuestions',
            style: t.style(AppTextStyles.body).copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Expanded(child: Center(child: _stage())),
        const SizedBox(height: 16),
        if (answers.isNotEmpty)
          _AnsweredRail(answers: answers),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _stage() {
    switch (subPhase) {
      case _SubPhase.speakingQuestion:
      case _SubPhase.speakingOverall:
        return _IconStage(
          t: t,
          icon: Icons.record_voice_over_rounded,
          colour: AppColors.primary,
          label: t.tdAsking,
          subLabel: t.tdListenCarefully,
        );
      case _SubPhase.listening:
      case _SubPhase.listeningOverall:
        return _ListeningStage(
          t: t,
          elapsed: listenElapsed,
          total: listenTotal,
        );
      case _SubPhase.transcribing:
        return _IconStage(
          t: t,
          icon: Icons.subtitles_rounded,
          colour: AppColors.primary,
          label: t.tdTranscribing,
          subLabel: t.tdHearingWhat,
        );
      case _SubPhase.parsing:
        return _IconStage(
          t: t,
          icon: Icons.psychology_rounded,
          colour: AppColors.primary,
          label: t.tdUnderstanding,
        );
      case _SubPhase.speakingAck:
        return _IconStage(
          t: t,
          icon: Icons.check_rounded,
          colour: AppColors.success,
          label: t.tdGotIt,
        );
      case _SubPhase.summarising:
        return _IconStage(
          t: t,
          icon: Icons.auto_awesome_rounded,
          colour: AppColors.primary,
          label: t.tdWrappingUp,
        );
    }
  }

  bool _isOverall(_SubPhase p) =>
      p == _SubPhase.speakingOverall ||
      p == _SubPhase.listeningOverall ||
      p == _SubPhase.summarising;
}

class _IconStage extends StatelessWidget {
  final Translations t;
  final IconData icon;
  final Color colour;
  final String label;
  final String? subLabel;
  const _IconStage({
    required this.t,
    required this.icon,
    required this.colour,
    required this.label,
    this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: colour, size: 48),
        ),
        const SizedBox(height: 16),
        Text(label,
            style: t.style(AppTextStyles.heading2).copyWith(fontSize: 22)),
        if (subLabel != null) ...[
          const SizedBox(height: 4),
          Text(subLabel!,
              style: t.style(AppTextStyles.body)
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}

class _ListeningStage extends StatelessWidget {
  final Translations t;
  final Duration elapsed;
  final Duration total;
  const _ListeningStage({
    required this.t,
    required this.elapsed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final remaining = total - elapsed;
    final secs = remaining.inMilliseconds < 0 ? 0 : remaining.inSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120, height: 120,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 7,
                backgroundColor: AppColors.surfaceMuted,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.error),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic_rounded,
                    color: AppColors.error, size: 36),
                const SizedBox(height: 6),
                Text('$secs s',
                    style: AppTextStyles.heading2.copyWith(
                      color: AppColors.error,
                      fontSize: 22,
                    )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(t.tdSpeakAnswer,
            style: t.style(AppTextStyles.body).copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

class _AnsweredRail extends StatelessWidget {
  final List<TestDriveAnswer> answers;
  const _AnsweredRail({required this.answers});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: answers
            .map((a) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${a.questionId} · ${a.value}',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final TestDriveSummary summary;
  final Translations t;
  final VoidCallback onSave;
  const _SummaryView({
    required this.summary,
    required this.t,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScoreHeader(summary: summary),
          const SizedBox(height: 16),
          ...summary.answers
              .map((a) => _AnswerRow(answer: a, t: t)),
          if (summary.overallSummary.isNotEmpty) ...[
            const SizedBox(height: 16),
            _OverallCard(text: summary.overallSummary),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check_rounded,
                  color: AppColors.onCtaDark),
              label: Text(t.saveAndFinish,
                  style: t.style(AppTextStyles.button)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreHeader extends ConsumerWidget {
  final TestDriveSummary summary;
  const _ScoreHeader({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final tone = _toneFor(summary.verdict);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(_iconFor(summary.verdict), color: tone, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_labelFor(t, summary.verdict),
                    style: t.style(AppTextStyles.heading3)
                        .copyWith(color: tone)),
                const SizedBox(height: 2),
                Text(
                  '${summary.answers.length} / '
                  '${kTestDriveQuestions.length} ${t.tdChecksComplete}',
                  style: t.style(AppTextStyles.caption)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text('${summary.healthScore}',
              style: AppTextStyles.heading1.copyWith(
                fontSize: 32,
                color: AppColors.textPrimary,
              )),
        ],
      ),
    );
  }

  Color _toneFor(TestDriveVerdict v) {
    switch (v) {
      case TestDriveVerdict.good:          return AppColors.success;
      case TestDriveVerdict.minorIssue:    return AppColors.warning;
      case TestDriveVerdict.concern:       return AppColors.warning;
      case TestDriveVerdict.criticalIssue: return AppColors.error;
      case TestDriveVerdict.inconclusive:  return AppColors.textSecondary;
    }
  }

  IconData _iconFor(TestDriveVerdict v) {
    switch (v) {
      case TestDriveVerdict.good:          return Icons.check_circle_rounded;
      case TestDriveVerdict.minorIssue:    return Icons.info_rounded;
      case TestDriveVerdict.concern:       return Icons.warning_rounded;
      case TestDriveVerdict.criticalIssue: return Icons.error_rounded;
      case TestDriveVerdict.inconclusive:  return Icons.help_outline_rounded;
    }
  }

  String _labelFor(Translations t, TestDriveVerdict v) {
    switch (v) {
      case TestDriveVerdict.good:          return t.tdVerdictGood;
      case TestDriveVerdict.minorIssue:    return t.tdVerdictMinor;
      case TestDriveVerdict.concern:       return t.tdVerdictConcern;
      case TestDriveVerdict.criticalIssue: return t.tdVerdictCritical;
      case TestDriveVerdict.inconclusive:  return t.tdVerdictInconclusive;
    }
  }
}

class _AnswerRow extends StatelessWidget {
  final TestDriveAnswer answer;
  final Translations t;
  const _AnswerRow({required this.answer, required this.t});

  @override
  Widget build(BuildContext context) {
    final lang = t.language;
    // Try to find a localised label for the canonical category value.
    final q = kTestDriveQuestions
        .where((x) => x.id == answer.questionId)
        .firstOrNull;
    final shortLabel = q?.shortLabel[lang] ?? answer.questionId;
    final valueLabel = q?.valueLabels[lang]?[answer.value]
        ?? _capitalised(answer.value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(shortLabel,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                )),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valueLabel,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                if (answer.notes != null && answer.notes!.trim().isNotEmpty)
                  Text(answer.notes!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capitalised(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _OverallCard extends ConsumerWidget {
  final String text;
  const _OverallCard({required this.text});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.tdOverallFeedback,
              style: t.style(AppTextStyles.caption).copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              )),
          const SizedBox(height: 6),
          Text(text,
              style: t.style(AppTextStyles.body).copyWith(height: 1.4)),
        ],
      ),
    );
  }
}

class _PersistedView extends StatelessWidget {
  final TestDriveSummary summary;
  final Translations t;
  final bool isPlaying;
  final String? playingUrl;
  final Future<void> Function(String url) onTogglePlay;
  final VoidCallback onRedo;
  final VoidCallback onContinue;

  const _PersistedView({
    required this.summary,
    required this.t,
    required this.isPlaying,
    required this.playingUrl,
    required this.onTogglePlay,
    required this.onRedo,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScoreHeader(summary: summary),
          const SizedBox(height: 16),
          ...summary.answers.map((a) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: _AnswerRow(answer: a, t: t)),
                  if (a.audioUrl != null)
                    _PlayChip(
                      t: t,
                      isPlaying: isPlaying && playingUrl == a.audioUrl,
                      onTap: () => onTogglePlay(a.audioUrl!),
                    ),
                ],
              ),
            );
          }),
          if (summary.overallSummary.isNotEmpty) ...[
            const SizedBox(height: 16),
            _OverallCard(text: summary.overallSummary),
            if (summary.overallAudioUrl != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: _PlayChip(
                  t: t,
                  isPlaying:
                      isPlaying && playingUrl == summary.overallAudioUrl,
                  onTap: () => onTogglePlay(summary.overallAudioUrl!),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRedo,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(t.redo,
                      style: t.style(AppTextStyles.button)
                          .copyWith(color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.onCtaDark),
                  label: Text(t.next, style: AppTextStyles.button),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayChip extends StatelessWidget {
  final Translations t;
  final bool isPlaying;
  final VoidCallback onTap;
  const _PlayChip({
    required this.t,
    required this.isPlaying,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.primary,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(isPlaying ? t.tdPlaying : t.tdPlay,
                style: t.style(AppTextStyles.caption).copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

class _BusyCenter extends StatelessWidget {
  final String label;
  const _BusyCenter({required this.label});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 14),
          Text(label,
              style: AppTextStyles.body
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Translations t;
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({
    required this.t,
    required this.message,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message,
                textAlign: TextAlign.center,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.error)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.onCtaDark),
            label: Text(t.tdStartOver,
                style: t.style(AppTextStyles.button)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Intro + wrap-up prompts (localised)
// ============================================================

class _LangPair {
  final String spokenSsml;
  final String display;
  const _LangPair(this.spokenSsml, this.display);
}

_LangPair _introFor(AppLanguage l) {
  switch (l) {
    case AppLanguage.english:
      return const _LangPair(
        '<speak>Ready for the test drive? <break time="300ms"/> When you tap Start, I\'ll ask 7 short questions while you drive. <break time="300ms"/> Drive safely — eyes on the road.</speak>',
        'Ready for the test drive? Tap Start when you\'re behind the wheel.',
      );
    case AppLanguage.hindi:
      return const _LangPair(
        '<speak>Test drive के लिए तैयार हैं? <break time="300ms"/> Start दबाने पर मैं 7 छोटे सवाल पूछूँगा drive के दौरान। <break time="300ms"/> सावधानी से चलाइए, ध्यान road पर रखिए।</speak>',
        'Test drive के लिए तैयार? Steering पर बैठ कर Start दबाइए।',
      );
    case AppLanguage.telugu:
      return const _LangPair(
        '<speak>టెస్ట్ డ్రైవ్ కోసం సిద్ధంగా ఉన్నారా? <break time="300ms"/> Start నొక్కినప్పుడు, నేను డ్రైవ్ చేస్తున్నప్పుడు 7 చిన్న ప్రశ్నలు అడుగుతాను. <break time="300ms"/> జాగ్రత్తగా నడపండి, దృష్టి రోడ్డుపై ఉంచండి.</speak>',
        'టెస్ట్ డ్రైవ్‌కి సిద్ధంగా ఉన్నారా? స్టీరింగ్ వద్దకు వెళ్లి Start నొక్కండి.',
      );
    case AppLanguage.bengali:
      return const _LangPair(
        '<speak>টেস্ট ড্রাইভের জন্য প্রস্তুত? <break time="300ms"/> Start চাপলে আমি ৭টি ছোট প্রশ্ন করব ড্রাইভ চলাকালীন। <break time="300ms"/> সাবধানে চালান, চোখ রাস্তায় রাখুন।</speak>',
        'টেস্ট ড্রাইভের জন্য প্রস্তুত? স্টিয়ারিং-এ বসে Start চাপুন।',
      );
  }
}

/// Spoken inner SSML (no outer `<speak>` wrap) + display label used
/// when the parser flagged the previous answer as `unclear` and we're
/// re-asking the same question. The spoken portion is concatenated
/// with the original question inside one `<speak>` envelope.
({String spokenInner, String display}) _didntCatchThatFor(AppLanguage l) {
  switch (l) {
    case AppLanguage.english:
      return (
        spokenInner: "I didn't catch that — let me ask again.",
        display: "Didn't catch that — asking again.",
      );
    case AppLanguage.hindi:
      return (
        spokenInner: 'मुझे ठीक से समझ नहीं आया — एक बार और पूछता हूँ।',
        display: 'समझ नहीं आया — फिर से पूछ रहा हूँ।',
      );
    case AppLanguage.telugu:
      return (
        spokenInner: 'నాకు సరిగ్గా అర్థం కాలేదు — మళ్ళీ అడుగుతున్నాను.',
        display: 'అర్థం కాలేదు — మళ్ళీ అడుగుతున్నాను.',
      );
    case AppLanguage.bengali:
      return (
        spokenInner: 'আমি ঠিকঠাক বুঝতে পারিনি — আবার জিজ্ঞাসা করছি।',
        display: 'বুঝতে পারিনি — আবার জিজ্ঞাসা করছি।',
      );
  }
}

_LangPair _wrapUpFor(AppLanguage l) {
  switch (l) {
    case AppLanguage.english:
      return const _LangPair(
        '<speak>Thanks. <break time="300ms"/> You can pull over now and review the summary on screen.</speak>',
        'Thanks — review the summary and tap Save & finish.',
      );
    case AppLanguage.hindi:
      return const _LangPair(
        '<speak>शुक्रिया। <break time="300ms"/> गाड़ी रोक कर screen पर summary देखिए।</speak>',
        'शुक्रिया — summary देख कर Save दबाइए।',
      );
    case AppLanguage.telugu:
      return const _LangPair(
        '<speak>ధన్యవాదాలు. <break time="300ms"/> ఇప్పుడు కారు ఆపి స్క్రీన్‌లో సారాంశం చూడవచ్చు.</speak>',
        'ధన్యవాదాలు — సారాంశం చూసి Save నొక్కండి.',
      );
    case AppLanguage.bengali:
      return const _LangPair(
        '<speak>ধন্যবাদ। <break time="300ms"/> এখন গাড়ি থামিয়ে স্ক্রিনে সারসংক্ষেপ দেখুন।</speak>',
        'ধন্যবাদ — সারসংক্ষেপ দেখে Save চাপুন।',
      );
  }
}
