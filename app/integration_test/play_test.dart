import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:naija_reels/main.dart' as app;

/// Playback smoke: real EpisodeFeedPage for Mama ep1 against the deployed API.
/// Passes only when the cover poster is gone (first frame) and no error shows.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Mama ep1 plays in EpisodeFeedPage (poster gone, no error)', (t) async {
    await app.main();
    await binding.convertFlutterSurfaceToImage();
    for (var i = 0; i < 150 && find.text('Trending').evaluate().isEmpty; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Trending'), findsWidgets);
    debugPrint('PLAY: home ok, opening /drama/dr_mama/play?ep=0');
    GoRouter.of(t.element(find.text('Trending').first)).push('/drama/dr_mama/play?ep=0');
    final poster = find.byKey(const ValueKey('first-frame-poster'));
    final err = find.byKey(const ValueKey('player-error'));
    var ok = false;
    for (var i = 0; i < 90; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await t.pump(const Duration(milliseconds: 100));
      final video = find.byType(Video).evaluate().isNotEmpty;
      if (i % 5 == 0) {
        debugPrint('PLAY: t=${i}s video=$video poster=${poster.evaluate().isNotEmpty} '
            'error=${err.evaluate().isNotEmpty} spinner=${find.byType(CircularProgressIndicator).evaluate().isNotEmpty}');
      }
      if (i == 20) await binding.takeScreenshot('play_t20');
      if (err.evaluate().isNotEmpty) break;
      if (video && poster.evaluate().isEmpty) {
        ok = true;
        debugPrint('PLAY: first frame at ~${i}s');
        break;
      }
    }
    if (err.evaluate().isNotEmpty) {
      final texts = find.descendant(of: err, matching: find.byType(Text)).evaluate()
          .map((e) => (e.widget as Text).data).toList();
      debugPrint('PLAY: ERROR shown: $texts');
    }
    // Let it run a few seconds so subtitles / progress move for the screenshot.
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await binding.takeScreenshot('player_playing');
    debugPrint('PLAY: RESULT ok=$ok');
    expect(ok, isTrue, reason: 'poster never cleared / error shown');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
