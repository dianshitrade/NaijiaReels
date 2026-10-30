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

/// Business error codes (keep in sync with contracts/errors.md).
class ErrorCodes {
  ErrorCodes._();
  static const unauthorized = 40101;
  static const refreshInvalid = 40102;
  static const insufficientCoins = 40201;
  static const episodeLocked = 40301;
  static const notFound = 40401;
}

class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status, this.data});
  final int code;
  final String message;
  final int? status;
  final Object? data;

  bool get isLocked => status == 403 && code == ErrorCodes.episodeLocked;
  bool get isInsufficientCoins =>
      status == 402 && code == ErrorCodes.insufficientCoins;

  @override
  String toString() => 'ApiException($status/$code): $message';
}
