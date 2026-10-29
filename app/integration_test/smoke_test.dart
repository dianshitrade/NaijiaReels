import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:naija_reels/core/network/api_client.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/main.dart' as app;

/// Main-flow smoke against the deployed API (default Env base or --dart-define).
/// Screenshots are taken from the host with `adb exec-out screencap` while
/// this runs; progress is logged with the `SMOKE:` prefix.
Future<void> pumpUntil(WidgetTester t, Finder f, {int seconds = 150}) async {
  for (var i = 0; i < seconds; i++) {
    await t.pump(const Duration(seconds: 1));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timeout waiting for $f');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guest -> home -> free play -> locked 403 -> coin unlock -> wallet 70', (t) async {
    await app.main();
    await binding.convertFlutterSurfaceToImage();
    await t.pump(const Duration(seconds: 4));
    await binding.takeScreenshot('01_splash');
    await pumpUntil(t, find.text('Theater'));
    await t.tap(find.text('Theater').last); // catalog lives on the Theater tab
    await pumpUntil(t, find.text('Trending'));
    debugPrint('SMOKE: home loaded (guest login ok)');
    await t.pump(const Duration(seconds: 5)); // let covers load for screenshot
    await binding.takeScreenshot('02_home');
    debugPrint('SMOKE: SCREEN home');

    final repo = Repository(ApiClient(buildDio()));
    final w0 = await repo.wallet();
    debugPrint('SMOKE: wallet start=${w0.balanceCoins}');
    final home = await repo.home();
    final drama = await repo.drama(home.sections.first.items.first.id);
    final free = drama.episodes.firstWhere((e) => e.free);
    final locked = drama.episodes.firstWhere((e) => e.locked);

    final play = await repo.play(free.id);
    final m3u8 = await Dio().get<String>(play.hlsUrl);
    debugPrint('SMOKE: free ${free.id} hls ${m3u8.statusCode} ${play.hlsUrl}');
    expect(m3u8.statusCode, 200);
    expect(m3u8.data, contains('#EXTM3U'));

    try {
      await repo.play(locked.id);
      fail('locked episode played');
    } on ApiException catch (e) {
      debugPrint('SMOKE: locked ${locked.id} -> ${e.status}/${e.code}');
      expect(e.isLocked, isTrue);
    }

    final u = await repo.unlockWithCoins(locked.id);
    final w1 = await repo.wallet();
    debugPrint('SMOKE: unlocked ${u.episodeId} balance=${u.balanceCoins} wallet=${w1.balanceCoins}');
    expect(w1.balanceCoins, 70);

    // UI: open the drama detail for a screenshot.
    await t.tap(find.text(drama.title).first);
    await t.pump(const Duration(seconds: 10));
    await binding.takeScreenshot('03_drama_detail_after_unlock');
    debugPrint('SMOKE: SCREEN detail');
    debugPrint('SMOKE: PASS');
  });
}
