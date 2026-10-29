import 'package:media_kit/media_kit.dart';

bool _isPseudo(SubtitleTrack t) => t.id == 'auto' || t.id == 'no';

/// Picks the subtitle track to show for an HLS stream.
/// Priority: language == en (or en-*), then a track titled English / marked
/// default, then the first real (non auto/no) track. Returns null if none.
SubtitleTrack? pickSubtitleTrack(List<SubtitleTrack> tracks) {
  final real = tracks.where((t) => !_isPseudo(t)).toList();
  if (real.isEmpty) return null;
  for (final t in real) {
    final l = (t.language ?? '').toLowerCase();
    if (l == 'en' || l == 'eng' || l.startsWith('en-')) return t;
  }
  for (final t in real) {
    final n = (t.title ?? '').toLowerCase();
    if (n.contains('english') || t.isDefault == true) return t;
  }
  return real.first;
}
