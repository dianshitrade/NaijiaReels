import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/core/storage/local_storage.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/features/me/me_page.dart';

class _NoRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

EpisodeItem _ep(int no, {int season = 1}) => EpisodeItem(
    id: 'e$no', episodeNo: no, title: 'EP$no', free: true, locked: false, priceCoins: 0, seasonNumber: season);

Drama _drama({String status = 'ongoing', int? total}) => Drama(
      id: 'dr_x',
      title: 'Lagos Love',
      coverUrl: '',
      tags: const [],
      episodeCount: 3,
      totalEpisodes: total,
      status: status,
      episodes: [_ep(1), _ep(2), _ep(3)],
    );

void main() {
  setUp(LocalStorage.clearMemHistory);

  test('epProgress uses plannedEpisodes only', () {
    expect(epProgress(2, _drama()), 'EP 2/3');
    expect(epProgress(2, _drama(total: 40)), 'EP 2/40');
  });

  test('POST /history then GET /me/history filters by status', () async {
    final api = MockApi(_NoRepo());
    await api.postHistory(_drama(status: 'completed'), _ep(3));
    final all = await api.meHistory();
    expect(all.single.lastEpisodeNo, 3);
    expect(all.single.totalEpisodes, 3);
    expect(all.single.lastSeasonNumber, 1);
    expect(all.single.finished, isTrue);
    expect(await api.meHistory(status: 'in_progress'), isEmpty);
    await api.postHistory(_drama(status: 'completed'), _ep(1)); // one row per drama
    expect((await api.meHistory(status: 'in_progress')).single.lastEpisodeNo, 1);
  });

  test('PATCH /me validates nickname; likes feed /me/liked and likesCount', () async {
    final api = MockApi(_NoRepo());
    expect((await api.me()).likesCount, 58);
    await expectLater(api.updateMe(nickname: 'A'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 40001)));
    expect((await api.updateMe(nickname: 'Ada')).nickname, 'Ada');
    await api.setLiked('e2', true, drama: _drama(), episode: _ep(2));
    expect((await api.me()).likesCount, 59);
    expect((await api.meLiked()).single.episodeNo, 2);
    await api.setLiked('e2', false);
    expect(await api.meLiked(), isEmpty);
  });

  testWidgets('Me page shows profile, counters and history grid', (t) async {
    final api = MockApi(_NoRepo());
    await api.postHistory(_drama(), _ep(2));
    await t.pumpWidget(ProviderScope(
      overrides: [mockApiProvider.overrideWithValue(api)],
      child: MaterialApp(theme: ThemeData.dark(), home: const MePage()),
    ));
    await t.pumpAndSettle();
    expect(find.text('Chioma O.'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('me-inbox')), findsOneWidget);
    expect(find.text('EP 2/3'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('me-history-finished')));
    await t.pumpAndSettle();
    expect(find.text('EP 2/3'), findsNothing);
  });
}
