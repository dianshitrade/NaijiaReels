import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/shared/widgets/cover_image.dart';
import 'package:naija_reels/shared/widgets/episode_cover.dart';

// 2x2 PNG.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGM8YWT0n4GBgYGJAQoAIX4CL4ShB5UAAAAASUVORK5CYII=');

ImageProvider Function(String) _provider(Set<String> ok) =>
    (url) => MemoryImage(ok.contains(url) ? _png : Uint8List.fromList([1, 2, 3]));

void main() {
  group('EpisodeItem.fromJson', () {
    test('with coverUrl', () {
      final e = EpisodeItem.fromJson({
        'id': 'dr_mama_ep1', 'episodeNo': 1, 'title': 'Episode 1', 'free': true,
        'locked': false, 'priceCoins': 0,
        'coverUrl': 'https://naijareels-media.onrender.com/mama-in-law-wahala/ep1/cover.jpg',
      });
      expect(e.coverUrl, 'https://naijareels-media.onrender.com/mama-in-law-wahala/ep1/cover.jpg');
    });
    test('without coverUrl (missing / null / empty)', () {
      final base = {'id': 'x', 'episodeNo': 3, 'locked': true, 'priceCoins': 30};
      expect(EpisodeItem.fromJson(base).coverUrl, isNull);
      expect(EpisodeItem.fromJson({...base, 'coverUrl': null}).coverUrl, isNull);
      expect(EpisodeItem.fromJson({...base, 'coverUrl': ''}).coverUrl, isNull);
      expect(EpisodeItem.fromJson(base).episodeNo, 3);
    });
  });

  group('coverCandidates order', () {
    test('episode first, then drama, skipping empty', () {
      expect(coverCandidates(episodeCoverUrl: 'e', dramaCoverUrl: 'd'), ['e', 'd']);
      expect(coverCandidates(episodeCoverUrl: null, dramaCoverUrl: 'd'), ['d']);
      expect(coverCandidates(episodeCoverUrl: ' ', dramaCoverUrl: ''), isEmpty);
    });
  });

  group('EpisodeCover fallback chain', () {
    Future<void> pump(WidgetTester t, Set<String> ok, {String? ep = 'e', String? dr = 'd'}) async {
      await t.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 90, height: 160,
          child: EpisodeCover(
            episodeCoverUrl: ep, dramaCoverUrl: dr, title: 'T', imageProviderOverride: _provider(ok)),
        ),
      ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      await t.pump();
    }

    testWidgets('episode cover shown when it loads', (t) async {
      await pump(t, {'e', 'd'});
      expect(find.byKey(const ValueKey('cover-0')), findsOneWidget);
      expect(find.byType(CoverFallback), findsNothing);
    });
    testWidgets('episode fails -> drama cover', (t) async {
      await pump(t, {'d'});
      expect(find.byKey(const ValueKey('cover-1')), findsOneWidget);
      expect(find.byType(CoverFallback), findsNothing);
    });
    testWidgets('both fail -> CoverFallback', (t) async {
      await pump(t, {});
      expect(find.byType(CoverFallback), findsOneWidget);
    });
    testWidgets('no urls -> CoverFallback', (t) async {
      await pump(t, {}, ep: null, dr: '');
      expect(find.byType(CoverFallback), findsOneWidget);
    });
  });
}
