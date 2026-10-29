// Central mock layer for the five-tab contract (naija-backend
// contracts/openapi.yaml, branch feat/T13-five-tabs-contract @ 449cef1).
// None of these endpoints exist on the backend yet. Field names and sample
// values are copied from the contract. Flip [kUseMocks] off once they ship;
// every mocked call lives in this file only.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_response.dart';

import '../models.dart';
import '../repository.dart';

/// Master switch for the whole mock layer.
const bool kUseMocks = true;

/// Contract error: reward already claimed (treat as claimed, not an error).
const int kErrAlreadyClaimed = 40903;

/// Per-drama contract fields missing from the live API (Drama + DramaDetail).
class _DramaExtras {
  const _DramaExtras(this.heatCount, this.watchingCount, this.badge, this.status, this.saveCount,
      [this.topComment]);
  final int saveCount;
  final int heatCount;
  final int watchingCount;
  final String? badge;
  final String status;
  final TopComment? topComment;
}

/// Contract examples for known ids; others derive stable values from the id.
const Map<String, _DramaExtras> _extras = {
  'dr_mama': _DramaExtras(1284000, 3120, 'hot', 'ongoing', 43860,
      TopComment(text: 'Mama Bisi no go kill me with laugh 😂', likeCount: 4210, userName: 'Tunde_Ib')),
  'dr_prince': _DramaExtras(856000, 1450, 'new', 'completed', 29240),
  'dr_lagos': _DramaExtras(402000, 610, null, 'ongoing', 36550),
};

/// Contract chart examples: rankChange per id (null = new entry).
const Map<String, int?> _rankChange = {'dr_mama': 2, 'dr_prince': null, 'dr_lagos': -1};

const _comments = [
  'Wetin you dey watch? This one sweet die!',
  'I no fit wait for the next episode o',
  'The plot twist for episode 2 shock me',
];

/// Contract per-episode counters (FeedEpisode / play examples).
const Map<String, (int, int)> _epCounts = {'dr_mama_ep1': (2310, 148), 'dr_prince_ep5': (980, 37)};

int _hash(String id) => id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);

/// Fills Episode.seasonNumber/likeCount/commentCount (contract 449cef1).
EpisodeItem enrichEpisode(EpisodeItem e) {
  final c = _epCounts[e.id];
  final h = _hash(e.id);
  return EpisodeItem(
    id: e.id,
    episodeNo: e.episodeNo,
    title: e.title,
    free: e.free,
    locked: e.locked,
    priceCoins: e.priceCoins,
    durationSec: e.durationSec,
    coverUrl: e.coverUrl,
    seasonNumber: e.seasonNumber,
    likeCount: e.likeCount ?? c?.$1 ?? 100 + h % 3000,
    commentCount: e.commentCount ?? c?.$2 ?? 10 + h % 200,
  );
}

/// Contract-required status/currentSeason come from the mock for known ids
/// (live API does not send them yet); no completion is inferred client-side.
Drama enrichDrama(Drama d) {
  final e = _extras[d.id];
  final eps = [for (final x in d.episodes) enrichEpisode(x)];
  if (e != null) {
    return d.copyWith(
        heatCount: d.heatCount ?? e.heatCount,
        watchingCount: d.watchingCount ?? e.watchingCount,
        badge: d.badge ?? e.badge,
        status: e.status,
        saveCount: d.saveCount ?? e.saveCount,
        commentCount: d.commentCount ?? (d.id == 'dr_mama' ? 1874 : null),
        // Never invent episode counts: real totalEpisodes, else real episodeCount.
        totalEpisodes: d.totalEpisodes ?? d.episodeCount,
        topComment: d.topComment ?? e.topComment,
        episodes: eps);
  }
  final h = _hash(d.id);
  return d.copyWith(
    heatCount: d.heatCount ?? 120000 + h % 900000,
    watchingCount: d.watchingCount ?? 300 + h % 4000,
    badge: d.badge ?? (h % 3 == 0 ? 'hot' : (h % 3 == 1 ? 'new' : null)),
    saveCount: d.saveCount ?? 5000 + h % 40000,
    totalEpisodes: d.totalEpisodes ?? d.episodeCount,
    topComment:
        d.topComment ?? TopComment(text: _comments[h % _comments.length], likeCount: 200 + h % 3000, userName: null),
    episodes: eps,
  );
}

/// Contract comment errors.
const int kErrCommentInvalid = 42203;
const int kErrTooManyRequests = 42901;

