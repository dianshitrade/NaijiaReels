// Widget-level UI screenshots (not a device capture). Renders key screens with
// mock data at 360x780dp @2x and, when UI_SHOTS_DIR is set, writes PNGs there.
// Network images cannot load in flutter test, so covers show the branded
// fallback (this doubles as the "cover failed" state).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/app/theme.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/features/home/discover_page.dart';
import 'package:naija_reels/features/home/home_page.dart';
import 'package:naija_reels/features/player/episode_feed_page.dart';
import 'package:naija_reels/features/splash/splash_page.dart';
import 'package:naija_reels/shared/widgets/brand_logo.dart';
import 'package:naija_reels/shared/widgets/cover_image.dart';
import 'package:naija_reels/shared/widgets/episode_cover.dart';

// Real backend titles only (GET /dramas), cycled for layout.
const _titles = [
  'Mama-in-Law Wahala', 'The Village Prince', 'Lagos Hustle', 'Mama-in-Law Wahala', 'The Village Prince',
  'Lagos Hustle', 'Mama-in-Law Wahala', 'The Village Prince', 'Lagos Hustle', 'Mama-in-Law Wahala',
];
const _tags = ['Romance', 'Revenge', 'Royal', 'Royal', 'CEO', 'Romance', 'Family', 'Family', 'Romance', 'Village'];

Drama _d(int i) => Drama(
    id: 'd$i', title: _titles[i], coverUrl: '', tags: [_tags[i]], episodeCount: 20 + i * 3);

final _home = HomeData(banners: const [], sections: [
  HomeSection('Trending', [for (var i = 0; i < 4; i++) _d(i)]),
  HomeSection('New Releases', [for (var i = 4; i < 10; i++) _d(i)]),
]);

final _overrides = [
  homeProvider.overrideWith((_) async => _home),
  walletProvider.overrideWith((_) async => const Wallet(balanceCoins: 245, bonusCoins: 30)),
  dramaListProvider.overrideWith((_) async => [for (var i = 0; i < 9; i++) _d(i)]),
];

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await l.load();
  }
  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _key = GlobalKey();

Future<void> _shot(WidgetTester t, Widget child, String name,
    {Size size = const Size(360, 780), double textScale = 1}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: _overrides,
    child: RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)), child: w!),
        home: child,
      ),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  // let real-async image decodes (and decode errors) finish
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(t.takeException(), isNull);
  final out = Platform.environment['UI_SHOTS_DIR'];
  if (out == null) return;
  await t.runAsync(() async {
    final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(out).createSync(recursive: true);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

// Synthetic 9:16 "episode cover" images (network is unavailable in flutter test).
final _covers = <String, Uint8List>{};
Future<Uint8List> _makeCover(int i) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const w = 270.0, h = 480.0;
  final hues = [10.0, 200.0, 45.0, 280.0, 150.0, 330.0];
  final col = HSLColor.fromAHSL(1, hues[i % hues.length], 0.6, 0.45).toColor();
  c.drawRect(const Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), [col, const Color(0xFF101010)]));
  c.drawCircle(const Offset(w / 2, h * 0.38), 70, Paint()..color = const Color(0x55FFFFFF));
  final tp = TextPainter(
      text: TextSpan(text: 'EP${i + 1}\nCOVER', style: const TextStyle(fontSize: 44, color: Colors.white, fontWeight: FontWeight.w900)),
      textAlign: TextAlign.center, textDirection: TextDirection.ltr)..layout(maxWidth: w);
  tp.paint(c, Offset((w - tp.width) / 2, h * 0.38 - tp.height / 2));
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

ImageProvider _coverProvider(String url) =>
    MemoryImage(_covers[url] ?? Uint8List.fromList([0])); // unknown url -> decode error

final _mamaEps = [
  for (var i = 0; i < 6; i++)
    EpisodeItem(
        id: 'dr_mama_ep${i + 1}', episodeNo: i + 1, title: 'Episode ${i + 1}', free: i < 2,
        locked: i >= 2, priceCoins: i >= 2 ? 30 : 0,
        coverUrl: i < 2 ? 'ep${i + 1}' : null),
];

Widget _picker(String title, List<EpisodeItem> eps, String dramaCover) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: EpisodeGrid(
          episodes: eps, dramaCoverUrl: dramaCover, dramaTitle: 'Mama-in-Law Wahala',
          currentIndex: 0, onTap: (_) {}, imageProviderOverride: _coverProvider),
      ),
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
    for (var i = 0; i < 2; i++) {
      _covers['ep${i + 1}'] = await _makeCover(i);
    }
    _covers['drama'] = await _makeCover(4);
  });
  testWidgets('episode covers (ep1-2 cover, ep3-6 drama cover)', (t) async {
    await _shot(t, _picker('Episodes · covers', _mamaEps, 'drama'), 'episode_covers');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
  });
  testWidgets('episode cover fallback (all covers fail)', (t) async {
    await _shot(t, _picker('Episodes · fallback', [
      for (final e in _mamaEps)
        EpisodeItem(id: e.id, episodeNo: e.episodeNo, title: e.title, free: e.free,
            locked: e.locked, priceCoins: e.priceCoins, coverUrl: e.coverUrl == null ? null : 'broken')
    ], 'broken-drama'), 'episode_cover_fallback');
    expect(find.byType(CoverFallback), findsNWidgets(6));
  });

  testWidgets('01 splash', (t) => _shot(t, const SplashPage(autoBoot: false), '01_splash'));
  testWidgets('01b splash 320dp text x2 stays one line', (t) async {
    await _shot(t, const SplashPage(autoBoot: false), '01b_splash_320dp_textx2',
        size: const Size(320, 640), textScale: 2);
    final p = t.renderObject<RenderParagraph>(find.textContaining('NaijaReels', findRichText: true).first);
    expect(p.didExceedMaxLines, isFalse);
    expect(p.getMaxIntrinsicHeight(double.infinity), lessThan(60));
  });
  testWidgets('02 discover', (t) => _shot(t, const HomePage(initialTab: 1), '02_discover'));
  testWidgets('03 player', (t) => _shot(
      t,
      const Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          CoverFallback(title: 'Lagos Revenge', showTitle: false),
          PlayerChrome(
              title: 'Lagos Revenge', episodeNo: 3, episodeTitle: 'Dem push am commot for company',
              total: 20, index: 2),
        ]),
      ),
      '03_player'));
  testWidgets('04 rewards', (t) => _shot(t, const HomePage(initialTab: 3), '04_rewards'));
  testWidgets('05 inbox', (t) => _shot(t, const HomePage(initialTab: 4), '05_inbox'));
  testWidgets('06 profile', (t) => _shot(t, const HomePage(initialTab: 4), '06_profile'));
  testWidgets('07 cover failed', (t) => _shot(
      t,
      Scaffold(
        appBar: AppBar(title: const Text('Cover load failed')),
        body: GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 9 / 16,
          children: [
            for (var i = 0; i < 4; i++)
              if (i.isEven) DramaCard(_d(i)) else CoverImage('', title: _titles[i], radius: 14),
          ],
        ),
      ),
      '07_cover_failed'));
  testWidgets('brand logo 320dp', (t) async {
    await _shot(t, const Scaffold(body: Center(child: SizedBox(width: 120, child: BrandLogo(fontSize: 40)))), '99_logo_narrow');
    expect(find.byType(BrandLogo), findsOneWidget);
  });
}
