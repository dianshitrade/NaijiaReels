import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/shared/ai_label.dart';

Drama _real(String id, {int? total}) => Drama.fromJson({
      'id': id,
      'title': 'T',
      'episodeCount': 6,
      if (total != null) 'totalEpisodes': total,
      'episodes': [
        for (var i = 1; i <= 6; i++) {'id': '${id}_ep$i', 'episodeNo': i}
      ],
    });

void main() {
  test('mock never invents episode totals; every surface reads plannedEpisodes', () {
    for (final id in ['dr_mama', 'dr_prince', 'dr_lagos', 'dr_unknown']) {
      final summary = enrichDrama(_real(id)); // Home feed / Theater card
      final detail = enrichDrama(_real(id)); // player / episodes panel
      expect(summary.plannedEpisodes, 6, reason: id);
      expect(detail.plannedEpisodes, summary.plannedEpisodes, reason: id);
      expect(detail.plannedEpisodes, detail.episodes.length, reason: id);
      expect(detail.seasons, [1], reason: 'no invented seasons for $id');
      expect(detail.currentSeason, 1);
    }
  });

  test('real totalEpisodes from backend wins', () {
    expect(enrichDrama(_real('dr_mama', total: 60)).plannedEpisodes, 60);
  });

  test('single AI label', () => expect(kAiContentLabel, 'AI-generated content'));
}
