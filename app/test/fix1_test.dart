import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/features/home/home_feed_page.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/shared/widgets/measure_size.dart';

List<EpisodeItem> _eps(int n, {int season = 1}) => [
      for (var i = 1; i <= n; i++)
        EpisodeItem(
            id: 'dr_mama_ep$i',
            episodeNo: i,
            title: 'Episode $i',
            free: i < 3,
            locked: i >= 3,
            priceCoins: i >= 3 ? 20 : 0,
            seasonNumber: season),
    ];

void main() {
  group('P0-2 Episodes panel', () {
    Future<void> open(WidgetTester t, List<EpisodeItem> eps) async {
      await t.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: c,
                isScrollControlled: true,
                backgroundColor: const Color(0xFF16181A),
                builder: (_) => EpisodesPanel(
                    title: 'Mama-in-Law Wahala',
                    completed: false,
                    total: eps.length,
                    episodes: eps,
                    dramaCoverUrl: '',
                    currentIndex: 0,
                    onTap: (_) {}),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('every tile renders with a real size on screen', (t) async {
      await open(t, _eps(6));
      final panel = t.getRect(find.byKey(const ValueKey('episodes-panel')));
      expect(panel.height, greaterThan(250));
      for (var i = 1; i <= 6; i++) {
        final r = t.getRect(find.byKey(ValueKey('ep-tile-$i')));
        expect(r.width, greaterThan(40), reason: 'tile $i width');
        expect(r.height, greaterThan(70), reason: 'tile $i height');
        expect(panel.contains(r.center), isTrue, reason: 'tile $i inside panel');
      }
      expect(find.text('Ongoing · All 6 EPs'), findsOneWidget);
    });

    testWidgets('two seasons render two non-empty grids', (t) async {
      await open(t, [..._eps(3), ..._eps(2, season: 2)]);
      expect(find.byKey(const ValueKey('episodes-season-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('episodes-season-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('ep-tile-3')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('episodes-grid-s2'))).height, greaterThan(70));
    });

    testWidgets('empty list shows a message, not a blank sheet', (t) async {
      await open(t, const []);
      expect(find.text('No episodes yet'), findsOneWidget);
    });
  });

  group('P1-3 Watch full drama uses plannedEpisodes', () {
    for (final n in [6, 12, 40]) {
      testWidgets('$n EPs', (t) async {
        final d = Drama(id: 'x', title: 'T', coverUrl: '', tags: const [], episodeCount: 3, totalEpisodes: n);
        await t.pumpWidget(MaterialApp(home: Scaffold(body: WatchFullBar(total: d.plannedEpisodes, onTap: () {}))));
        expect(find.text('Watch full drama · $n EPs'), findsOneWidget);
      });
    }
    test('enrichDrama keeps the real count (no hardcoded 6)', () {
      expect(
          enrichDrama(const Drama(id: 'dr_lagos', title: 'L', coverUrl: '', tags: [], episodeCount: 9)).plannedEpisodes,
          9);
      expect(
          enrichDrama(const Drama(id: 'zz', title: 'Z', coverUrl: '', tags: [], episodeCount: 14)).plannedEpisodes, 14);
    });
  });

  group('P1-4 one source for counters', () {
    test('contract example for dr_mama EP1 and deterministic per id', () {
      expect(mockEpisodeCounts('dr_mama_ep1', 1), (2310, 148));
      expect(mockEpisodeCounts('dr_prince_ep3', 3), mockEpisodeCounts('dr_prince_ep3', 3));
    });
    test('reasonable: comments well below likes, slow decay across episodes', () {
      for (final d in ['dr_mama', 'dr_prince', 'dr_lagos']) {
        var prev = 1 << 30;
        for (var n = 1; n <= 6; n++) {
          final (likes, comments) = mockEpisodeCounts('${d}_ep$n', n);
          expect(likes, inInclusiveRange(100, 10000), reason: '$d ep$n likes');
          expect(comments, lessThan(likes ~/ 5), reason: '$d ep$n comments');
          expect(likes, lessThanOrEqualTo((prev * 1.1).round()));
          prev = likes;
        }
      }
    });
    test('Home feed item and player episodes get identical numbers', () {
      final d = enrichDrama(
          Drama(id: 'dr_mama', title: 'M', coverUrl: '', tags: const [], episodeCount: 6, episodes: _eps(6)));
      final again = enrichDrama(
          Drama(id: 'dr_mama', title: 'M', coverUrl: '', tags: const [], episodeCount: 6, episodes: _eps(6)));
      for (var i = 0; i < 6; i++) {
        expect(d.episodes[i].likeCount, again.episodes[i].likeCount);
        expect(d.episodes[i].commentCount, again.episodes[i].commentCount);
      }
      expect(d.episodes[0].likeCount, 2310);
      expect(d.episodes[0].commentCount, 148);
    });
    test('single formatter', () {
      expect(compactCount(43860), '44K');
      expect(compactCount(2310), '2.3K');
      expect(compactCount(148), '148');
    });
  });

  group('P1-5 top tabs', () {
    for (final w in [320.0, 360.0, 412.0]) {
      for (final tab in [4, 2, 0]) {
        testWidgets('width $w tab $tab fully visible', (t) async {
          await t.binding.setSurfaceSize(Size(w, 700));
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: Align(alignment: Alignment.topCenter, child: FeedTopBar(top: 0, tab: tab, onTab: (_) {})))));
          await t.pumpAndSettle();
          final view = t.getRect(find.byKey(const ValueKey('feed-tabs-scroll')));
          final r = t.getRect(find.text(kFeedTabs[tab].$1));
          expect(r.left, greaterThanOrEqualTo(view.left + kTabFade - 1), reason: 'left $r in $view');
          expect(r.right, lessThanOrEqualTo(view.right - kTabFade + 1), reason: 'right $r in $view');
        });
      }
    }
  });

  group('P1-6 subtitle above info', () {
    test('bottom edge = info top + gap', () {
      expect(subtitleBottomAbove(infoBottom: 84, infoHeight: 250), 346);
      expect(subtitleBottomAbove(infoBottom: 8, infoHeight: 180, gap: 12), 200);
    });
    testWidgets('MeasureSize reports the real height', (t) async {
      double? h;
      await t.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Align(child: MeasureSize(onHeight: (v) => h = v, child: const SizedBox(width: 10, height: 123)))));
      await t.pump();
      expect(h, 123);
    });
  });
}
