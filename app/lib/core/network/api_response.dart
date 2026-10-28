/// Unified backend envelope: `{code, message, data}`. `code == 0` means success.
class ApiResponse<T> {
  const ApiResponse({required this.code, required this.message, this.data});

  final int code;
  final String message;
  final T? data;

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? raw) fromData,
  ) {
    return ApiResponse<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      message: json['message'] as String? ?? '',
      data: json['data'] == null ? null : fromData(json['data']),
    );
  }
}

class ApiException implements Exception {
  ApiException(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';
}
