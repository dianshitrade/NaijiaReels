import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/app/env.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/shared/widgets/brand_logo.dart';

void main() {
  test('env default + resolve relative media path', () {
    expect(Env.apiRoot, endsWith('/api/v1'));
    expect(Env.resolve('/media/a/cover.jpg'), '${Env.apiBaseUrl}/media/a/cover.jpg');
    expect(Env.resolve('https://x/y.jpg'), 'https://x/y.jpg');
  });

  test('ApiResponse parses envelope', () {
    final r = ApiResponse<int>.fromJson({'code': 0, 'message': 'ok', 'data': 5}, (d) => d as int);
    expect(r.isSuccess, isTrue);
    expect(r.data, 5);
  });

  test('error code helpers', () {
    expect(ApiException(40301, 'locked', status: 403).isLocked, isTrue);
    expect(ApiException(40201, 'no coins', status: 402).isInsufficientCoins, isTrue);
  });

  test('drama detail parsing', () {
    final d = Drama.fromJson({
      'id': 'd1', 'title': 'T', 'coverUrl': '/media/x/cover.jpg', 'tags': ['a'],
      'episodeCount': 1,
      'episodes': [
        {'id': 'e1', 'episodeNo': 1, 'title': 'E1', 'free': false, 'locked': true, 'priceCoins': 30}
      ],
    });
    expect(d.episodes.single.locked, isTrue);
    expect(d.episodes.single.priceCoins, 30);
  });

  testWidgets('BrandLogo renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLogo()));
    expect(find.byType(RichText), findsWidgets);
  });
}
