import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/core/network/api_client.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/shared/widgets/comments_sheet.dart';
import 'package:naija_reels/shared/widgets/episode_cover.dart';

MockApi _api() => MockApi(Repository(ApiClient(Dio())));

void main() {
  test('Drama: status/currentSeason/saveCount/commentCount, no inferred completion', () {
    final d = Drama.fromJson({
      'id': 'x',
      'title': 'X',
      'episodeCount': 2,
      'status': 'ongoing',
      'currentSeason': 2,
      'saveCount': 43860,
      'commentCount': 1874,
      'episodes': [
        {'id': 'a', 'episodeNo': 1, 'seasonNumber': 1},
        {'id': 'b', 'episodeNo': 1, 'seasonNumber': 2},
      ],
    });
    // All listed episodes released, but status says ongoing: no client inference.
    expect(d.completed, isFalse);
    expect(d.currentSeason, 2);
    expect(d.saveCount, 43860);
    expect(d.commentCount, 1874);
    expect(d.seasons, [1, 2]);
  });

  test('PlayInfo + EpisodeItem carry seasonNumber/likeCount/commentCount', () {
    final p = PlayInfo.fromJson(
        {'seasonNumber': 1, 'likeCount': 2310, 'commentCount': 148, 'hlsUrl': 'u', 'expiresAt': null});
    expect((p.seasonNumber, p.likeCount, p.commentCount), (1, 2310, 148));
    final e = enrichEpisode(
        const EpisodeItem(id: 'dr_mama_ep1', episodeNo: 1, title: 'E1', free: true, locked: false, priceCoins: 0));
    expect((e.likeCount, e.commentCount, e.seasonNumber), (2310, 148, 1));
    final m = enrichDrama(const Drama(id: 'dr_prince', title: 'P', coverUrl: '', tags: [], episodeCount: 1));
    expect(m.status, 'completed');
    expect(m.saveCount, 29240);
  });

  test('Comment parses contract example', () {
    final c = Comment.fromJson({
      'id': 'cm_7Hq2',
      'user': {'id': 'u_tunde', 'nickname': 'Tunde_Ib', 'avatarUrl': null},
      'text': 'hi',
      'likeCount': 4210,
      'liked': true,
      'createdAt': '2026-10-29T19:12:00Z',
      'replyCount': 0,
    });
    expect(c.user.nickname, 'Tunde_Ib');
    expect(c.liked, isTrue);
    expect(c.createdAt.isUtc, isTrue);
  });

  test('mock comments: hot/new sort, post validation 42203, rate limit 42901, like', () async {
    final api = _api();
    final hot = await api.comments('ep1');
    expect(hot.items.first.likeCount, 4210);
    final nw = await api.comments('ep1', sort: 'new');
    expect(nw.items.first.createdAt.isAfter(nw.items.last.createdAt), isTrue);

    Future<String?> reason(String t) async {
      try {
        await api.postComment('ep1', t);
        return null;
      } on ApiException catch (e) {
        expect(e.code, kErrCommentInvalid);
        return (e.data as Map)['reason'] as String;
      }
    }

    expect(await reason('   '), 'empty');
    expect(await reason('x' * 501), 'too_long');
    expect(await reason('visit https://spam'), 'blocked_word');
    final t0 = DateTime.utc(2026, 10, 30, 6);
    for (var i = 0; i < 5; i++) {
      await api.postComment('ep1', 'ok $i', now: t0.add(Duration(seconds: i)));
    }
    await expectLater(api.postComment('ep1', 'six', now: t0.add(const Duration(seconds: 10))),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', kErrTooManyRequests)));
    expect(commentErrorMessage(ApiException(42901, 'x')), contains('too fast'));
    expect(commentErrorMessage(ApiException(42203, 'x', data: {'reason': 'too_long'})), contains('500'));

    final r = await api.setCommentLiked('cm_8Kd9_ep1', true);
    expect((r.liked, r.likeCount), (true, 313)); // contract example
    final again = await api.setCommentLiked('cm_8Kd9_ep1', true); // idempotent
    expect(again.likeCount, 313);
  });

  testWidgets('comments sheet: Hot/New toggle, post, error message', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [mockApiProvider.overrideWithValue(_api())],
      child: const MaterialApp(home: Scaffold(body: CommentsSheet(episodeId: 'ep9', commentCount: 148))),
    ));
    await t.pumpAndSettle();
    expect(find.text('148 comments'), findsOneWidget);
    expect(find.text('Mama Bisi no go kill me with laugh 😂'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('comments-sort-new')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('comment-send')));
    await t.pumpAndSettle();
    expect(find.text('Comment cannot be empty.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('comment-input')), 'Na wa o');
    await t.tap(find.byKey(const ValueKey('comment-send')));
    await t.pumpAndSettle();
    expect(find.text('Na wa o'), findsOneWidget);
    expect(find.text('149 comments'), findsOneWidget);
  });

  testWidgets('episode picker groups by season', (t) async {
    EpisodeItem ep(String id, int no, int s) =>
        EpisodeItem(id: id, episodeNo: no, title: '', free: true, locked: false, priceCoins: 0, seasonNumber: s);
    int? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SeasonedEpisodeGrid(
            episodes: [ep('a', 1, 1), ep('b', 2, 1), ep('c', 1, 2)],
            dramaCoverUrl: '',
            dramaTitle: 'T',
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    ));
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('episodes-grid-s2')), matching: find.byKey(const ValueKey('ep-tile-1'))));
    expect(tapped, 2);
  });
}
