import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import '../models/user.dart';
import 'api_service.dart';

/// Calls /auth/* endpoints. Returns typed results; throws [AuthException] on failure.
class AuthService {
  final Dio _dio;
  AuthService([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  /// `mockOtp` is populated in dev for convenience; null in prod.
  Future<({bool sent, String? mockOtp})> requestOtp(String phoneNumber) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.requestOtp,
        data: {'phoneNumber': phoneNumber},
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return (sent: data['sent'] == true, mockOtp: data['mockOtp'] as String?);
    } on DioException catch (e) {
      throw AuthException(_dioMessage(e), code: _dioCode(e));
    }
  }

  Future<({String token, User user})> verifyOtp(
    String phoneNumber,
    String otp, {
    Map<String, dynamic>? deviceInfo,
    String? fcmToken,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phoneNumber': phoneNumber,
          'otp': otp,
          'deviceInfo': ?deviceInfo,
          'fcmToken': ?fcmToken,
        },
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return (
        token: data['token'] as String,
        user: User.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw AuthException(_dioMessage(e), code: _dioCode(e));
    }
  }

  /// Best-effort revocation. The JWT remains usable until expiry until the
  /// backend wires a session-validity check; the row is marked `revokedAt`.
  Future<void> logout() async {
    try {
      await _dio.post(ApiEndpoints.logout);
    } on DioException catch (e) {
      throw AuthException(_dioMessage(e), code: _dioCode(e));
    }
  }

  Future<User> getMe() async {
    try {
      final res = await _dio.get(ApiEndpoints.me);
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return User.fromJson(data);
    } on DioException catch (e) {
      throw AuthException(_dioMessage(e), code: _dioCode(e));
    }
  }

  Future<User> updateMe({
    String? name,
    String? email,
    String? preferredLanguage,
    String? employeeId,
    String? selfieUrl,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'email': ?email,
      'preferredLanguage': ?preferredLanguage,
      'employeeId': ?employeeId,
      'selfieUrl': ?selfieUrl,
    };
    try {
      final res = await _dio.patch(ApiEndpoints.me, data: body);
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return User.fromJson(data);
    } on DioException catch (e) {
      throw AuthException(_dioMessage(e), code: _dioCode(e));
    }
  }
}

enum AuthErrorKind { unauthorized, badRequest, network, server, unknown }

class AuthException implements Exception {
  final String message;
  final AuthErrorKind code;
  const AuthException(this.message, {this.code = AuthErrorKind.unknown});
  @override
  String toString() => message;
}

AuthErrorKind _dioCode(DioException e) {
  final s = e.response?.statusCode;
  if (s == 401) return AuthErrorKind.unauthorized;
  if (s == 400) return AuthErrorKind.badRequest;
  if (s != null && s >= 500) return AuthErrorKind.server;
  if (e.response == null) return AuthErrorKind.network;
  return AuthErrorKind.unknown;
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