/// English message for a failed comment POST (42203 reason / 42901).
String commentErrorMessage(ApiException e) {
  if (e.code == kErrTooManyRequests) return 'You are commenting too fast. Please wait a moment.';
  if (e.code == kErrCommentInvalid) {
    final r = e.data is Map ? (e.data as Map)['reason'] : null;
    return switch (r) {
      'empty' => 'Comment cannot be empty.',
      'too_long' => 'Comment is too long (max 500 characters).',
      _ => 'This comment contains words that are not allowed.',
    };
  }
  return 'Could not post comment. Try again.';
}

/// Mock implementations of contract endpoints. Builds on real data where it
/// exists (/dramas, /dramas/{id}, /episodes/{id}/play).
class MockApi {
  MockApi(this._repo);
  final Repository _repo;

  // Optimistic, idempotent local state (contract: repeat calls return 200).
  final Set<String> _liked = {};
  final Set<String> _saved = {'dr_mama'};
  final Set<String> _reminders = {};
  final Set<String> _claimed = {};

  /// GET /api/v1/feed?tag=for_you|following|nollywood|comedy|romance
  Future<List<FeedItem>> feed({String tag = 'for_you'}) async {
    if (tag == 'following') return const []; // guests get an empty list
    var dramas = await _repo.dramas();
    if (tag == 'comedy' || tag == 'romance') {
      final f = dramas.where((d) => d.tags.any((t) => t.toLowerCase() == tag)).toList();
      if (f.isNotEmpty) dramas = f;
    }
    final items = await Future.wait(dramas.take(10).map(_feedItem));
    return items.whereType<FeedItem>().toList();
  }

  Future<FeedItem?> _feedItem(Drama summary) async {
    try {
      final d = enrichDrama(await _repo.drama(summary.id));
      if (d.episodes.isEmpty) return null;
      final ep = d.episodes.firstWhere((e) => !e.locked, orElse: () => d.episodes.first);
      PlayInfo? play;
      if (!ep.locked) play = await _repo.play(ep.id); // real signed url
      return FeedItem(
        drama: d,
        episode: FeedEpisode(
          id: ep.id,
          episodeNo: ep.episodeNo,
          durationSec: ep.durationSec,
          locked: ep.locked,
          seasonNumber: play?.seasonNumber ?? ep.seasonNumber,
          likeCount: ep.likeCount ?? 0,
          commentCount: ep.commentCount ?? 0,
          free: ep.free,
          priceCoins: ep.priceCoins,
          coverUrl: ep.coverUrl ?? d.coverUrl,
          hlsUrl: play?.hlsUrl,
          hlsUrlExpiresAt: play?.expiresAt,
          subtitles: play?.subtitles ?? const [],
        ),
        liked: _liked.contains(ep.id),
        saved: _saved.contains(d.id),
      );
    } catch (_) {
      return null;
    }
  }

  /// GET /api/v1/dramas?tag&sort=new|hot&genre&status (contract fields mocked on real /dramas).
  Future<List<Drama>> dramas({String sort = 'hot', String? genre, String? status}) async {
    final real = await _repo.dramas();
    var list = [for (final d in real) enrichDrama(d)];
    if (genre != null) list = list.where((d) => d.tags.any((t) => t.toLowerCase() == genre)).toList();
    if (status != null) list = list.where((d) => d.status == status).toList();
    if (sort == 'hot') {
      list.sort((a, b) => (b.heatCount ?? 0).compareTo(a.heatCount ?? 0));
    } else {
      list = list.reversed.toList(); // no release date yet: newest = last in catalog
    }
    return list;
  }

  /// GET /api/v1/charts?type=hot|trending|new|completed (max 50).
  Future<List<ChartItem>> charts({String type = 'hot'}) async {
    var list = await dramas(sort: type == 'new' ? 'new' : 'hot', status: type == 'completed' ? 'completed' : null);
    if (type == 'trending') {
      list = [...list]..sort((a, b) => (b.watchingCount ?? 0).compareTo(a.watchingCount ?? 0));
    }
    return [
      for (var i = 0; i < list.length && i < 50; i++)
        ChartItem(
          drama: list[i],
          rank: i + 1,
          rankChange: _rankChange.containsKey(list[i].id) ? _rankChange[list[i].id] : (list[i].id.hashCode % 5) - 2,
        ),
    ];
  }

  final Map<String, int> _reminderCount = {};

