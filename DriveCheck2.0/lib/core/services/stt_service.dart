import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'language_service.dart';
import 'transcribe_service.dart';

/// Speech-to-text via OpenAI Whisper (through the DriveCheck backend).
///
/// Records mic audio to a temp .m4a file using the `record` package, then
/// uploads it to /ai/transcribe and returns the text via [listen]'s
/// [onResult] callback. Single-shot — there are no partial results.
class SttService {
  static final SttService instance = SttService._();
  SttService._();

  final AudioRecorder _recorder = AudioRecorder();
  final TranscribeService _transcribe = TranscribeService();

  // Silence detection. `Amplitude.current` is dBFS-ish (negative; closer to 0
  // = louder). `-40` reliably catches normal speech without misfiring on a
  // quiet room background.
  static const double _speechThresholdDb = -40;
  static const Duration _ampPollInterval = Duration(milliseconds: 200);
  static const Duration _silenceHoldFor = Duration(milliseconds: 1200);
  static const Duration _minSpeechBeforeAutoStop = Duration(milliseconds: 400);

  Timer? _timeoutTimer;
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _firstSpeechAt;
  DateTime? _lastSpeechAt;
  bool _busy = false;

  AppLanguage? _activeLang;
  void Function(String text, bool isFinal)? _onResult;
  void Function(String errorMsg)? _onError;
  void Function()? _onDone;

  bool get isListening => _busy;

  /// Starts recording. Stops automatically after [timeout], or when
  /// [stop] is called. On completion the audio is uploaded and the
  /// transcript is delivered to [onResult] with `isFinal = true`.
  Future<bool> listen({
    required AppLanguage language,
    required void Function(String text, bool isFinal) onResult,
    void Function(String errorMsg)? onError,
    void Function()? onDone,
    Duration timeout = const Duration(seconds: 6),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    if (_busy) return false;
    try {
      if (!await _recorder.hasPermission()) {
        onError?.call('permission');
        return false;
      }
      final dir = await getTemporaryDirectory();
      // WAV (PCM 16-bit) is the most Whisper-friendly format. AAC-in-M4A from
      // `record` can come back as raw ADTS on some devices, which Whisper
      // rejects with "could not be decoded". A 6s 16kHz mono WAV is ~192KB —
      // small enough to base64-post without thought.
      final path = '${dir.path}/stt-${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      _busy = true;
      _activeLang = language;
      _onResult = onResult;
      _onError = onError;
      _onDone = onDone;
      _firstSpeechAt = null;
      _lastSpeechAt = null;
      _timeoutTimer = Timer(timeout, _finishAndTranscribe);
      _ampSub = _recorder
          .onAmplitudeChanged(_ampPollInterval)
          .listen(_onAmplitude);
      return true;
    } catch (e) {
      debugPrint('[stt] start failed: $e');
      _busy = false;
      onError?.call(e.toString());
      return false;
    }
  }

  /// Stop recording early. Triggers the upload + transcription flow.
  Future<void> stop() async {
    if (!_busy) return;
    await _finishAndTranscribe();
  }

  /// Throw the recording away — no transcription is performed.
  Future<void> cancel() async {
    if (!_busy) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;
    final onDone = _onDone;
    _resetActive();
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('[stt] cancel failed: $e');
    }
    onDone?.call();
  }

  void _onAmplitude(Amplitude amp) {
    final loud = amp.current > _speechThresholdDb;
    final now = DateTime.now();
    if (loud) {
      _firstSpeechAt ??= now;
      _lastSpeechAt = now;
      return;
    }
    if (_firstSpeechAt == null || _lastSpeechAt == null) return;
    final speech = _lastSpeechAt!.difference(_firstSpeechAt!);
    final silence = now.difference(_lastSpeechAt!);
    if (speech >= _minSpeechBeforeAutoStop && silence >= _silenceHoldFor) {
      _finishAndTranscribe();
    }
  }

  Future<void> _finishAndTranscribe() async {
    if (!_busy) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;

    final lang = _activeLang;
    final onResult = _onResult;
    final onError = _onError;
    final onDone = _onDone;
    _resetActive();

    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      debugPrint('[stt] stop failed: $e');
      onError?.call(e.toString());
      onDone?.call();
      return;
    }

    if (path == null || lang == null) {
      onError?.call('no_audio');
      onDone?.call();
      return;
    }

    final file = File(path);
    try {
      final text = await _transcribe.transcribe(
        file,
        language: lang,
        mimeType: 'audio/wav',
      );
      if (text.isEmpty) {
        onError?.call('no_match');
      } else {
        onResult?.call(text, true);
      }
    } catch (e) {
      debugPrint('[stt] transcribe failed: $e');
      onError?.call(e.toString());
    } finally {
      try { await file.delete(); } catch (_) {}
      onDone?.call();
    }
  }

  void _resetActive() {
    _busy = false;
    _activeLang = null;
    _onResult = null;
    _onError = null;
    _onDone = null;
  }
}
