import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import 'api_service.dart';

/// Calls upload endpoints. Selfie upload sends a base64-encoded image; the
/// backend Lambda downscales to 512x512 JPEG and stores it on S3.
class UploadsService {
  final Dio _dio;
  UploadsService([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  /// Uploads [file] and returns the permanent public URL of the stored image.
  Future<String> uploadSelfie(File file) async {
    final bytes = await file.readAsBytes();
    final encoded = base64Encode(bytes);
    try {
      final res = await _dio.post(
        ApiEndpoints.uploadSelfie,
        data: {'imageBase64': encoded, 'mimeType': 'image/jpeg'},
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return data['url'] as String;
    } on DioException catch (e) {
      throw UploadsException(_dioMessage(e));
    }
  }
}

class UploadsException implements Exception {
  final String message;
  const UploadsException(this.message);
  @override
  String toString() => message;
}

String _dioMessage(DioException e) {
  final s = e.response?.statusCode;
  final body = e.response?.data;
  if (body is Map && body['error'] is Map) {
    return (body['error'] as Map)['message']?.toString() ?? 'Upload failed';
  }
  if (s != null) return 'HTTP $s';
  return e.message ?? 'Network error';
}
