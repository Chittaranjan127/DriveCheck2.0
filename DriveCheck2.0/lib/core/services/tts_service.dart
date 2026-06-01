import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_endpoints.dart';
import 'api_service.dart';

/// Plays text through ElevenLabs TTS via the backend `/ai/tts` Lambda.
/// Caches the resulting MP3 bytes in-memory keyed by (text, voiceId) so
/// repeated playback of the same line — the spoken quality-reason if the
/// jockey takes the same bad photo twice — doesn't burn ElevenLabs credits.
///
/// Singleton. Call [instance.speak(text)] from anywhere; failures are
/// swallowed (debugPrint only) so a TTS hiccup never blocks the UI.
class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final AudioPlayer _player = AudioPlayer();
  final Dio _dio = ApiService.create().dio;

  /// Broadcast of the underlying player's state. The assistant chat bubble
  /// subscribes to this to know when to flip from "thinking" (loading) to
  /// "speaking" (text + waveform) — keeping the visual in sync with the
  /// audio rather than showing the text before sound arrives.
  Stream<PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  // Bounded LRU. Each entry is the raw MP3 — typically 20-60 KB for a
  // 1-2 sentence utterance. _maxEntries * ~50 KB ≈ 1 MB upper bound.
  static const int _maxEntries = 20;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  /// Synthesises [text] via the backend and starts playback. Returns when
  /// playback STARTS (not when it finishes); await [_player.onPlayerComplete]
  /// externally if the caller cares about end-of-playback.
  ///
  /// Subsequent calls cancel any in-flight playback so two "speak"s in
  /// quick succession don't overlap.
  Future<void> speak(
    String text, {
    String? voiceId,
    String? modelId,
  }) async {
    if (text.trim().isEmpty) return;

    final cacheKey = '${voiceId ?? "_"}|$text';
    try {
      Uint8List bytes;
      final cached = _cache.remove(cacheKey);
      if (cached != null) {
        _cache[cacheKey] = cached; // LRU bump
        bytes = cached;
      } else {
        bytes = await _fetch(text, voiceId: voiceId, modelId: modelId);
        _cache[cacheKey] = bytes;
        while (_cache.length > _maxEntries) {
          _cache.remove(_cache.keys.first);
        }
      }

      await _player.stop();
      await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    } catch (e) {
      debugPrint('[tts] speak failed: $e');
    }
  }

  /// Stops any current playback. Safe to call from dispose hooks.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {/* ignore */}
  }

  /// Pauses in-flight playback; can be resumed via [resume] without
  /// re-fetching the MP3. No-op if nothing's playing.
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {/* ignore */}
  }

  /// Resumes a previously paused clip from where it left off.
  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (_) {/* ignore */}
  }

  Future<Uint8List> _fetch(
    String text, {
    String? voiceId,
    String? modelId,
  }) async {
    final res = await _dio.post(
      ApiEndpoints.tts,
      data: {
        'text': text,
        'voiceId': ?voiceId,
        'modelId': ?modelId,
      },
    );
    final data = (res.data as Map)['data'] as Map<String, dynamic>;
    final b64 = data['audioBase64'] as String;
    return base64Decode(b64);
  }
}
