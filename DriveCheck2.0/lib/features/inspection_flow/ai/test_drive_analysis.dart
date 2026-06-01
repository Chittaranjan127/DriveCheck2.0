import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/language_service.dart';

// Convenience re-export so the step widget only needs one import for
// everything test-drive related (the question table + the analyzers).
export 'test_drive_questions.dart';

/// Bucketed verdict for the final summary card. Same rough buckets as
/// the engine-sound step so the two health-checks render with
/// consistent colour-coding on the summary screen.
enum TestDriveVerdict {
  good,
  minorIssue,
  concern,
  criticalIssue,
  inconclusive,
}

TestDriveVerdict _verdictFromScore(int score, {required int issueCount}) {
  if (score >= 85 && issueCount == 0) return TestDriveVerdict.good;
  if (score >= 65) return TestDriveVerdict.minorIssue;
  if (score >= 35) return TestDriveVerdict.concern;
  if (score >  0)  return TestDriveVerdict.criticalIssue;
  return TestDriveVerdict.inconclusive;
}

/// One driver answer post-transcription + post-parse. [audioUrl] is
/// filled in after the per-question recording is uploaded to S3 in
/// the step's confirm phase.
class TestDriveAnswer {
  final String questionId;
  final String questionText;     // localised question shown on summary
  final String transcription;    // raw Whisper output
  final String value;            // canonical machine id from the question
  final String? notes;           // extra detail the driver mentioned
  final double confidence;       // 0-1
  final String? acknowledgment;  // TTS-friendly read-back ("Got it…")
  final String? audioUrl;        // S3 URL after upload

  const TestDriveAnswer({
    required this.questionId,
    required this.questionText,
    required this.transcription,
    required this.value,
    required this.confidence,
    this.notes,
    this.acknowledgment,
    this.audioUrl,
  });

  TestDriveAnswer copyWith({String? audioUrl}) => TestDriveAnswer(
        questionId: questionId,
        questionText: questionText,
        transcription: transcription,
        value: value,
        confidence: confidence,
        notes: notes,
        acknowledgment: acknowledgment,
        audioUrl: audioUrl ?? this.audioUrl,
      );

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'questionText': questionText,
        'transcription': transcription,
        'value': value,
        'confidence': confidence,
        if (notes != null) 'notes': notes,
        if (acknowledgment != null) 'acknowledgment': acknowledgment,
        if (audioUrl != null) 'audioUrl': audioUrl,
      };

  static TestDriveAnswer fromJson(Map<String, dynamic> j) => TestDriveAnswer(
        questionId: j['questionId'] as String,
        questionText: (j['questionText'] as String?) ?? '',
        transcription: (j['transcription'] as String?) ?? '',
        value: (j['value'] as String?) ?? 'unclear',
        confidence: ((j['confidence'] as num?) ?? 0).toDouble(),
        notes: j['notes'] as String?,
        acknowledgment: j['acknowledgment'] as String?,
        audioUrl: j['audioUrl'] as String?,
      );
}

/// Final rolled-up result for the whole drive — what we persist on
/// the InspectionSteps row's `data` and what the summary screen
/// renders.
class TestDriveSummary {
  final List<TestDriveAnswer> answers;
  final String overallTranscription;
  final String overallSummary;   // model-condensed paraphrase
  final TestDriveVerdict verdict;
  final int healthScore;         // 0-100
  final String? overallAudioUrl;

  const TestDriveSummary({
    required this.answers,
    required this.overallTranscription,
    required this.overallSummary,
    required this.verdict,
    required this.healthScore,
    this.overallAudioUrl,
  });

  Map<String, dynamic> toJson() => {
        'answers': answers.map((a) => a.toJson()).toList(),
        'overallTranscription': overallTranscription,
        'overallSummary': overallSummary,
        'verdict': verdict.name,
        'healthScore': healthScore,
        if (overallAudioUrl != null) 'overallAudioUrl': overallAudioUrl,
      };

