import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/language_service.dart';

/// Why the recording can't be used. `good` is the only verdict that
/// gates "save + advance"; everything else forces a re-record.
enum EngineSoundQuality {
  good,
  noisy,        // engine is audible but masked by wind / handling
  tooShort,     // < ~5 seconds of actual engine sound
  wrongAudio,   // speech, music, traffic, etc.
  silent,       // no audible engine at all
  unreadable,   // backend / OpenAI returned something we can't parse
}

EngineSoundQuality _qualityFromString(String? s) {
  switch (s) {
    case 'good':       return EngineSoundQuality.good;
    case 'noisy':      return EngineSoundQuality.noisy;
    case 'tooShort':   return EngineSoundQuality.tooShort;
    case 'wrongAudio': return EngineSoundQuality.wrongAudio;
    case 'silent':     return EngineSoundQuality.silent;
    default:           return EngineSoundQuality.unreadable;
  }
}

/// Rolled-up health verdict bucket from a usable engine recording.
/// Maps from the model's numeric [EngineSoundResult.healthScore] but
/// the bucket is also returned directly so a future model change can
/// tune the boundaries without forcing a client update.
enum EngineHealthVerdict {
  smooth,
  minorIssue,
  concern,
  criticalIssue,
  inconclusive,
}

EngineHealthVerdict _verdictFromString(String? s) {
  switch (s) {
    case 'smooth':        return EngineHealthVerdict.smooth;
    case 'minorIssue':    return EngineHealthVerdict.minorIssue;
    case 'concern':       return EngineHealthVerdict.concern;
    case 'criticalIssue': return EngineHealthVerdict.criticalIssue;
    default:              return EngineHealthVerdict.inconclusive;
  }
}

/// One acoustic cue the model heard in the recording. Canonical set
/// mirrors the backend prompt's allowed list — anything outside this
/// list is dropped (rather than rendered as a free-text chip) so the
/// UI can attach an icon + severity colour per id.
enum EngineIssue {
  knocking,
  ticking,
  misfire,
  roughIdle,
  beltSqueal,
  exhaustLeak,
  valveTap,
  rattle,
  whistle,
  unusualVibration,
  unknown;

  static EngineIssue fromString(String s) {
    switch (s) {
      case 'knocking':          return EngineIssue.knocking;
      case 'ticking':           return EngineIssue.ticking;
      case 'misfire':           return EngineIssue.misfire;
      case 'rough_idle':        return EngineIssue.roughIdle;
      case 'belt_squeal':       return EngineIssue.beltSqueal;
      case 'exhaust_leak':      return EngineIssue.exhaustLeak;
      case 'valve_tap':         return EngineIssue.valveTap;
      case 'rattle':            return EngineIssue.rattle;
      case 'whistle':           return EngineIssue.whistle;
      case 'unusual_vibration': return EngineIssue.unusualVibration;
      default:                  return EngineIssue.unknown;
    }
  }

  /// Display label shown on the warning chip in the result card.
  String get displayName {
    switch (this) {
      case EngineIssue.knocking:         return 'Knocking';
      case EngineIssue.ticking:          return 'Ticking';
      case EngineIssue.misfire:          return 'Misfire';
      case EngineIssue.roughIdle:        return 'Rough idle';
      case EngineIssue.beltSqueal:       return 'Belt squeal';
      case EngineIssue.exhaustLeak:      return 'Exhaust leak';
      case EngineIssue.valveTap:         return 'Valve tap';
      case EngineIssue.rattle:           return 'Rattle';
      case EngineIssue.whistle:          return 'Whistle';
      case EngineIssue.unusualVibration: return 'Vibration';
      case EngineIssue.unknown:          return 'Other';
    }
  }
}

/// Parsed response from `/ai/analyze-engine-sound`. Always has either
/// a `qualityReason*` pair (recording was unusable) OR a `summary*`
/// pair (engine analysed cleanly) — never both, never neither.
class EngineSoundResult {
  final EngineSoundQuality quality;
  final String? qualityReasonDisplay;
  final String? qualityReasonSpoken;

  final bool engineRunning;
  final int healthScore; // 0-100, 0 if quality != good
  final EngineHealthVerdict verdict;
  final List<EngineIssue> detectedIssues;

  final String? summaryDisplay;
  final String? summarySpoken;

  const EngineSoundResult({
    required this.quality,
    required this.engineRunning,
    required this.healthScore,
    required this.verdict,
    required this.detectedIssues,
    this.qualityReasonDisplay,
    this.qualityReasonSpoken,
    this.summaryDisplay,
    this.summarySpoken,
  });

  bool get isUsable => quality == EngineSoundQuality.good;

