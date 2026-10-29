import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';

void main() {
  testWidgets('loading poster: cover + spinner + text, never bare black', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: FirstFramePoster(
          pooled: null,
          onRetry: () {},
          message: 'Loading episode…',
          child: const ColoredBox(key: ValueKey('cover'), color: Colors.blue),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('first-frame-poster')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-loading')), findsOneWidget);
    expect(find.text('Loading episode…'), findsOneWidget);
  });

  testWidgets('drama-detail loading view has spinner on a gradient', (t) async {
    await t.pumpWidget(const MaterialApp(home: PlayerLoadingView(message: 'Loading drama…')));
    expect(find.byKey(const ValueKey('player-loading-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-loading')), findsOneWidget);
  });

  testWidgets('hongguo chrome: rail, title, synopsis More/Less, AI note, episodes bar', (t) async {
    var open = false;
    var eps = 0, title = 0, rewards = 0, full = 0;
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => PlayerChrome(
              title: 'Mama-in-Law Wahala',
              episodeNo: 7,
              episodeTitle: 'Ep 7',
              total: 80,
              completed: true,
              likeCount: 130,
              commentCount: 24,
              saveCount: 40,
              description: 'A new bride versus the most formidable mother-in-law in Lagos.',
              synopsisOpen: open,
              onToggleSynopsis: () => setState(() => open = !open),
              onTitle: () => title++,
              onRewards: () => rewards++,
              onEpisodes: () => eps++,
              onFullscreen: () => full++,
              translation: const Text('See translation'),
            ),
          ),
        ),
      ),
    ));
    for (final c in ['130', '24', '40', 'Share', 'Claim', 'AI-generated content', 'More', 'See translation']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    expect(find.text('Episodes · Completed · All 80 EPs'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-disc')), findsNothing);
    expect(find.byKey(const ValueKey('player-follow')), findsNothing);
    await t.tap(find.byKey(const ValueKey('synopsis-toggle')));
    await t.pump();
    expect(find.text('More'), findsNothing);
    expect(find.textContaining('Less', findRichText: true), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('synopsis-toggle')));
    await t.pump();
    expect(find.text('More'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('player-title')));
    await t.tap(find.byKey(const ValueKey('reward-widget')));
    await t.tap(find.byKey(const ValueKey('episodes-button')));
    await t.tap(find.byKey(const ValueKey('player-fullscreen')));
    expect([title, rewards, eps, full], [1, 1, 1, 1]);
  });

  testWidgets('ongoing drama label', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: PlayerChrome(title: 'X', episodeNo: 1, episodeTitle: 'e', total: 6)),
      ),
    ));
    expect(find.text('Episodes · Ongoing · All 6 EPs'), findsOneWidget);
  });

  testWidgets('top bar: back + EP n + more; no tabs/search', (t) async {
    var more = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [PlayerTopBar(episodeNo: 7, onMore: () => more++)]),
      ),
    ));
    expect(find.text('EP 7'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-search')), findsNothing);
    expect(find.text('For You'), findsNothing);
    await t.tap(find.byKey(const ValueKey('player-more')));
    expect(more, 1);
  });

  testWidgets('seek bar is brand green with a thumb', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerSeekBar(
            position: const Duration(seconds: 10), duration: const Duration(seconds: 60), onSeek: (_) {}),
      ),
    ));
    expect(find.byKey(const ValueKey('seek-thumb')), findsOneWidget);
    final hasGreen = t
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .any((b) => b.color == const Color(0xFF00A859));
    expect(hasGreen, isTrue);
  });
}
