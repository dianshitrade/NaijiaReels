import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:naija_reels/app/env.dart';
import 'package:naija_reels/core/player/player_pool.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/features/player/subtitle_controls.dart';
import 'package:naija_reels/main.dart' show kAppLocale;

/// Live multi-language subtitles against the deployed API: guest login →
/// /episodes/{id}/play → HLS + subtitles[]. Screenshots: subs_off, subs_picker,
/// subs_en / yo / fr / zh. Logs whether HLS tracks or the VTT fallback were used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live subtitles: off, picker, en/yo/fr/zh', (t) async {
    MediaKit.ensureInitialized();
    final dio = Dio(BaseOptions(baseUrl: Env.apiRoot, connectTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90)));
    late PlayInfo info;
    await t.runAsync(() async {
      final g = await dio.post<Map<String, dynamic>>('/auth/guest', data: {'deviceId': 'and-subs-shots-01'});
      final tok = (g.data!['data'] as Map)['accessToken'] as String;
      final d = await dio.get<Map<String, dynamic>>('/dramas/dr_mama');
      final ep = (((d.data!['data'] as Map)['episodes'] as List).first as Map)['id'] as String;
      final p = await dio.get<Map<String, dynamic>>('/episodes/$ep/play',
          options: Options(headers: {'Authorization': 'Bearer $tok'}));
      info = PlayInfo.fromJson(p.data!['data'] as Map<String, dynamic>);
    });
    debugPrint('SUBS: play hls=${info.hlsUrl} subtitles=${info.subtitles.map((s) => '${s.lang}/${s.label}').toList()}');
    final pool = PlayerPool()..subtitlesFor[info.hlsUrl] = info.subtitles;
    pool.focus(info.hlsUrl).catchError((Object e) { debugPrint('SUBS: focus err $e'); return pool.get(info.hlsUrl)!; });
    final p = pool.get(info.hlsUrl)!;
    final settings = SubtitleSettings(systemLocale: () => const Locale('en', 'NG'));
    late BuildContext sheetCtx;
    await t.pumpWidget(MaterialApp(
      locale: kAppLocale,
      supportedLocales: const [kAppLocale],
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(listenable: settings, builder: (ctx, _) {
          sheetCtx = ctx;
          return Stack(fit: StackFit.expand, children: [
            Center(child: AspectRatio(aspectRatio: 9 / 16, child: Video(
                controller: p.controller, fit: BoxFit.cover, controls: NoVideoControls,
                subtitleViewConfiguration: playerSubtitleConfig(0)))),
            PlayerChrome(title: 'Mama-in-Law Wahala', episodeNo: 1, episodeTitle: 'Live subtitles',
                total: 6, index: 0,
                subtitleButton: Row(mainAxisSize: MainAxisSize.min, children: [
                  SubtitleMenuArrow(onPick: () => showSubtitlePicker(ctx, settings)),
                  SubtitleButton(settings: settings, onTap: settings.toggle,
                      onPick: () => showSubtitlePicker(ctx, settings)),
                ])),
            PlayerSubtitleOverlay(player: p.player, enabled: settings.enabled),
          ]);
        }),
      ),
    ));
    await binding.convertFlutterSurfaceToImage();
    Future<void> wait(int s) async {
      for (var i = 0; i < s; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    for (var i = 0; i < 90 && !p.ready.value; i++) {
      await wait(1);
    }
    debugPrint('SUBS: ready=${p.ready.value} tracks=${p.player.state.tracks.subtitle.map((e) => '${e.id}/${e.language}/${e.title}').toList()}');
    await wait(3);
    debugPrint('SUBS: off text="${p.player.state.subtitle.join(' ')}" current=${p.player.state.track.subtitle.id}');
    expect(find.byKey(const ValueKey('player-subtitle-text')), findsNothing);
    await binding.takeScreenshot('subs_off');

    var anyText = false;
    for (final lang in ['en', 'yo', 'fr', 'zh-Hans']) {
      await t.runAsync(() => settings.choose(lang));
      await t.runAsync(() => pool.setSubtitleLang(settings.activeLang));
      String txt = '';
      for (var i = 0; i < 25 && txt.isEmpty; i++) {
        await wait(1);
        txt = p.player.state.subtitle.join(' ').trim();
        if (txt.isEmpty && p.player.state.position > const Duration(seconds: 20)) {
          await t.runAsync(() => p.player.seek(const Duration(seconds: 1)));
        }
      }
      anyText |= txt.isNotEmpty;
      debugPrint('SUBS: lang=$lang applied=${p.appliedSubtitle} current=${p.player.state.track.subtitle.id}/'
          '${p.player.state.track.subtitle.language} uri=${p.player.state.track.subtitle.uri} text="$txt"');
      await binding.takeScreenshot(lang == 'zh-Hans' ? 'subs_zh' : 'subs_$lang');
    }

    showSubtitlePicker(sheetCtx, settings);
    await wait(2);
    await binding.takeScreenshot('subs_picker');
    expect(find.text('Yorùbá'), findsOneWidget);
    expect(anyText, isTrue);
    await t.runAsync(() => pool.disposeAll().timeout(const Duration(seconds: 20)));
  }, timeout: const Timeout(Duration(minutes: 8)));
}
