import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/features/shell/tab_placeholders.dart';
import 'package:naija_reels/shared/widgets/ankara_pattern.dart';

void main() {
  test('mock enriches Drama with contract fields', () {
    const d = Drama(id: 'dr_mama', title: 'Mama', coverUrl: '', tags: ['comedy'], episodeCount: 2);
    final e = enrichDrama(d);
    expect(e.heatCount, 1284000);
    expect(e.watchingCount, 3120);
    expect(e.badge, 'hot');
    expect(e.status, 'ongoing');
    expect(e.completed, isFalse);
    expect(e.totalEpisodes, 2);
    expect(e.plannedEpisodes, 2);
    expect(e.episodeCount, 2);
    expect(e.topComment?.userName, 'Tunde_Ib');
    expect(kUseMocks, isTrue);
  });

  test('Drama parses contract fields', () {
    final d = Drama.fromJson({
      'id': 'x',
      'title': 'X',
      'episodeCount': 2,
      'status': 'completed',
      'totalEpisodes': 2,
      'badge': null,
      'heatCount': 5,
      'topComment': {'text': 'hi', 'likeCount': 3, 'userName': null},
    });
    expect(d.completed, isTrue);
    expect(d.badge, isNull);
    expect(d.topComment!.text, 'hi');
  });

  test('compactCount', () {
    expect(compactCount(1284000), '1.3M');
    expect(compactCount(3120), '3.1K');
    expect(compactCount(980), '980');
  });

  testWidgets('following feed mock is empty; claim is idempotent', (t) async {
    final api = MockApi(_NoRepo());
    expect(await api.feed(tag: 'following'), isEmpty);
    expect(await api.claim('t1'), isTrue);
    expect(await api.claim('t1'), isFalse); // 40903 → already claimed
  });

  testWidgets('Me placeholder opens Inbox from the envelope', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Stack(children: [TextilePattern(style: TextileStyle.adire), MePlaceholder()])));
    await t.tap(find.byKey(const ValueKey('me-inbox')));
    await t.pumpAndSettle();
    expect(find.text('Inbox'), findsWidgets);
  });
}

class _NoRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
