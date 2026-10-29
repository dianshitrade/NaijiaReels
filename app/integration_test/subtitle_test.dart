import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:naija_reels/core/player/player_pool.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';

const url = 'https://naijareels-media.onrender.com/mama-in-law-wahala/ep1/master.m3u8';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('HLS subtitle track auto-selected and rendered', (t) async {
    MediaKit.ensureInitialized();
    final pool = PlayerPool();
    // Don't await open before frames exist: on Android media_kit's open waits on
    // the video texture, which needs real frames. Start it, pump in real time.
    debugPrint('SUBS: opening $url');
    var opened = false;
    pool.focus(url).then((_) { opened = true; debugPrint('SUBS: opened'); },
        onError: (Object e) => debugPrint('SUBS: open error $e'));
    final p = pool.get(url)!;
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (ctx, c) {
          final boxH = (c.maxWidth * 16 / 9).clamp(0.0, c.maxHeight);
          return Stack(fit: StackFit.expand, children: [
            Center(child: AspectRatio(aspectRatio: 9 / 16, child: Video(
              controller: p.controller, fit: BoxFit.cover, controls: NoVideoControls,
              subtitleViewConfiguration: playerSubtitleConfig((c.maxHeight - boxH) / 2)))),
            const PlayerChrome(title: 'Mama-in-Law Wahala', episodeNo: 1,
                episodeTitle: 'Subtitle smoke', total: 2, index: 0),
            PlayerSubtitleOverlay(player: p.player),
          ]);
        }),
      ),
    ));
    await binding.convertFlutterSurfaceToImage();
    String sub = '';
    for (var i = 0; i < 120 && sub.isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await t.pump(const Duration(milliseconds: 100));
      sub = p.player.state.subtitle.join(' ').trim();
      if (i % 5 == 0) {
        debugPrint('SUBS: t=$i opened=$opened tracks.subtitle=${p.player.state.tracks.subtitle.map((e) => '${e.id}/${e.language}').toList()} '
            'current=${p.player.state.track.subtitle.id}/${p.player.state.track.subtitle.language} '
            'pos=${p.player.state.position} text="$sub"');
      }
    }
    debugPrint('SUBS: current=${p.player.state.track.subtitle.id} text="$sub"');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 100));
    await binding.takeScreenshot('player_subtitles');
    final txt = find.byKey(const ValueKey('player-subtitle-text'));
    if (txt.evaluate().isNotEmpty) {
      final w = t.widget<Text>(txt.first);
      debugPrint('SUBS: screen=${t.view.physicalSize / t.view.devicePixelRatio} '
          'fontSize=${w.style?.fontSize} effectiveFontSize=${(w.textScaler ?? TextScaler.noScaling).scale(w.style?.fontSize ?? 0)} '
          'rect=${t.getRect(txt.first)}');
    } else {
      debugPrint('SUBS: subtitle Text not found');
    }
    expect(sub, isNotEmpty);
    expect(txt, findsWidgets);
    await t.runAsync(() => pool.disposeAll().timeout(const Duration(seconds: 20)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
