import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';
import '../storage/local_storage.dart';
import 'api_response.dart';

final dioProvider = Provider<Dio>((ref) => buildDio());

final apiClientProvider =
    Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

BaseOptions _options() => BaseOptions(
      baseUrl: Env.apiRoot,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    );

/// Guest login against the current base URL; stores tokens in Hive.
Future<Map<String, dynamic>> guestLogin([Dio? raw]) async {
  final dio = raw ?? Dio(_options());
  final res = await dio.post<Map<String, dynamic>>('${Env.apiRoot}/auth/guest',
      data: {'deviceId': LocalStorage.deviceId, 'platform': 'android'});
  final data = res.data!['data'] as Map<String, dynamic>;
  await LocalStorage.saveTokens(
      data['accessToken'] as String, data['refreshToken'] as String);
  return data;
}

Future<bool> _refresh(Dio raw) async {
  final rt = LocalStorage.refreshToken;
  if (rt != null) {
    try {
      final res = await raw.post<Map<String, dynamic>>(
          '${Env.apiRoot}/auth/refresh',
          data: {'refreshToken': rt});
      final data = res.data!['data'] as Map<String, dynamic>;
      await LocalStorage.saveTokens(
          data['accessToken'] as String, data['refreshToken'] as String);
      return true;
    } catch (e) {
      debugPrint('[api] refresh failed: $e');
    }
  }
  try {
    await guestLogin(raw);
    return true;
  } catch (e) {
    debugPrint('[api] guest re-login failed: $e');
    return false;
  }
}

Dio buildDio() {
  final dio = Dio(_options());
  final raw = Dio(_options());
  dio.interceptors.add(QueuedInterceptorsWrapper(
    onRequest: (options, handler) {
      options.baseUrl = Env.apiRoot; // runtime-switchable from settings
      final token = LocalStorage.accessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (e, handler) async {
      final body = e.response?.data;
      final code = body is Map ? (body['code'] as num?)?.toInt() : null;
      final retried = e.requestOptions.extra['retried'] == true;
      if (e.response?.statusCode == 401 &&
          code == ErrorCodes.unauthorized &&
          !retried &&
          await _refresh(raw)) {
        final o = e.requestOptions
          ..extra['retried'] = true
          ..headers['Authorization'] = 'Bearer ${LocalStorage.accessToken}';
        try {
          return handler.resolve(await raw.fetch(o));
        } on DioException catch (e2) {
          return handler.next(e2);
        }
      }
      handler.next(e);
    },
  ));
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: false));
  }
  return dio;
}

/// Unwraps `{code,message,data}`; throws [ApiException] (with HTTP status and
/// error `data`, e.g. `priceCoins` for 40301) on failure.
class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  Future<T> get<T>(String path,
          {Map<String, dynamic>? query,
          required T Function(Object? data) decode}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query), decode);

  Future<T> post<T>(String path,
          {Object? body, required T Function(Object? data) decode}) =>
      _send(() => _dio.post<Object?>(path, data: body), decode);

  Future<T> _send<T>(Future<Response<Object?>> Function() call,
      T Function(Object? data) decode) async {
    try {
      final res = await call();
      final body = res.data;
      if (body is! Map<String, dynamic>) {
        throw ApiException(-1, 'Invalid response format', status: res.statusCode);
      }
      final parsed = ApiResponse<T>.fromJson(body, decode);
      if (!parsed.isSuccess) {
        throw ApiException(parsed.code, parsed.message, status: res.statusCode);
      }
      return parsed.data as T;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        throw ApiException((body['code'] as num?)?.toInt() ?? -1,
            body['message'] as String? ?? e.message ?? 'Network error',
            status: e.response?.statusCode, data: body['data']);
      }
      throw ApiException(-1, e.message ?? 'Network error',
          status: e.response?.statusCode);
    }
  }
}
