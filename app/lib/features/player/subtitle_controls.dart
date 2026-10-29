import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/material.dart';

import '../../core/player/subtitle_select.dart';
import '../../core/storage/local_storage.dart';

/// Subtitle on/off + language, persisted in Hive via [LocalStorage].
/// Default: OFF. When turned on without a manual pick, the language follows
/// the SYSTEM locale (not the app locale, which is pinned to English).
class SubtitleSettings extends ChangeNotifier {
  SubtitleSettings({Locale Function()? systemLocale})
      : _systemLocale = systemLocale ?? (() => PlatformDispatcher.instance.locale),
        _enabled = LocalStorage.subtitlesEnabled,
        _manual = LocalStorage.subtitleLang;

  final Locale Function() _systemLocale;
  bool _enabled;
  String? _manual;

  bool get enabled => _enabled;
  String? get manualLang => _manual;

  /// Language suggested by the system locale.
  String get systemLang => subtitleLangForLocale(_systemLocale());

  /// Language that would be used when on.
  String get preferredLang {
    final m = _manual;
    if (m != null && kSubtitleLangs.any((l) => l.code == m)) return m;
    return subtitleLangForLocale(_systemLocale());
  }

  /// Language to apply to players; null = off.
  String? get activeLang => _enabled ? preferredLang : null;

  Future<void> toggle() async {
    _enabled = !_enabled;
    notifyListeners();
    await LocalStorage.setSubtitlesEnabled(_enabled);
  }

  Future<void> choose(String? code) async {
    if (code == null) {
      _enabled = false;
    } else {
      _manual = code;
      _enabled = true;
    }
    notifyListeners();
    if (code != null) await LocalStorage.setSubtitleLang(code);
    await LocalStorage.setSubtitlesEnabled(_enabled);
  }
}

/// TikTok-style small "See translation" link under the title/description.
/// Off: "See translation"; on: "Translation: Yorùbá". Tap opens the picker.
class SeeTranslationLink extends StatelessWidget {
  const SeeTranslationLink({super.key, required this.settings, required this.onPick});
  final SubtitleSettings settings;
  final VoidCallback onPick;

  static String labelFor(SubtitleSettings s) =>
      s.enabled ? 'Translation: ${subtitleLabel(s.preferredLang)}' : 'See translation';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('see-translation'),
      behavior: HitTestBehavior.opaque,
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(labelFor(settings),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                fontFamilyFallback: kSubtitleFontFallback)),
      ),
    );
  }
}

Future<void> showSubtitlePicker(BuildContext context, SubtitleSettings settings) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Subtitles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          _option(ctx, settings, null, 'Off'),
          // System-locale language first (auto pick), then the rest.
          for (final l in _ordered(settings)) _option(ctx, settings, l.code, l.label),
        ]),
      ),
    ),
  );
}

List<SubtitleLang> _ordered(SubtitleSettings s) {
  final auto = s.systemLang;
  return [
    ...kSubtitleLangs.where((l) => l.code == auto),
    ...kSubtitleLangs.where((l) => l.code != auto),
  ];
}

Widget _option(BuildContext ctx, SubtitleSettings s, String? code, String label) {
  final selected = code == null ? !s.enabled : (s.enabled && s.preferredLang == code);
  return ListTile(
    key: ValueKey('subs-opt-${code ?? 'off'}'),
    dense: true,
    title: Text(label, style: const TextStyle(fontFamilyFallback: kSubtitleFontFallback)),
    trailing: selected ? const Icon(Icons.check, color: Colors.white) : null,
    onTap: () {
      s.choose(code);
      Navigator.pop(ctx);
    },
  );
}

/// System fonts only (nothing bundled): Roboto covers Latin + Yoruba tone
/// marks; Noto Sans CJK covers Chinese on Android.
const kSubtitleFontFallback = <String>[
  'Roboto',
  'Noto Sans',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Noto Sans CJK',
  'sans-serif',
];
