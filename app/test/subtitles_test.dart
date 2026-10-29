import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:naija_reels/app/router.dart';
import 'package:naija_reels/core/player/subtitle_select.dart';
import 'package:naija_reels/core/storage/local_storage.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/features/player/subtitle_controls.dart';
import 'package:naija_reels/main.dart';

const _hls = [
  SubtitleTrack('auto', null, null),
  SubtitleTrack('no', null, null),
  SubtitleTrack('1', 'English', 'en'),
  SubtitleTrack('2', 'Naija Pidgin', 'pcm'),
  SubtitleTrack('3', 'Yorùbá', 'yo'),
  SubtitleTrack('4', 'Igbo', 'ig'),
  SubtitleTrack('5', 'Hausa', 'ha'),
  SubtitleTrack('6', 'Français', 'fr'),
  SubtitleTrack('7', 'Chinese', 'zh-Hans'),
];

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_subs');
    Hive.init(dir.path);
    LocalStorage.useBox(await Hive.openBox<dynamic>('t${DateTime.now().microsecondsSinceEpoch}',
        bytes: Uint8List(0)));
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('locale → subtitle language mapping', () {
    expect(subtitleLangForLocale(const Locale('en', 'NG')), 'en');
    expect(subtitleLangForLocale(const Locale('yo')), 'yo');
    expect(subtitleLangForLocale(const Locale('ig')), 'ig');
    expect(subtitleLangForLocale(const Locale('ha')), 'ha');
    expect(subtitleLangForLocale(const Locale('fr', 'FR')), 'fr');
    expect(subtitleLangForLocale(const Locale('pcm')), 'pcm');
    for (final l in const [Locale('zh'), Locale('zh', 'CN'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')]) {
      expect(subtitleLangForLocale(l), 'zh-Hans');
    }
    expect(subtitleLangForLocale(const Locale('de')), 'en');
    expect(subtitleLangForLocale(const Locale('ja')), 'en');
  });

  test('HLS track picked per language', () {
    expect(pickSubtitleTrackForLang(_hls, 'yo')?.id, '3');
    expect(pickSubtitleTrackForLang(_hls, 'zh-Hans')?.id, '7');
    expect(pickSubtitleTrackForLang([const SubtitleTrack('9', null, 'zh-hans')], 'zh-Hans')?.id, '9');
    expect(pickSubtitleTrackForLang([const SubtitleTrack('8', 'English', 'eng')], 'en')?.id, '8');
    expect(pickSubtitleTrackForLang(const [SubtitleTrack('auto', null, null)], 'en'), isNull);
  });

  test('subtitles default OFF', () {
    final s = SubtitleSettings(systemLocale: () => const Locale('yo'));
    expect(s.enabled, isFalse);
    expect(s.activeLang, isNull);
  });

  test('system yo → yo; unsupported → en; toggle off → no subtitles', () async {
    final yo = SubtitleSettings(systemLocale: () => const Locale('yo', 'NG'));
    await yo.toggle();
    expect(yo.activeLang, 'yo');
    await yo.toggle();
    expect(yo.activeLang, isNull);
    final de = SubtitleSettings(systemLocale: () => const Locale('de', 'DE'));
    await de.toggle();
    expect(de.activeLang, 'en');
  });

  test('Hive remembers on/off and manual language', () async {
    final a = SubtitleSettings(systemLocale: () => const Locale('en'));
    await a.choose('ha');
    final b = SubtitleSettings(systemLocale: () => const Locale('en'));
    expect(b.enabled, isTrue);
    expect(b.activeLang, 'ha');
    await b.toggle();
    final c = SubtitleSettings(systemLocale: () => const Locale('en'));
    expect(c.activeLang, isNull);
    expect(c.preferredLang, 'ha');
  });

  test('PlayInfo parses subtitles; old API without it still works', () {
    final p = PlayInfo.fromJson({
      'hlsUrl': 'https://x/master.m3u8',
      'subtitles': [
        {'lang': 'yo', 'label': 'Yorùbá', 'url': 'https://x/yo.vtt'},
        {'lang': '', 'url': ''},
      ],
    });
    expect(p.subtitles.single.lang, 'yo');
    expect(PlayInfo.fromJson({'hlsUrl': 'u'}).subtitles, isEmpty);
    expect(PlayInfo.fromJson({'hlsUrl': 'u', 'subtitles': null}).subtitles, isEmpty);
  });

  testWidgets('system zh → zh-Hans subtitles, app UI stays English', (t) async {
    final s = SubtitleSettings(systemLocale: () => const Locale('zh', 'CN'));
    await t.runAsync(s.toggle);
    expect(s.activeLang, 'zh-Hans');
    t.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    t.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(t.platformDispatcher.clearAllTestValues);
    late BuildContext ctx;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, _) {
        ctx = c;
        return const Scaffold(body: Text('home'));
      }),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [routerProvider.overrideWithValue(router)],
      child: const NaijaReelsApp(),
    ));
    await t.pumpAndSettle();
    expect(Localizations.localeOf(ctx), const Locale('en'));
    expect(MaterialLocalizations.of(ctx).okButtonLabel, 'OK');
  });

  testWidgets('CC button toggles; picker lists English/endonym labels', (t) async {
    final s = SubtitleSettings(systemLocale: () => const Locale('yo'));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => Center(
            child: SubtitleButton(
              settings: s,
              onTap: s.toggle,
              onPick: () => showSubtitlePicker(ctx, s),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('CC off'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('player-subs')));
    await t.pump();
    expect(find.text('YO'), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('player-subs')));
    await t.pumpAndSettle();
    for (final l in ['Off', 'English', 'Naija Pidgin', 'Yorùbá', 'Igbo', 'Hausa', 'Français', 'Chinese']) {
      expect(find.text(l), findsOneWidget);
    }
    await t.ensureVisible(find.byKey(const ValueKey('subs-opt-zh-Hans')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('subs-opt-zh-Hans')));
    await t.pumpAndSettle();
    expect(s.activeLang, 'zh-Hans');
    expect(LocalStorage.subtitleLang, 'zh-Hans');
    expect(find.text('ZH'), findsOneWidget);
  });
}
