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

  testWidgets('right rail: follow badge, counts, disc, EP badge opens episodes', (t) async {
    var followed = false;
    var eps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (ctx, setState) => PlayerChrome(
            title: 'Mama',
            episodeNo: 1,
            episodeTitle: 'Ep 1',
            total: 6,
            index: 0,
            likeCount: 130,
            commentCount: 24,
            saveCount: 40,
            shareCount: 12,
            followed: followed,
            onFollow: () => setState(() => followed = !followed),
            onEpisodes: () => eps++,
            translation: const Text('See translation'),
          ),
        ),
      ),
    ));
    for (final c in ['130', '24', '40', '12']) {
      expect(find.text(c), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('follow-plus')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('player-follow')));
    await t.pump();
    expect(find.byKey(const ValueKey('follow-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-disc')), findsOneWidget);
    expect(find.text('See translation'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('episodes-button')));
    expect(eps, 1);
  });

  testWidgets('top bar: For You + tags, tap selects, search callback', (t) async {
    String? sel;
    var searched = 0;
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => Stack(children: [
              PlayerTopBar(
                tags: const ['family', 'comedy', 'romance', 'drama'],
                selected: sel,
                onSelect: (v) => setState(() => sel = v),
                onSearch: () => searched++,
                showWallet: false,
              ),
            ]),
          ),
        ),
      ),
    ));
    for (final l in ['For You', 'Family', 'Comedy', 'Romance', 'Drama']) {
      expect(find.text(l), findsOneWidget);
    }
    FontWeight? w(String l) => t.widget<Text>(find.text(l)).style?.fontWeight;
    expect(w('For You'), FontWeight.w800);
    await t.tap(find.byKey(const ValueKey('tab-comedy')));
    await t.pump();
    expect(sel, 'comedy');
    expect(w('Comedy'), FontWeight.w800);
    expect(w('For You'), FontWeight.w500);
    await t.tap(find.byKey(const ValueKey('player-search')));
    expect(searched, 1);
  });
}
