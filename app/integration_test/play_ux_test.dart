import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/main.dart' as app;

/// Player UX on a real EpisodeFeedPage (Mama): first-frame timing ep1 cold +
/// ep2 swipe, tap=pause, like, comments sheet, seek drag. Logs `UX:` lines.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> wait(WidgetTester t, int ms) async {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('player ux', (t) async {
    await app.main();
    await binding.convertFlutterSurfaceToImage();
    for (var i = 0; i < 150 && find.text('Trending').evaluate().isEmpty; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    final poster = find.byKey(const ValueKey('first-frame-poster'));
    final sw = Stopwatch()..start();
    GoRouter.of(t.element(find.text('Trending').first)).push('/drama/dr_mama/play?ep=0');
    var ok = false;
    for (var i = 0; i < 450; i++) {
      await wait(t, 200);
      if (find.byType(PlayerProgress).evaluate().isNotEmpty && poster.evaluate().isEmpty) {
        ok = true;
        break;
      }
    }
    debugPrint('UX: ep1 cold first frame ${sw.elapsedMilliseconds}ms ok=$ok');
    expect(ok, isTrue);
    await wait(t, 4000); // let ep2 preload

    // tap = pause
    PlayerProgress prog() => t.widget<PlayerProgress>(find.byType(PlayerProgress).first);
    await t.tapAt(t.getCenter(find.byType(PlayerTapLayer).first));
    await wait(t, 600);
    debugPrint('UX: after tap playing=${prog().player.state.playing}');
    expect(prog().player.state.playing, isFalse);
    expect(find.byKey(const ValueKey('player-play-icon')), findsOneWidget);
    await binding.takeScreenshot('player_paused');

    await t.tap(find.byKey(const ValueKey('player-like')).first);
    await wait(t, 300);
    expect(find.byIcon(Icons.favorite), findsWidgets);
    await binding.takeScreenshot('player_liked');

    await t.tap(find.byKey(const ValueKey('player-comment')).first);
    for (var i = 0; i < 6; i++) { await wait(t, 200); }
    expect(find.text('coming soon'), findsOneWidget);
    await binding.takeScreenshot('player_comments');
    Navigator.of(t.element(find.text('coming soon'))).pop();
    for (var i = 0; i < 6; i++) { await wait(t, 200); }

    // seek drag
    final bar = find.byKey(const ValueKey('player-seekbar')).first;
    final before = prog().player.state.position;
    final r = t.getRect(bar);
    final g = await t.startGesture(Offset(r.left + 20, r.center.dy));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(Offset(r.width * 0.4, 0));
    await wait(t, 200);
    expect(find.byKey(const ValueKey('seek-time')), findsOneWidget);
    await binding.takeScreenshot('player_seeking');
    await g.up();
    await wait(t, 1500);
    final after = prog().player.state.position;
    debugPrint('UX: seek before=$before after=$after');
    expect(after, isNot(before));

    // resume + swipe to ep2
    await t.tapAt(t.getCenter(find.byType(PlayerTapLayer).first));
    await wait(t, 600);
    final sw2 = Stopwatch()..start();
    await t.fling(find.byType(PageView), const Offset(0, -500), 1500);
    var ok2 = false;
    for (var i = 0; i < 300; i++) {
      await wait(t, 100);
      final pp = find.byType(PlayerProgress);
      if (pp.evaluate().isNotEmpty && poster.evaluate().isEmpty && i >= 3) {
        ok2 = true;
        break;
      }
    }
    debugPrint('UX: ep2 swipe first frame ${sw2.elapsedMilliseconds}ms ok=$ok2');
    await binding.takeScreenshot('player_ep2');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
