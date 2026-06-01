import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import 'api_service.dart';
import 'language_service.dart';

/// Calls /ai/transcribe. Sends recorded audio (base64) to the backend, which
/// forwards it to OpenAI Whisper and returns the recognized text.
class TranscribeService {
  final Dio _dio;
  TranscribeService([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  Future<String> transcribe(
    File audioFile, {
    required AppLanguage language,
    String mimeType = 'audio/wav',
  }) async {
    final bytes = await audioFile.readAsBytes();
    final ext = mimeType.split('/').last;
    try {
      final res = await _dio.post(
        ApiEndpoints.transcribe,
        data: {
          'audioBase64': base64Encode(bytes),
          'language': language.code,
          'mimeType': mimeType,
          'filename': 'audio.$ext',
        },
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return (data['text'] as String? ?? '').trim();
    } on DioException catch (e) {
      throw TranscribeException(_dioMessage(e));
    }
  }
}

class TranscribeException implements Exception {
  final String message;
  const TranscribeException(this.message);
  @override
  String toString() => message;
}

String _dioMessage(DioException e) {
  final s = e.response?.statusCode;
  final body = e.response?.data;
  if (body is Map && body['error'] is Map) {
    return (body['error'] as Map)['message']?.toString() ?? 'Transcribe failed';
  }
  if (s != null) return 'HTTP $s';
  return e.message ?? 'Network error';
}
