import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/main.dart' as app;

/// Hongguo-style player on the live API: loading poster, playing page,
/// "See translation" picker + Yoruba. Prints `SHOT:name` for host screencap
/// and QUALITY: lines (with the pool's [Quality] logs) for the upgrade proof.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('hongguo player shots', (t) async {
    Future<void> wait(int ms) async {
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pump(const Duration(milliseconds: 50));
    }

    Future<void> shot(String name, {int settle = 4000}) async {
      debugPrint('SHOT:$name');
      await wait(settle);
    }

    await app.main();
    // --- Home feed (5-tab shell) ---
    final homeTap = find.byKey(const ValueKey('player-tap-layer'));
    final framePoster = find.byKey(const ValueKey('first-frame-poster'));
    for (var i = 0; i < 120 && (homeTap.evaluate().isEmpty || framePoster.evaluate().isNotEmpty); i++) {
      await wait(1000);
    }
    debugPrint('HOME: playing=${homeTap.evaluate().isNotEmpty && framePoster.evaluate().isEmpty} '
        'watchAll=${find.byKey(const ValueKey('feed-watch-full')).evaluate().isNotEmpty} '
        'reward=${find.byKey(const ValueKey('reward-widget')).evaluate().isNotEmpty} '
        'badge=${find.byKey(const ValueKey('feed-badge')).evaluate().isNotEmpty} '
        'watching=${find.byKey(const ValueKey('feed-watching')).evaluate().isNotEmpty} '
        'comment=${find.byKey(const ValueKey('feed-top-comment')).evaluate().isNotEmpty} '
        'tabs=${['Home', 'Theater', 'Shop', 'Rewards', 'Me'].every((l) => find.text(l).evaluate().isNotEmpty)}');
    await wait(2500);
    await shot('hongguo_home');
    await t.ensureVisible(find.byKey(const ValueKey('feed-tab-following')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('feed-tab-following')));
    await wait(2500);
    debugPrint('HOME: following empty=${find.byKey(const ValueKey('feed-empty')).evaluate().isNotEmpty}');
    await shot('hongguo_home_following', settle: 1500);
    await t.ensureVisible(find.byKey(const ValueKey('feed-tab-for_you')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('feed-tab-for_you')));
    await wait(1000);
    await t.tap(find.text('Theater').last);
    await wait(500);
    for (var i = 0; i < 150 && find.byKey(const ValueKey('theater-grid')).evaluate().isEmpty; i++) {
      await wait(1000);
    }
    debugPrint(
        'THEATER: cards=${find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('theater-card-')).evaluate().length}');
    await shot('hongguo_theater', settle: 6000);
    await t.tap(find.byKey(const ValueKey('quick-charts')));
    await wait(3000);
    await shot('hongguo_theater_charts', settle: 3000);
    await t.pageBack();
    await wait(800);
    await t.tap(find.byKey(const ValueKey('quick-coming-soon')));
    await wait(2000);
    await t.tap(find.byKey(const ValueKey('remind-dr_danfo')));
    await wait(600);
    debugPrint('THEATER: danfo count=${(t.widget<Text>(find.byKey(const ValueKey('coming-count-dr_danfo')))).data}');
    await shot('hongguo_theater_coming_soon', settle: 2000);
    await t.pageBack();
    await wait(800);
    // --- Shop ---
    await t.tap(find.text('Shop').last);
    for (var i = 0; i < 30 && find.byKey(const ValueKey('shop-list')).evaluate().isEmpty; i++) {
      await wait(500);
    }
    debugPrint('SHOP: list=${find.byKey(const ValueKey('shop-list')).evaluate().isNotEmpty} '
        'countdown=${find.byKey(const ValueKey('countdown-pk_coins_first')).evaluate().isNotEmpty}');
    await shot('hongguo_shop', settle: 2500);
    await t.tap(find.text('Theater').last);
    await wait(800);
    final poster = find.byKey(const ValueKey('first-frame-poster'));
    GoRouter.of(t.element(find.byKey(const ValueKey('theater-grid')).first)).push('/drama/dr_mama/play?ep=0');
    for (var i = 0; i < 100 && poster.evaluate().isEmpty; i++) {
      await wait(50);
    }
    debugPrint('QUALITY: loading poster=${poster.evaluate().isNotEmpty} '
        'spinner=${find.byKey(const ValueKey('player-loading')).evaluate().isNotEmpty}');
    await wait(1500); // let the cover image decode (still before first frame)
    debugPrint('QUALITY: loading poster still=${poster.evaluate().isNotEmpty}');
    await shot('hongguo_loading', settle: 300);

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
    await shot('hongguo_nosubs');

    await t.tap(find.byKey(const ValueKey('see-translation')).first);
    await wait(1500);
    expect(find.text('Yorùbá'), findsOneWidget);
    await shot('hongguo_picker');
    await t.tap(find.byKey(const ValueKey('subs-opt-yo')));
    await wait(800);
    expect(find.text('Translation: Yorùbá'), findsWidgets);
    final txt = find.byKey(const ValueKey('player-subtitle-text'));
    await t.runAsync(() => prog().player.seek(Duration.zero));
    for (var i = 0; i < 80 && txt.evaluate().isEmpty; i++) {
      await wait(250);
    }
    if (txt.evaluate().isNotEmpty) {
      await t.runAsync(() async {
        await prog().player.pause();
        // freeze inside the cue so the shot still shows it
        final back = prog().player.state.position - const Duration(milliseconds: 400);
        await prog().player.seek(back.isNegative ? Duration.zero : back);
      });
      await wait(1000);
    }
    debugPrint('QUALITY: yo cue shown=${txt.evaluate().isNotEmpty} '
        'text="${txt.evaluate().isEmpty ? '' : t.widget<Text>(txt).data}" '
        'res=${prog().player.state.width}x${prog().player.state.height}');
    final info = find.byKey(const ValueKey('player-info'));
    if (txt.evaluate().isNotEmpty) {
      final sb = t.getRect(txt.first).bottom, it = t.getRect(info.first).top;
      debugPrint('QUALITY: subtitle bottom=$sb info top=$it overlap=${sb > it}');
      expect(sb <= it, isTrue);
    }
    expect(find.textContaining('All '), findsOneWidget);
    expect(find.text('AI-generated content'), findsOneWidget);
    await shot('hongguo_playing');

    await t.tap(find.byKey(const ValueKey('synopsis-toggle')).first);
    await wait(600);
    expect(find.textContaining('Less'), findsWidgets);
    if (txt.evaluate().isNotEmpty) {
      final sb = t.getRect(txt.first).bottom, it = t.getRect(info.first).top;
      debugPrint('QUALITY: expanded subtitle bottom=$sb info top=$it overlap=${sb > it}');
    }
    await shot('hongguo_synopsis');
    await t.tap(find.byKey(const ValueKey('synopsis-toggle')).first);
    await wait(400);

    await t.tap(find.byKey(const ValueKey('episodes-button')).first);
    await wait(2500);
    expect(find.byKey(const ValueKey('episodes-panel')), findsOneWidget);
    debugPrint('QUALITY: episodes panel locks=${find.byIcon(Icons.lock).evaluate().length}');
    await shot('hongguo_episodes');
    Navigator.of(t.element(find.byKey(const ValueKey('episodes-panel')))).pop();
    await wait(800);

    await t.tap(find.byKey(const ValueKey('player-fullscreen')).first);
    await wait(600);
    expect(find.byKey(const ValueKey('player-info')), findsNothing);
    expect(find.byKey(const ValueKey('player-more')), findsNothing);
    await shot('hongguo_fullscreen');
    await t.tap(find.byKey(const ValueKey('exit-fullscreen')));
    await wait(600);
    expect(find.byKey(const ValueKey('player-info')), findsWidgets);

    await t.tap(find.byKey(const ValueKey('player-more')));
    await wait(1000);
    expect(find.text('Playback speed'), findsOneWidget);
    await shot('hongguo_menu');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
