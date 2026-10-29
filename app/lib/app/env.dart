import '../core/storage/local_storage.dart';

/// API base. Compile-time default via
/// `--dart-define=API_BASE_URL=https://xxx.trycloudflare.com`; can be
/// overridden at runtime from the debug settings page (stored in Hive).
class Env {
  Env._();

  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4010',
  );

  static const String apiPrefix = '/api/v1';

  static String get apiBaseUrl {
    final o = LocalStorage.apiBaseOverride;
    final base = (o != null && o.isNotEmpty) ? o : defaultApiBaseUrl;
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  static String get apiRoot => '$apiBaseUrl$apiPrefix';

  /// Resolves backend-relative paths like `/media/x/cover.jpg`.
  static String resolve(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return '';
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    return '$apiBaseUrl${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }
}
