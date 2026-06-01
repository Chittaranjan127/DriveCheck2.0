import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_endpoints.dart';
import 'auth_token_holder.dart';

/// Shared Dio client. Reads base URL + API key from `.env` and stamps
/// `x-api-key` on every outbound request.
class ApiService {
  final Dio dio;
  ApiService._(this.dio);

  factory ApiService.create() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(_ApiKeyInterceptor());
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: false,   // keep API key out of logs
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
        logPrint: (o) => debugPrint('[api] $o'),
      ));
    }
    return ApiService._(dio);
  }
}

class _ApiKeyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final key = dotenv.env['API_KEY'] ?? '';
    if (key.isNotEmpty) options.headers['x-api-key'] = key;
    final jwt = AuthTokenHolder.instance.current;
    if (jwt != null && jwt.isNotEmpty) options.headers['Authorization'] = 'Bearer $jwt';
    handler.next(options);
  }
}

final apiServiceProvider = Provider<ApiService>((_) => ApiService.create());
