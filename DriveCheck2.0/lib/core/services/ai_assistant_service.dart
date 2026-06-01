import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the AI assistant (voice prompts + bottom bar) is enabled
/// for this user. Defaults to ON.
///
/// Experienced jockeys who already know the flow can disable it from
/// the profile screen to skip every TTS narration and hide the bottom
/// bar. The toggle is persisted in [SharedPreferences] so the
/// preference survives app restarts.
///
/// Two integration points consume this:
///   * [AssistantUtteranceNotifier.say] — silently drops the
///     utterance + skips the ElevenLabs round-trip when disabled.
///   * [AssistantBottomBar] — collapses to an empty `SizedBox` when
///     disabled, so the screen reflows without a leftover gap.
class AiAssistantEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'ai_assistant_enabled';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    // Default true — new users get the guided experience; only
    // explicit toggle-off persists a `false`.
    return prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
    state = AsyncData(enabled);
  }
}

final aiAssistantEnabledProvider =
    AsyncNotifierProvider<AiAssistantEnabledNotifier, bool>(
        AiAssistantEnabledNotifier.new);