  factory EngineSoundResult.fromJson(Map<String, dynamic> j) => EngineSoundResult(
        quality: _qualityFromString(j['quality'] as String?),
        qualityReasonDisplay: _str(j['qualityReasonDisplay']),
        qualityReasonSpoken: _str(j['qualityReasonSpoken']),
        engineRunning: j['engineRunning'] == true,
        healthScore: _int(j['healthScore']) ?? 0,
        verdict: _verdictFromString(j['verdict'] as String?),
        detectedIssues: ((j['detectedIssues'] as List?) ?? const [])
            .whereType<String>()
            .map(EngineIssue.fromString)
            .where((e) => e != EngineIssue.unknown)
            .toList(growable: false),
        summaryDisplay: _str(j['summaryDisplay']),
        summarySpoken: _str(j['summarySpoken']),
      );

  /// Flattened map persisted on the step row's `aiAnalysis` field so
  /// a revisit can render the same verdict without re-calling OpenAI.
  Map<String, dynamic> toAiAnalysis() => {
        'quality': quality.name,
        if (qualityReasonDisplay != null) 'qualityReasonDisplay': qualityReasonDisplay,
        if (qualityReasonSpoken != null) 'qualityReasonSpoken': qualityReasonSpoken,
        'engineRunning': engineRunning,
        'healthScore': healthScore,
        'verdict': verdict.name,
        'detectedIssues': detectedIssues.map((e) => _issueToJson(e)).toList(),
        if (summaryDisplay != null) 'summaryDisplay': summaryDisplay,
        if (summarySpoken != null) 'summarySpoken': summarySpoken,
      };
}

/// Inverse of [EngineIssue.fromString] for the serialised form persisted
/// on the step row (keeps the backend allowlist as canonical naming).
String _issueToJson(EngineIssue e) {
  switch (e) {
    case EngineIssue.knocking:         return 'knocking';
    case EngineIssue.ticking:          return 'ticking';
    case EngineIssue.misfire:          return 'misfire';
    case EngineIssue.roughIdle:        return 'rough_idle';
    case EngineIssue.beltSqueal:       return 'belt_squeal';
    case EngineIssue.exhaustLeak:      return 'exhaust_leak';
    case EngineIssue.valveTap:         return 'valve_tap';
    case EngineIssue.rattle:           return 'rattle';
    case EngineIssue.whistle:          return 'whistle';
    case EngineIssue.unusualVibration: return 'unusual_vibration';
    case EngineIssue.unknown:          return 'unknown';
  }
}

String? _str(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty || t.toLowerCase() == 'null') return null;
    return t;
  }
  return v.toString();
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Sends a WAV/MP3 recording to `/ai/analyze-engine-sound` and returns
/// the parsed [EngineSoundResult]. The Lambda calls
/// `gpt-4o-audio-preview` so the model "hears" the recording directly
/// — no speech-to-text intermediate that would erase the acoustic
/// cues we actually care about (knock, tick, misfire).
class EngineSoundAnalyzer {
  final Dio _dio;
  EngineSoundAnalyzer([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  Future<EngineSoundResult> analyze(
    File audio, {
    required AppLanguage language,
    String format = 'wav',
  }) async {
    final bytes = await audio.readAsBytes();
    final base64Audio = base64Encode(bytes);
    try {
      final res = await _dio.post(
        ApiEndpoints.analyzeEngineSound,
        data: {
          'audioBase64': base64Audio,
          'format': format,
          'language': _langCode(language),
        },
      );
      final body = res.data as Map<String, dynamic>;
      if (body['ok'] != true) {
        final err = body['error'] as Map<String, dynamic>?;
        throw EngineSoundException(
            err?['message'] as String? ?? 'Backend returned ok=false');
      }
      final data = body['data'] as Map<String, dynamic>;
      return EngineSoundResult.fromJson(data);
    } on DioException catch (e) {
      throw EngineSoundException(_dioMessage(e));
    } catch (e) {
      debugPrint('[engineSound] analyze failed: $e');
      rethrow;
    }
  }

  String _langCode(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.english: return 'en';
      case AppLanguage.hindi:   return 'hi';
      case AppLanguage.telugu:  return 'te';
      case AppLanguage.bengali: return 'bn';
    }
  }
}

class EngineSoundException implements Exception {
  final String message;
  const EngineSoundException(this.message);
  @override
  String toString() => message;
}

String _dioMessage(DioException e) {
  final s = e.response?.statusCode;
  final body = e.response?.data;
  if (body is Map && body['error'] is Map) {
    return (body['error'] as Map)['message']?.toString() ?? 'Request failed';
  }
  if (s != null) return 'HTTP $s';
  return e.message ?? 'Network error';
}
