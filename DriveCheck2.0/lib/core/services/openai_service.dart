import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import 'api_service.dart';

/// Vision client. Calls the DriveCheck backend's `/ai/analyze-image` Lambda,
/// which proxies GPT-4o and returns parsed JSON.
class OpenAiService {
  final Dio _dio;
  OpenAiService([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  /// Sends [prompt] + image and asks the model to return a JSON object.
  /// Throws [OpenAiException] on transport or parse errors.
  Future<Map<String, dynamic>> analyzeImage({
    required String prompt,
    required File imageFile,
    String model = 'gpt-4o',
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64 = base64Encode(bytes);

    try {
      final response = await _dio.post(
        ApiEndpoints.analyzeImage,
        data: {
          'prompt': prompt,
          'model': model,
          'mimeType': 'image/jpeg',
          'imageBase64': base64,
        },
      );

      final body = response.data as Map<String, dynamic>;
      if (body['ok'] != true) {
        final err = body['error'] as Map<String, dynamic>?;
        throw OpenAiException(err?['message'] as String? ?? 'Backend returned ok=false');
      }
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw OpenAiException(_dioMessage(e));
    } on FormatException catch (e) {
      throw OpenAiException('Bad JSON: ${e.message}');
    }
  }
}

String _dioMessage(DioException e) {
  final status = e.response?.statusCode;
  final data = e.response?.data;
  if (status != null) return 'HTTP $status: ${data ?? e.message}';
  return 'Network error: ${e.message}';
}

class OpenAiException implements Exception {
  final String message;
  const OpenAiException(this.message);
  @override
  String toString() => message;
}
