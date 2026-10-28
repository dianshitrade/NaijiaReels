/// Build-time environment. Override with
/// `flutter run --dart-define=API_BASE_URL=https://xxx.trycloudflare.com`.
class Env {
  Env._();

  /// Default: Prism mock server reachable from the Android emulator.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4010',
  );

  static const String apiPrefix = '/api/v1';

  static String get apiRoot => '$apiBaseUrl$apiPrefix';
}
