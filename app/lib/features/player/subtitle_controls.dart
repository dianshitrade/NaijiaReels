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

/// Right-rail CC button: tap toggles, long-press or the small arrow opens
/// the language picker.
class SubtitleButton extends StatelessWidget {
  const SubtitleButton({super.key, required this.settings, required this.onTap, required this.onPick});
  final SubtitleSettings settings;
  final VoidCallback onTap;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final on = settings.enabled;
    final code = settings.preferredLang;
    final short = code == 'zh-Hans' ? 'ZH' : code.toUpperCase();
    return Material(
      color: Colors.transparent,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          key: const ValueKey('player-subs'),
          onTap: onTap,
          onLongPress: onPick,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(children: [
              Icon(on ? Icons.closed_caption : Icons.closed_caption_off_outlined,
                  size: 32, color: on ? Colors.white : Colors.white70),
              const SizedBox(height: 2),
              Text(on ? short : 'CC off',
                  key: const ValueKey('player-subs-label'),
                  style: const TextStyle(fontSize: 11, color: Colors.white)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Small arrow next to the CC button that opens the picker.
class SubtitleMenuArrow extends StatelessWidget {
  const SubtitleMenuArrow({super.key, required this.onPick});
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) => InkWell(
        key: const ValueKey('player-subs-menu'),
        onTap: onPick,
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(Icons.arrow_drop_down, size: 20, color: Colors.white70),
        ),
      );
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
          for (final l in kSubtitleLangs) _option(ctx, settings, l.code, l.label),
        ]),
      ),
    ),
  );
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
