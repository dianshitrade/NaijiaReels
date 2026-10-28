import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';
import '../storage/local_storage.dart';
import 'api_response.dart';

final dioProvider = Provider<Dio>((ref) => buildDio());

final apiClientProvider =
    Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

Dio buildDio({String? baseUrl}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl ?? Env.apiRoot,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    contentType: Headers.jsonContentType,
  ));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final token = LocalStorage.token;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }));
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }
  return dio;
}

/// Thin wrapper: unwraps `{code,message,data}` and throws [ApiException]
/// on non-zero code or transport errors.
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
        throw ApiException(-1, 'Invalid response format');
      }
      final parsed = ApiResponse<T>.fromJson(body, decode);
      if (!parsed.isSuccess) throw ApiException(parsed.code, parsed.message);
      return parsed.data as T;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        throw ApiException((body['code'] as num?)?.toInt() ?? -1,
            body['message'] as String? ?? e.message ?? 'Network error');
      }
      throw ApiException(e.response?.statusCode ?? -1, e.message ?? 'Network error');
    }
  }
}
