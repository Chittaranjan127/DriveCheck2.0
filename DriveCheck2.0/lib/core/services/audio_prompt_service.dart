import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'language_service.dart';

/// Plays per-language pre-recorded prompts shipped under
/// `assets/audio/prompts/<langCode>/<promptId>.mp3`.
/// Add new prompt ids by dropping files under all four language folders.
class AudioPromptService {
  static final AudioPromptService instance = AudioPromptService._();
  AudioPromptService._();

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _completionSub;

  /// Plays the localized variant of [promptId]. Silently no-ops if the asset
  /// is missing — keeps the UI working before audio files are dropped in.
  /// [onComplete] fires exactly once when playback finishes naturally; it does
  /// NOT fire if [stop] is called or playback errors.
  Future<void> play(
    String promptId,
    AppLanguage language, {
    VoidCallback? onComplete,
  }) async {
    final path = 'audio/prompts/${language.code}/$promptId.mp3';
    try {
      await stop();
      if (onComplete != null) {
        _completionSub = _player.onPlayerComplete.listen((_) {
          _completionSub?.cancel();
          _completionSub = null;
          onComplete();
        });
      }
      await _player.play(AssetSource(path));
    } catch (e) {
      debugPrint('[audio] prompt $path failed: $e');
      await _completionSub?.cancel();
      _completionSub = null;
    }
  }

  Future<void> stop() async {
    await _completionSub?.cancel();
    _completionSub = null;
    await _player.stop();
  }

  void dispose() {
    _completionSub?.cancel();
    _player.dispose();
  }
}

/// Prompt id constants. Audio files must exist at
/// `assets/audio/prompts/<lang>/<id>.mp3` for every language.
class PromptIds {
  static const whatsYourName = 'whats_your_name';
  static const takeSelfie = 'take_selfie';
}
