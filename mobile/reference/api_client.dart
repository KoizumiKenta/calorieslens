import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';

/// Dio client with JWT auth, transparent refresh-token rotation, and
/// single-flight refresh (concurrent 401s wait on one refresh call).
class ApiClient {
  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(this),
      LogInterceptor(requestBody: false, responseBody: false),
    ]);
  }

  late final Dio _dio;
  final FlutterSecureStorage _storage;
  Future<bool>? _refreshing;

  Dio get dio => _dio;

  Future<String?> accessToken() => _storage.read(key: 'access_token');

  /// Single-flight refresh: first 401 triggers the rotation, the rest await it.
  Future<bool> refreshSession() => _refreshing ??= _doRefresh()
    ..whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    try {
      // Bare Dio: must not recurse through the auth interceptor
      final response = await Dio(BaseOptions(baseUrl: Env.apiBaseUrl)).post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      await _storage.write(key: 'access_token', value: response.data['access_token'] as String);
      await _storage.write(key: 'refresh_token', value: response.data['refresh_token'] as String);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Rotation family revoked (reuse detection) — full re-auth required
        await _storage.deleteAll();
      }
      return false;
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final ApiClient _client;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _client.accessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final isAuthRoute = err.requestOptions.path.startsWith('/auth/');
    if (err.response?.statusCode == 401 && !isAuthRoute) {
      if (await _client.refreshSession()) {
        final retried = await _client.dio.fetch(err.requestOptions);
        return handler.resolve(retried);
      }
    }
    handler.next(err);
  }
}
