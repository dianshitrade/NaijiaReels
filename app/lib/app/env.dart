import '../core/storage/local_storage.dart';

/// API base. Compile-time default via
/// `--dart-define=API_BASE_URL=https://xxx.trycloudflare.com`; can be
/// overridden at runtime from the debug settings page (stored in Hive).
class Env {
  Env._();

  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://naijareels-api.onrender.com',
  );

  static const String apiPrefix = '/api/v1';

  static String get apiBaseUrl {
    final o = LocalStorage.apiBaseOverride;
    final base = (o != null && o.isNotEmpty) ? o : defaultApiBaseUrl;
    var b = base.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    // Accept bases given with the /api/v1 suffix too.
    if (b.endsWith(apiPrefix)) b = b.substring(0, b.length - apiPrefix.length);
    return b;
  }

  static String get apiRoot => '$apiBaseUrl$apiPrefix';

  /// Resolves backend-relative paths like `/media/x/cover.jpg`.
  static String resolve(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return '';
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    return '$apiBaseUrl${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }
}