  /// GET /api/v1/dramas/coming-soon (ordered by releaseAt asc).
  Future<List<ComingSoonDrama>> comingSoon() async {
    ComingSoonDrama cs(String id, String title, List<String> tags, String desc, int total, String at, bool set, int n) {
      final on = _reminders.contains(id) || (set && !_reminderOff.contains(id));
      return ComingSoonDrama(
        drama: Drama(
            id: id,
            title: title,
            coverUrl: '',
            tags: tags,
            episodeCount: 0,
            description: desc,
            heatCount: 0,
            watchingCount: 0,
            badge: 'new',
            status: 'ongoing',
            totalEpisodes: total),
        releaseAt: DateTime.parse(at),
        reminderSet: on,
        reminderCount: _reminderCount[id] ?? n,
      );
    }

    return [
      // Contract example (cover not uploaded yet → branded fallback cover).
      cs('dr_owambe', 'Owambe Queens', ['comedy', 'romance'], 'Aso-ebi rivalry at the biggest party in Surulere.', 45,
          '2026-11-14T18:00:00Z', true, 8120),
      // Placeholder titles (mock only).
      cs('dr_danfo', 'Danfo Driver Diaries', ['comedy', 'nollywood'], 'One bus, one driver, a hundred Lagos stories.',
          30, '2026-11-21T18:00:00Z', false, 2310),
      cs('dr_aso', 'Aso Rock Secrets', ['drama', 'thriller'], 'An intern stumbles on a secret that could shake Abuja.',
          50, '2026-12-05T18:00:00Z', false, 1540),
    ];
  }

  final Set<String> _reminderOff = {};

  final Map<String, List<Comment>> _commentsByEp = {};
  final List<DateTime> _postTimes = [];
  static const _blocked = ['scam', 'http://', 'https://', 'www.'];

  List<Comment> _seed(String epId) => _commentsByEp.putIfAbsent(epId, () {
        final h = _hash(epId);
        return [
          // Contract examples.
          Comment(
              id: 'cm_7Hq2_$epId',
              user: const CommentUser(
                  id: 'u_tunde',
                  nickname: 'Tunde_Ib',
                  avatarUrl: 'https://naijareels-media.onrender.com/avatars/u_tunde.jpg'),
              text: 'Mama Bisi no go kill me with laugh 😂',
              likeCount: 4210,
              liked: true,
              createdAt: DateTime.parse('2026-10-29T19:12:00Z')),
          Comment(
              id: 'cm_8Kd9_$epId',
              user: const CommentUser(id: 'u_amaka', nickname: 'Amaka from Enugu'),
              text: 'Wetin Ngozi do her sef? Episode 3 abeg!',
              likeCount: 312,
              liked: false,
              createdAt: DateTime.parse('2026-10-29T21:40:00Z')),
          for (var i = 0; i < 6; i++)
            Comment(
                id: 'cm_m${i}_$epId',
                user: CommentUser(id: 'u_m$i', nickname: const ['Chidi', 'Bisola', 'Musa', 'Efe', 'Ngozi', 'Kunle'][i]),
                text: _comments[(h + i) % _comments.length],
                likeCount: (h >> i) % 200,
                liked: false,
                createdAt: DateTime.parse('2026-10-28T12:00:00Z').add(Duration(hours: i * 3))),
        ];
      });

