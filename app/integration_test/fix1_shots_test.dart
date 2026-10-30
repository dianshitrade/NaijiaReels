import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naija_reels/features/home/home_feed_page.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/main.dart' as app;

/// fix1 acceptance: Home autoplay without a tap (item 1, swipe to 3, back to 1),
/// subtitle/info coordinates on Home and the player, Episodes panel, no black
/// frame on tab switches. Prints `SHOT:fix1_*` and `FIX1:` lines (with wall clock).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('fix1 shots', (t) async {
    void log(String m) => debugPrint('FIX1: ${DateTime.now().toIso8601String()} $m');
    Future<void> wait(int ms) async {
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pump(const Duration(milliseconds: 50));
    }

    Future<void> shot(String name, {int settle = 2500}) async {
      debugPrint('SHOT:$name');
      await wait(settle);
    }

    /// Waits until feed item [i] reports an advancing frame; returns ms or -1.
    Future<int> autoplay(int i, String label, {int timeoutMs = 20000}) async {
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < timeoutMs) {
        final v = HomeFeedPage.debugPlaying.value;
        if (v != null && v.$1 == i) {
          log('autoplay $label item=${i + 1} ok focus->frame=${v.$2}ms waited=${sw.elapsedMilliseconds}ms tap=none');
          return v.$2;
        }
        await wait(100);
      }
      log('autoplay $label item=${i + 1} TIMEOUT ${sw.elapsedMilliseconds}ms');
      return -1;
    }

    void rects(String page, String? scopeKey, String infoKey) {
      final text = find.byKey(const ValueKey('player-subtitle-text'));
      final s = scopeKey == null ? text : find.descendant(of: find.byKey(ValueKey(scopeKey)), matching: text);
      final i = find.byKey(ValueKey(infoKey));
      if (s.evaluate().isEmpty || i.evaluate().isEmpty) {
        log('$page rect missing sub=${s.evaluate().length} info=${i.evaluate().length}');
        return;
      }
      final sr = t.getRect(s.first), ir = t.getRect(i.first);
      log('$page subtitle=${sr.toString()} info=${ir.toString()} gap=${(ir.top - sr.bottom).toStringAsFixed(1)} '
          'above=${sr.bottom <= ir.top}');
    }

    log('launch');
    await app.main();
    await t.pump();
    await shot('fix1_first_screen', settle: 300);
    final a1 = await autoplay(0, 'initial');
    await shot('fix1_home_item1_autoplay', settle: 1500);
    final tabs = t.getRect(find.byKey(const ValueKey('feed-tabs-scroll')));
    final sel = t.getRect(find.byKey(const ValueKey('feed-tab-for_you')));
    log('tabs viewport=$tabs selected=$sel inside=${sel.left >= tabs.left && sel.right <= tabs.right}');

    final pv = find.byType(PageView).first;
    for (final target in [1, 2]) {
      await t.fling(pv, const Offset(0, -500), 2000);
      await wait(200);
      log('swiped to item ${target + 1}');
      await autoplay(target, 'swipe-down');
    }
    await shot('fix1_home_item3_autoplay', settle: 1200);
    for (final target in [1, 0]) {
      await t.fling(pv, const Offset(0, 500), 2000);
      await wait(200);
      log('swiped back to item ${target + 1}');
      await autoplay(target, 'swipe-back');
    }
    await shot('fix1_home_back_item1_autoplay', settle: 1200);
    expect(a1, greaterThanOrEqualTo(0));

    // Tab switch: shot almost immediately; IndexedStack keeps pages, no black.
    await t.tap(find.text('Theater').last);
    await wait(150);
    await shot('fix1_tab_theater_150ms', settle: 1500);
    await t.tap(find.text('Home').last);
    await wait(150);
    await shot('fix1_tab_home_back_150ms', settle: 300);
    final back = await autoplay(0, 'tab-return');
    log('tab return autoplay=$back');

    // Player page.
    final poster = find.byKey(const ValueKey('first-frame-poster'));
    GoRouter.of(t.element(find.byType(PageView).first)).push('/drama/dr_mama/play?ep=0');
    await wait(120);
    await shot('fix1_player_open_120ms', settle: 200);
    final sw = Stopwatch()..start();
    var ready = false;
    for (var i = 0; i < 200; i++) {
      await wait(100);
      if (find.byType(PlayerProgress).evaluate().isNotEmpty && poster.evaluate().isEmpty) {
        ready = true;
        break;
      }
    }
    log('player autoplay ready=$ready after ${sw.elapsedMilliseconds}ms tap=none');
    await t.tap(find.byKey(const ValueKey('see-translation')).first);
    await wait(1200);
    await t.tap(find.byKey(const ValueKey('subs-opt-yo')));
    final txt = find.byKey(const ValueKey('player-subtitle-text'));
    for (var i = 0; i < 60 && txt.evaluate().isEmpty; i++) {
      await wait(250);
    }
    rects('player', null, 'player-info');
    await shot('fix1_player_subtitle', settle: 800);

    await t.tap(find.byKey(const ValueKey('episodes-button')).first);
    await wait(1500);
    final panel = find.byKey(const ValueKey('episodes-panel'));
    final tiles = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ep-tile-'));
    log('episodes panel=${panel.evaluate().isNotEmpty} '
        'rect=${panel.evaluate().isEmpty ? '-' : t.getRect(panel)} tiles=${tiles.evaluate().length} '
        'tile1=${tiles.evaluate().isEmpty ? '-' : t.getRect(tiles.first)}');
    await shot('fix1_episodes_panel', settle: 1500);
    expect(tiles.evaluate().length, greaterThan(0));
    Navigator.of(t.element(panel)).pop();
    await wait(800);
    GoRouter.of(t.element(find.byType(PlayerProgress).first)).pop();
    await wait(1000);
    // Home with Yoruba subtitles on (same global setting): measure a live cue.
    final cue = find.descendant(
        of: find.byKey(const ValueKey('feed-subtitle')), matching: find.byKey(const ValueKey('player-subtitle-text')));
    for (var i = 0; i < 120 && cue.evaluate().isEmpty; i++) {
      await wait(250);
    }
    rects('home', 'feed-subtitle', 'feed-info');
    await shot('fix1_home_subtitle', settle: 300);
    log('done');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
