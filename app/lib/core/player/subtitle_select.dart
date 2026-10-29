import 'dart:ui' show Locale;

import 'package:media_kit/media_kit.dart';

/// Subtitle languages published by the backend (master.m3u8 SUBTITLES +
/// /episodes/{id}/play `subtitles`). Labels are English / endonyms only.
class SubtitleLang {
  const SubtitleLang(this.code, this.label);
  final String code;
  final String label;
}

const kSubtitleLangs = <SubtitleLang>[
  SubtitleLang('en', 'English'),
  SubtitleLang('pcm', 'Naija Pidgin'),
  SubtitleLang('yo', 'Yorùbá'),
  SubtitleLang('ig', 'Igbo'),
  SubtitleLang('ha', 'Hausa'),
  SubtitleLang('fr', 'Français'),
  SubtitleLang('zh-Hans', 'Chinese'),
];

const kFallbackSubtitleLang = 'en';

String subtitleLabel(String code) =>
    kSubtitleLangs.firstWhere((l) => l.code == code,
        orElse: () => SubtitleLang(code, code)).label;

/// Maps a system locale to one of [kSubtitleLangs]; unknown → `en`.
/// en-NG→en, yo→yo, ig→ig, ha→ha, fr-*→fr, pcm→pcm, zh / zh-CN / zh-Hant…→zh-Hans.
String subtitleLangForLocale(Locale? locale) {
  final lang = (locale?.languageCode ?? '').toLowerCase();
  if (lang.startsWith('zh')) return 'zh-Hans';
  for (final l in kSubtitleLangs) {
    if (l.code == lang) return l.code;
  }
  return kFallbackSubtitleLang;
}

bool _isPseudo(SubtitleTrack t) => t.id == 'auto' || t.id == 'no';

/// Normalises mpv/HLS language tags (e.g. `eng`, `zh-hans`, `chi`, `yor`).
String? normalizeSubtitleLang(String? raw) {
  final l = (raw ?? '').trim().toLowerCase();
  if (l.isEmpty) return null;
  if (l.startsWith('zh') || l == 'chi' || l == 'zho') return 'zh-Hans';
  const iso3 = {'eng': 'en', 'yor': 'yo', 'ibo': 'ig', 'hau': 'ha', 'fra': 'fr', 'fre': 'fr'};
  if (iso3.containsKey(l)) return iso3[l];
  final base = l.split(RegExp('[-_]')).first;
  return base == 'pcm' ? 'pcm' : base;
}

/// The HLS track for [lang] (by LANGUAGE, then NAME/title), or null.
SubtitleTrack? pickSubtitleTrackForLang(List<SubtitleTrack> tracks, String lang) {
  final real = tracks.where((t) => !_isPseudo(t)).toList();
  for (final t in real) {
    if (normalizeSubtitleLang(t.language) == lang) return t;
  }
  final label = subtitleLabel(lang).toLowerCase();
  for (final t in real) {
    if ((t.title ?? '').toLowerCase() == label) return t;
  }
  return null;
}

/// Legacy helper: English first, then default, then first real track.
SubtitleTrack? pickSubtitleTrack(List<SubtitleTrack> tracks) {
  final real = tracks.where((t) => !_isPseudo(t)).toList();
  if (real.isEmpty) return null;
  final en = pickSubtitleTrackForLang(real, 'en');
  if (en != null) return en;
  for (final t in real) {
    final n = (t.title ?? '').toLowerCase();
    if (n.contains('english') || t.isDefault == true) return t;
  }
  return real.first;
}