  /// GET /api/v1/episodes/{id}/comments?sort=hot|new&page&size
  Future<({List<Comment> items, int page, int size, bool hasMore})> comments(String episodeId,
      {String sort = 'hot', int page = 1, int size = 20}) async {
    final all = [..._seed(episodeId)];
    if (sort == 'new') {
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      all.sort((a, b) {
        final c = b.likeCount.compareTo(a.likeCount);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
    }
    final from = ((page - 1) * size).clamp(0, all.length);
    final to = (from + size).clamp(0, all.length);
    return (items: all.sublist(from, to), page: page, size: size, hasMore: to < all.length);
  }

  /// POST /api/v1/episodes/{id}/comments {text}: 1–500 chars after trim; 42203 / 42901.
  Future<Comment> postComment(String episodeId, String text, {DateTime? now}) async {
    final t = text.trim();
    ApiException invalid(String reason) =>
        ApiException(kErrCommentInvalid, 'Comment text invalid', status: 422, data: {'reason': reason});
    if (t.isEmpty) throw invalid('empty');
    if (t.length > 500) throw invalid('too_long');
    final lower = t.toLowerCase();
    if (_blocked.any(lower.contains)) throw invalid('blocked_word');
    final at = now ?? DateTime.now();
    _postTimes.removeWhere((x) => at.difference(x) > const Duration(minutes: 1));
    if (_postTimes.length >= 5) throw ApiException(kErrTooManyRequests, 'Too many requests', status: 429);
    _postTimes.add(at);
    final c = Comment(
        id: 'cm_local_${at.microsecondsSinceEpoch}',
        user: const CommentUser(id: 'u_me', nickname: 'You'),
        text: t,
        likeCount: 0,
        liked: false,
        createdAt: at.toUtc());
    _seed(episodeId).insert(0, c);
    return c;
  }

  /// POST|DELETE /api/v1/comments/{id}/like → CommentLike {commentId, liked, likeCount}.
  Future<({String commentId, bool liked, int likeCount})> setCommentLiked(String commentId, bool on) async {
    for (final list in _commentsByEp.values) {
      final i = list.indexWhere((c) => c.id == commentId);
      if (i < 0) continue;
      final c = list[i];
      if (c.liked != on) list[i] = c.copyWith(liked: on, likeCount: (c.likeCount + (on ? 1 : -1)).clamp(0, 1 << 30));
      return (commentId: commentId, liked: on, likeCount: list[i].likeCount);
    }
    throw ApiException(40401, 'Not found', status: 404);
  }

  /// POST|DELETE /api/v1/episodes/{id}/like
  Future<void> setLiked(String episodeId, bool liked) async => liked ? _liked.add(episodeId) : _liked.remove(episodeId);

  /// POST|DELETE /api/v1/library (save drama)
  Future<void> setSaved(String dramaId, bool saved) async => saved ? _saved.add(dramaId) : _saved.remove(dramaId);

  /// POST|DELETE /api/v1/dramas/{id}/reminder
  /// Idempotent; returns the contract body `{dramaId, reminderSet, releaseAt}`.
  Future<Map<String, Object?>> setReminder(String dramaId, bool on, {int? countBefore, DateTime? releaseAt}) async {
    final was = _reminders.contains(dramaId) || (dramaId == 'dr_owambe' && !_reminderOff.contains(dramaId));
    if (on) {
      _reminders.add(dramaId);
      _reminderOff.remove(dramaId);
    } else {
      _reminders.remove(dramaId);
      _reminderOff.add(dramaId);
    }
    if (countBefore != null && was != on) _reminderCount[dramaId] = countBefore + (on ? 1 : -1);
    return {'dramaId': dramaId, 'reminderSet': on, 'releaseAt': releaseAt?.toUtc().toIso8601String()};
  }

  /// POST /api/v1/rewards/{taskId}/claim → returns false on 40903 (already claimed).
  Future<bool> claim(String taskId) async => _claimed.add(taskId);

  /// GET /api/v1/shop/packages (skeleton; contract field names).
  List<Map<String, Object?>> shopPackages() => const [
        {
          'id': 'pkg_coins_100',
          'title': '100 Coins',
          'coins': 100,
          'bonusCoins': 0,
          'amountKobo': 50000,
          'vipDays': 0,
          'playProductId': 'coins_100'
        },
        {
          'id': 'pkg_vip_7',
          'title': 'VIP 7 days',
          'coins': 0,
          'bonusCoins': 0,
          'amountKobo': 150000,
          'vipDays': 7,
          'playProductId': 'vip_7d'
        },
      ];

  /// GET /api/v1/rewards/summary (skeleton; contract field names).
  Map<String, Object?> rewardsSummary() => const {
        'balanceCoins': 120,
        'cashKobo': 25000,
        'newbie7Day': [],
        'checkin7Day': [],
        'bingeStreak': null,
        'dramaCompletion': [],
        'chests': [],
      };
}

/// GET /dramas (mocked contract fields), keyed "sort|genre|status".
final theaterDramasProvider = FutureProvider.autoDispose.family<List<Drama>, String>((ref, key) {
  final p = key.split('|');
  return ref
      .watch(mockApiProvider)
      .dramas(sort: p[0], genre: p[1].isEmpty ? null : p[1], status: p[2].isEmpty ? null : p[2]);
});

/// GET /charts?type=…
final chartsProvider = FutureProvider.autoDispose
    .family<List<ChartItem>, String>((ref, type) => ref.watch(mockApiProvider).charts(type: type));

/// GET /dramas/coming-soon
final comingSoonProvider =
    FutureProvider.autoDispose<List<ComingSoonDrama>>((ref) => ref.watch(mockApiProvider).comingSoon());

final mockApiProvider = Provider<MockApi>((ref) => MockApi(ref.watch(repositoryProvider)));

/// GET /feed?tag=… (mocked).
final feedProvider =
    FutureProvider.autoDispose.family<List<FeedItem>, String>((ref, tag) => ref.watch(mockApiProvider).feed(tag: tag));

/// 1.2M / 3.1K style.
String compactCount(int n) {
  String f(double v, String s) => '${v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.0', '')}$s';
  if (n >= 1000000) return f(n / 1000000, 'M');
  if (n >= 1000) return f(n / 1000, 'K');
  return '$n';
}
