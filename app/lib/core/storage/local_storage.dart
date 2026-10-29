import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

class LocalStorage {
  LocalStorage._();
  static const _boxName = 'naija_reels';
  static const _kDevice = 'device_id';
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kApiBase = 'api_base_override';
  static Box<dynamic>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  /// For tests: use an already-opened box.
  static void useBox(Box<dynamic> box) => _box = box;

  static String get deviceId {
    var id = _box?.get(_kDevice) as String?;
    if (id == null) {
      final r = Random.secure();
      id = 'and-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
      _box?.put(_kDevice, id);
    }
    return id;
  }

  static String? get accessToken => _box?.get(_kAccess) as String?;
  static String? get refreshToken => _box?.get(_kRefresh) as String?;

  static Future<void> saveTokens(String access, String refresh) async {
    await _box?.put(_kAccess, access);
    await _box?.put(_kRefresh, refresh);
  }

  static Future<void> clearTokens() async {
    await _box?.delete(_kAccess);
    await _box?.delete(_kRefresh);
  }

  static String? get apiBaseOverride => _box?.get(_kApiBase) as String?;
  static Future<void> setApiBaseOverride(String? v) async =>
      (v == null || v.trim().isEmpty)
          ? _box?.delete(_kApiBase)
          : _box?.put(_kApiBase, v.trim());

  static const _kSubsOn = 'subtitles_enabled';
  static const _kSubsLang = 'subtitles_lang';

  /// Subtitles are OFF unless the user turned them on.
  static bool get subtitlesEnabled => _box?.get(_kSubsOn) as bool? ?? false;
  static Future<void> setSubtitlesEnabled(bool v) async => _box?.put(_kSubsOn, v);

  /// Manually chosen language; null = follow the system locale.
  static String? get subtitleLang => _box?.get(_kSubsLang) as String?;
  static Future<void> setSubtitleLang(String? v) async =>
      v == null ? _box?.delete(_kSubsLang) : _box?.put(_kSubsLang, v);
}
