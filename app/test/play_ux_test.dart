import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';

void main() {
  testWidgets('tap layer shows play icon after onTap when parent sets showPlayIcon', (t) async {
    var taps = 0;
    var playing = true;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (ctx, setState) {
          return PlayerTapLayer(
            showPlayIcon: !playing,
            onTap: () => setState(() {
              taps++;
              playing = !playing;
            }),
            onDoubleTap: (_) {},
          );
        }),
      ),
    ));
    expect(find.byKey(const ValueKey('player-play-icon')), findsNothing);
    await t.tap(find.byKey(const ValueKey('player-tap-layer')));
    // onTap+onDoubleTap share the arena; wait past double-tap timeout.
    await t.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(playing, isFalse);
    expect(find.byKey(const ValueKey('player-play-icon')), findsOneWidget);
  });

  testWidgets('Like button toggles liked visual state', (t) async {
    var liked = false;
    var count = 100;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (ctx, setState) {
          return PlayerChrome(
            title: 'Test Drama',
            episodeNo: 1,
            episodeTitle: 'Ep 1',
            total: 10,
            index: 0,
            liked: liked,
            likeCount: count,
            onLike: () => setState(() {
              liked = !liked;
              count += liked ? 1 : -1;
            }),
          );
        }),
      ),
    ));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('player-like')));
    await t.pump();
    expect(liked, isTrue);
    expect(count, 101);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('Share button invokes share callback', (t) async {
    var shared = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerChrome(
          title: 'Mama',
          episodeNo: 2,
          episodeTitle: 'Ep 2',
          total: 5,
          index: 1,
          onShare: () => shared = true,
        ),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('player-share')));
    await t.pump();
    expect(shared, isTrue);
  });

  testWidgets('Comment opens bottom sheet with coming soon', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          return PlayerChrome(
            title: 'Mama',
            episodeNo: 1,
            episodeTitle: 'Ep 1',
            total: 5,
            index: 0,
            onComment: () {
              showModalBottomSheet<void>(
                context: ctx,
                builder: (_) => const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Comments coming soon'),
                  ),
                ),
              );
            },
          );
        }),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('player-comment')));
    await t.pumpAndSettle();
    expect(find.textContaining('coming soon'), findsOneWidget);
  });

  testWidgets('display chrome gradient does not block like hit target', (t) async {
    var liked = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          PlayerChrome(
            title: 'X',
            episodeNo: 1,
            episodeTitle: 'Y',
            total: 3,
            index: 0,
            liked: liked,
            onLike: () => liked = true,
          ),
        ]),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('player-like')));
    expect(liked, isTrue);
  });

  testWidgets('drag seek bar changes position', (t) async {
    var pos = const Duration(seconds: 10);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 300,
            child: StatefulBuilder(builder: (ctx, setState) => PlayerSeekBar(
                  position: pos,
                  duration: const Duration(seconds: 65),
                  onSeek: (d) => setState(() => pos = d),
                )),
          ),
        ),
      ),
    ));
    final bar = find.byKey(const ValueKey('player-seekbar'));
    expect(t.getSize(bar).height, greaterThanOrEqualTo(24));
    final g = await t.startGesture(t.getTopLeft(bar) + const Offset(30, 16));
    await g.moveBy(const Offset(60, 0));
    await g.moveBy(const Offset(60, 0));
    await t.pump();
    expect(find.byKey(const ValueKey('seek-time')), findsOneWidget);
    expect(find.textContaining('/ 01:05'), findsOneWidget);
    await g.up();
    await t.pump();
    expect(pos, isNot(const Duration(seconds: 10)));
    expect(pos.inSeconds, greaterThan(20));
  });
}