  static TestDriveSummary fromJson(Map<String, dynamic> j) => TestDriveSummary(
        answers: ((j['answers'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => TestDriveAnswer.fromJson(m.cast<String, dynamic>()))
            .toList(),
        overallTranscription: (j['overallTranscription'] as String?) ?? '',
        overallSummary: (j['overallSummary'] as String?) ?? '',
        verdict: _verdictFromString(j['verdict'] as String?),
        healthScore: ((j['healthScore'] as num?) ?? 0).toInt(),
        overallAudioUrl: j['overallAudioUrl'] as String?,
      );

  /// Convenience constructor that derives the verdict bucket + a
  /// heuristic health score from the categorical answers. Lets the
  /// client build a usable summary even when the overall-feedback
  /// model call fails — we still have all 6 categorical signals.
  factory TestDriveSummary.fromAnswers({
    required List<TestDriveAnswer> answers,
    required String overallTranscription,
    required String overallSummary,
  }) {
    final issues = answers.where(_isIssue).length;
    // Cheap heuristic: start at 100, subtract 12 per issue, floor at 0.
    // Tuned so 0 issues → 100, 3 issues → 64 (concern), 7+ issues → 0.
    final score = (100 - issues * 12).clamp(0, 100);
    return TestDriveSummary(
      answers: answers,
      overallTranscription: overallTranscription,
      overallSummary: overallSummary,
      verdict: _verdictFromScore(score, issueCount: issues),
      healthScore: score,
    );
  }

  TestDriveSummary copyWithUrls({
    Map<String, String>? answerAudioUrls,
    String? overallAudioUrl,
  }) {
    final updated = answers
        .map((a) => answerAudioUrls != null && answerAudioUrls.containsKey(a.questionId)
            ? a.copyWith(audioUrl: answerAudioUrls[a.questionId])
            : a)
        .toList();
    return TestDriveSummary(
      answers: updated,
      overallTranscription: overallTranscription,
      overallSummary: overallSummary,
      verdict: verdict,
      healthScore: healthScore,
      overallAudioUrl: overallAudioUrl ?? this.overallAudioUrl,
    );
  }
}

/// Mapping from canonical category id → "this is bad" boolean, used
/// by the heuristic score above. Anything not in this set is treated
/// as a non-issue.
const _badValues = {
  'jerky', 'sluggish', 'soft', 'pulling', 'vibrating',
  'slipping', 'bouncy', 'noisy', 'present',
};

bool _isIssue(TestDriveAnswer a) => _badValues.contains(a.value);

TestDriveVerdict _verdictFromString(String? s) {
  switch (s) {
    case 'good':          return TestDriveVerdict.good;
    case 'minorIssue':    return TestDriveVerdict.minorIssue;
    case 'concern':       return TestDriveVerdict.concern;
    case 'criticalIssue': return TestDriveVerdict.criticalIssue;
    default:              return TestDriveVerdict.inconclusive;
  }
}

/// Dio wrapper for `/ai/analyze-answer`. Takes the question context +
/// the transcription Whisper produced and returns the parsed
/// categorical value plus a TTS-friendly acknowledgment line.
class TestDriveAnswerParser {
  final Dio _dio;
  TestDriveAnswerParser([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  Future<Map<String, dynamic>> parse({
    required String transcription,
    required String questionText,
    required List<String> expectedValues,
    required AppLanguage language,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.analyzeAnswer,
        data: {
          'transcription': transcription,
          'questionText': questionText,
          'expectedValues': expectedValues,
          'language': _langCode(language),
        },
      );
      final body = res.data as Map<String, dynamic>;
      if (body['ok'] != true) {
        final err = body['error'] as Map<String, dynamic>?;
        throw TestDriveAnswerException(
          err?['message'] as String? ?? 'Backend returned ok=false',
        );
      }
      return (body['data'] as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw TestDriveAnswerException(_dioMessage(e));
    }
  }
}

/// Dio wrapper for `/ai/transcribe`. Used for every per-question +
/// overall recording; the parser then turns the text into structure.
class TestDriveTranscriber {
  final Dio _dio;
  TestDriveTranscriber([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  Future<String> transcribe(
    File audio, {
    required AppLanguage language,
    String mimeType = 'audio/wav',
    String filename = 'answer.wav',
  }) async {
    try {
      final bytes = await audio.readAsBytes();
      final res = await _dio.post(
        ApiEndpoints.transcribe,
        data: {
          'audioBase64': base64Encode(bytes),
          'language': _langCode(language),
          'mimeType': mimeType,
          'filename': filename,
        },
      );
      final body = res.data as Map<String, dynamic>;
      if (body['ok'] != true) {
        final err = body['error'] as Map<String, dynamic>?;
        throw TestDriveAnswerException(
          err?['message'] as String? ?? 'Transcribe failed',
        );
      }
      return ((body['data'] as Map)['text'] as String?)?.trim() ?? '';
    } on DioException catch (e) {
      throw TestDriveAnswerException(_dioMessage(e));
    } catch (e) {
      debugPrint('[testDrive] transcribe failed: $e');
      rethrow;
    }
  }
}

class TestDriveAnswerException implements Exception {
  final String message;
  const TestDriveAnswerException(this.message);
  @override
  String toString() => message;
}

String _langCode(AppLanguage l) {
  switch (l) {
    case AppLanguage.english: return 'en';
    case AppLanguage.hindi:   return 'hi';
    case AppLanguage.telugu:  return 'te';
    case AppLanguage.bengali: return 'bn';
  }
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

