import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';

Finder hearts() => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('heart-'));

/// Mirrors EpisodeFeedPage wiring: double-tap sets heart, onHeartEnd clears it,
/// rail like button only toggles state.
Widget harness() {
  Offset? heartAt;
  var key = 0;
  var liked = false;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(builder: (ctx, setState) {
        return Stack(fit: StackFit.expand, children: [
          PlayerTapLayer(
            onTap: () {},
            heartAt: heartAt,
            heartKey: key,
            onDoubleTap: (p) => setState(() {
              liked = true;
              heartAt = p;
              key++;
            }),
            onHeartEnd: (k) {
              if (k == key) setState(() => heartAt = null);
            },
          ),
          PlayerChrome(
            title: 'T', episodeNo: 1, episodeTitle: 'Ep 1', total: 1, index: 0,
            liked: liked, likeCount: 1,
            onLike: () => setState(() => liked = !liked),
          ),
        ]);
      }),
    ),
  );
}

Future<void> doubleTap(WidgetTester t) async {
  final c = t.getCenter(find.byKey(const ValueKey('player-tap-layer'))) - const Offset(60, 0);
  await t.tapAt(c);
  await t.pump(const Duration(milliseconds: 50));
  await t.tapAt(c);
  await t.pump();
}

void main() {
  testWidgets('double-tap heart fades to 0 and is removed at end', (t) async {
    await t.pumpWidget(harness());
    await doubleTap(t);
    expect(hearts(), findsOneWidget);
    await t.pump(const Duration(milliseconds: 499));
    final op = t.widget<Opacity>(find.descendant(of: hearts(), matching: find.byType(Opacity)));
    expect(op.opacity, lessThan(0.01));
    await t.pumpAndSettle();
    expect(hearts(), findsNothing);
  });

  testWidgets('repeated double-taps never stack hearts', (t) async {
    await t.pumpWidget(harness());
    for (var n = 0; n < 4; n++) {
      await doubleTap(t);
      expect(hearts(), findsOneWidget);
      await t.pump(const Duration(milliseconds: 150));
    }
    await t.pumpAndSettle();
    expect(hearts(), findsNothing);
  });

  testWidgets('rail like button toggles state without a heart', (t) async {
    await t.pumpWidget(harness());
    await t.tap(find.byKey(const ValueKey('player-like')));
    await t.pump();
    expect(hearts(), findsNothing);
    await t.pumpAndSettle();
    expect(hearts(), findsNothing);
    final icon = t.widget<Icon>(
        find.descendant(of: find.byKey(const ValueKey('player-like')), matching: find.byType(Icon)));
    expect(icon.color, const Color(0xFFFE2C55)); // button now liked
  });
}
