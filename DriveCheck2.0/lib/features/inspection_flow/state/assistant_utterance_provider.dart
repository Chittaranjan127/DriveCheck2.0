import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ai_assistant_service.dart';
import '../../../core/services/tts_service.dart';

/// One utterance the AI assistant should display + speak. The spoken
/// text is SSML for ElevenLabs (`<speak>`/`<break>` tags); the bubble
/// strips tags when rendering. [issuedAt] is what the bubble uses as a
/// ValueKey so repeating the same text fires a fresh visual cycle.
///
/// When [autoplay] is false the bubble shows the text immediately with
/// the play button enabled, but no audio fires until the user taps it.
/// This is used when revisiting a completed step — we want the bubble's
/// context to update silently rather than re-narrate what the user has
/// already heard.
class AssistantUtterance {
  final String spokenSsml;
  final String? displayOverride;
  final bool autoplay;
  final DateTime issuedAt;

  AssistantUtterance({
    required this.spokenSsml,
    this.displayOverride,
    this.autoplay = true,
  }) : issuedAt = DateTime.now();
}

/// Single source of truth for what the AI assistant is "saying" right
/// now. Each step pushes an utterance via [say] in `initState` (intro
/// prompt) and again on OCR feedback. The shell-level [AssistantBubble]
/// watches this provider and reflects whatever the active step set.
class AssistantUtteranceNotifier extends Notifier<AssistantUtterance?> {
  @override
  AssistantUtterance? build() => null;

  /// Set the current utterance. When [autoplay] is true (default) the
  /// matching audio fires immediately via [TtsService]; the bubble's
  /// "thinking → speaking → done" lifecycle stays in sync with the real
  /// playback events.
  ///
  /// Gated by [aiAssistantEnabledProvider]: when the user has disabled
  /// the assistant from the profile screen, [say] silently drops the
  /// utterance (no text, no audio, no ElevenLabs round-trip) so the
  /// bar collapses and the inspection stays fully silent.
  void say(
    String spokenSsml, {
    String? display,
    bool autoplay = true,
  }) {
    final enabled = ref.read(aiAssistantEnabledProvider).valueOrNull ?? true;
    if (!enabled) {
      // Make sure nothing is mid-playback from before the user
      // disabled the assistant.
      state = null;
      unawaited(TtsService.instance.stop());
      return;
    }
    // If something else is mid-playback (the previous step's intro), stop
    // it before swapping in a silent utterance — otherwise the bubble will
    // still hear PlayerState.playing and flip back to the speaking phase
    // before the user sees the new text.
    if (!autoplay) {
      unawaited(TtsService.instance.stop());
    }
    state = AssistantUtterance(
      spokenSsml: spokenSsml,
      displayOverride: display,
      autoplay: autoplay,
    );
    if (autoplay && spokenSsml.trim().isNotEmpty) {
      unawaited(TtsService.instance.speak(spokenSsml));
    }
  }

  void clear() => state = null;
}

final assistantUtteranceProvider =
    NotifierProvider<AssistantUtteranceNotifier, AssistantUtterance?>(
        AssistantUtteranceNotifier.new);
