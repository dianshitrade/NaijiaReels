import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/main.dart' as app;

/// TikTok-style player on the live API: loading poster, playing page,
/// "See translation" picker + Yoruba. Prints `SHOT:name` for host screencap
/// and QUALITY: lines (with the pool's [Quality] logs) for the upgrade proof.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('tiktok player shots', (t) async {
    Future<void> wait(int ms) async {
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pump(const Duration(milliseconds: 50));
    }

    Future<void> shot(String name, {int settle = 4000}) async {
      debugPrint('SHOT:$name');
      await wait(settle);
    }

    await app.main();
    for (var i = 0; i < 150 && find.text('Trending').evaluate().isEmpty; i++) {
      await wait(1000);
    }
    final poster = find.byKey(const ValueKey('first-frame-poster'));
    GoRouter.of(t.element(find.text('Trending').first)).push('/drama/dr_mama/play?ep=0');
    for (var i = 0; i < 100 && poster.evaluate().isEmpty; i++) {
      await wait(50);
    }
    debugPrint('QUALITY: loading poster=${poster.evaluate().isNotEmpty} '
        'spinner=${find.byKey(const ValueKey('player-loading')).evaluate().isNotEmpty}');
    await shot('tiktok_loading', settle: 300);

    var ready = false;
    for (var i = 0; i < 450; i++) {
      await wait(200);
      if (find.byType(PlayerProgress).evaluate().isNotEmpty && poster.evaluate().isEmpty) {
        ready = true;
        break;
      }
    }
    debugPrint('QUALITY: first frame ready=$ready');
    expect(ready, isTrue);
    PlayerProgress prog() => t.widget<PlayerProgress>(find.byType(PlayerProgress).first);
    debugPrint('QUALITY: at first frame ${prog().player.state.width}x${prog().player.state.height}');
    for (var i = 0; i < 20; i++) {
      await wait(1000);
      debugPrint('QUALITY: t+${i + 1}s ${prog().player.state.width}x${prog().player.state.height}');
    }
    expect(find.text('See translation'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-subs')), findsNothing);
    await shot('tiktok_playing');

    await t.tap(find.byKey(const ValueKey('see-translation')).first);
    await wait(1500);
    expect(find.text('Yorùbá'), findsOneWidget);
    await shot('tiktok_picker');
    await t.tap(find.byKey(const ValueKey('subs-opt-yo')));
    await wait(800);
    expect(find.text('Translation: Yorùbá'), findsWidgets);
    final txt = find.byKey(const ValueKey('player-subtitle-text'));
    await t.runAsync(() => prog().player.seek(Duration.zero));
    for (var i = 0; i < 80 && txt.evaluate().isEmpty; i++) {
      await wait(250);
    }
    if (txt.evaluate().isNotEmpty) {
      await t.runAsync(() => prog().player.pause());
    }
    debugPrint('QUALITY: yo cue shown=${txt.evaluate().isNotEmpty} '
        'res=${prog().player.state.width}x${prog().player.state.height}');
    await shot('tiktok_translation');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
