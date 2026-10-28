import 'package:hive_flutter/hive_flutter.dart';

class LocalStorage {
  LocalStorage._();
  static const _boxName = 'naija_reels';
  static const _tokenKey = 'auth_token';
  static Box<dynamic>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  static String? get token => _box?.get(_tokenKey) as String?;
  static Future<void> setToken(String? value) async =>
      value == null ? _box?.delete(_tokenKey) : _box?.put(_tokenKey, value);
}
