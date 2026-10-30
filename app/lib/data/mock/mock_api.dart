// Central mock layer for the five-tab contract (naija-backend
// contracts/openapi.yaml, branch feat/T13-five-tabs-contract @ 449cef1).
// None of these endpoints exist on the backend yet. Field names and sample
// values are copied from the contract. Flip [kUseMocks] off once they ship;
// every mocked call lives in this file only.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_response.dart';
import '../../core/storage/local_storage.dart';

import '../models.dart';
import '../repository.dart';

/// Master switch for the whole mock layer.
const bool kUseMocks = true;

/// Contract error: reward already claimed (treat as claimed, not an error).
const int kErrAlreadyClaimed = 40903;

/// Per-drama contract fields missing from the live API (Drama + DramaDetail).
class _DramaExtras {
  const _DramaExtras(this.heatCount, this.watchingCount, this.badge, this.status, this.saveCount, [this.topComment]);
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
    ComingSoonDrama cs(String id, String title, List<String> tags, String desc, String at, bool set, int n) {
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
            // Unreleased mock titles: no invented episode totals.
            totalEpisodes: null),
        releaseAt: DateTime.parse(at),
        reminderSet: on,
        reminderCount: _reminderCount[id] ?? n,
      );
    }

    return [
      // Contract example (cover not uploaded yet → branded fallback cover).
      cs('dr_owambe', 'Owambe Queens', ['comedy', 'romance'], 'Aso-ebi rivalry at the biggest party in Surulere.',
          '2026-11-14T18:00:00Z', true, 8120),
      // Placeholder titles (mock only).
      cs('dr_danfo', 'Danfo Driver Diaries', ['comedy', 'nollywood'], 'One bus, one driver, a hundred Lagos stories.',
          '2026-11-21T18:00:00Z', false, 2310),
      cs('dr_aso', 'Aso Rock Secrets', ['drama', 'thriller'], 'An intern stumbles on a secret that could shake Abuja.',
          '2026-12-05T18:00:00Z', false, 1540),
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
  /// [drama]/[episode] let GET /me/liked render the row (mock only).
  Future<void> setLiked(String episodeId, bool liked, {Drama? drama, EpisodeItem? episode}) async {
    if (liked) {
      _liked.add(episodeId);
      if (drama != null && episode != null) {
        _likedInfo[episodeId] = (drama, episode, DateTime.now().toUtc());
      }
    } else {
      _liked.remove(episodeId);
      _likedInfo.remove(episodeId);
    }
  }

  final Map<String, (Drama, EpisodeItem, DateTime)> _likedInfo = {};
  final Map<String, DateTime> _savedAt = {'dr_mama': DateTime.utc(2026, 10, 28, 19)};
  String _nickname = 'Chioma O.';

  /// POST|DELETE /api/v1/library (save drama)
  Future<void> setSaved(String dramaId, bool saved) async {
    if (saved) {
      _saved.add(dramaId);
      _savedAt.putIfAbsent(dramaId, () => DateTime.now().toUtc());
    } else {
      _saved.remove(dramaId);
      _savedAt.remove(dramaId);
    }
  }

  /// GET /api/v1/me (contract example values; likesCount = session likes on top of the example).
  Future<MeProfile> me() async => MeProfile(
        id: 'u_8f2k1',
        nickname: _nickname,
        avatarUrl: null, // contract example URL is not hosted yet -> initials avatar
        guest: false,
        followingCount: 12,
        followersCount: 3,
        likesCount: 58 + _liked.length,
        balanceCoins: _balanceCoins,
        vipUntil: null,
      );

  /// PATCH /api/v1/me {nickname}: 2-24 chars, else 40001 (contract).
  Future<MeProfile> updateMe({required String nickname}) async {
    final n = nickname.trim();
    if (n.length < 2 || n.length > 24) throw ApiException(40001, 'Validation failed', status: 400);
    _nickname = n;
    return me();
  }

  /// POST /api/v1/history {episodeId, positionSec}. Mock: persisted locally in
  /// Hive (one row per drama) so GET /me/history can be served offline.
  Future<void> postHistory(Drama d, EpisodeItem ep, {int positionSec = 0}) async {
    final released = d.episodes.isEmpty ? d.episodeCount : d.episodes.length;
    final idx = d.episodes.indexWhere((e) => e.id == ep.id);
    await LocalStorage.putWatchHistory(d.id, {
      'dramaId': d.id,
      'title': d.title,
      'coverUrl': d.coverUrl,
      'tags': d.tags,
      'episodeCount': d.episodeCount,
      'totalEpisodes': d.totalEpisodes,
      'status': d.status,
      'lastEpisodeId': ep.id,
      'lastEpisodeNo': ep.episodeNo,
      'lastIndex': idx < 0 ? 0 : idx,
      'lastSeasonNumber': ep.seasonNumber,
      'progressSec': positionSec,
      // Reached the last released episode (no end-of-video signal yet).
      'finished': idx >= 0 && idx == released - 1 && d.completed,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// GET /api/v1/me/history?status=all|finished|in_progress (newest first).
  Future<List<MeHistoryItem>> meHistory({String status = 'all'}) async {
    final rows = LocalStorage.watchHistory.values.map((r) {
      final d = Drama(
        id: r['dramaId'] as String,
        title: r['title'] as String? ?? '',
        coverUrl: r['coverUrl'] as String? ?? '',
        tags: [for (final t in (r['tags'] as List? ?? const [])) '$t'],
        episodeCount: (r['episodeCount'] as num?)?.toInt() ?? 0,
        totalEpisodes: (r['totalEpisodes'] as num?)?.toInt(),
        status: r['status'] as String? ?? 'ongoing',
      );
      return MeHistoryItem(
        drama: d,
        lastEpisodeId: r['lastEpisodeId'] as String,
        lastEpisodeNo: (r['lastEpisodeNo'] as num).toInt(),
        totalEpisodes: d.plannedEpisodes,
        progressSec: (r['progressSec'] as num?)?.toInt() ?? 0,
        finished: r['finished'] as bool? ?? false,
        updatedAt: DateTime.parse(r['updatedAt'] as String),
        lastSeasonNumber: (r['lastSeasonNumber'] as num?)?.toInt() ?? 1,
      );
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return switch (status) {
      'finished' => rows.where((h) => h.finished).toList(),
      'in_progress' => rows.where((h) => !h.finished).toList(),
      _ => rows,
    };
  }

  /// GET /api/v1/me/saved (real dramas from /dramas, saved ids from the mock).
  Future<List<SavedDrama>> meSaved() async {
    if (_saved.isEmpty) return const [];
    final hist = {for (final h in await meHistory()) h.drama.id: h.lastEpisodeNo};
    final all = await _repo.dramas();
    return [
      for (final d in all)
        if (_saved.contains(d.id))
          SavedDrama(
              drama: enrichDrama(d),
              savedAt: _savedAt[d.id] ?? DateTime.now().toUtc(),
              lastEpisodeNo: hist[d.id]),
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  /// GET /api/v1/me/liked (episodes liked this session, newest first).
  Future<List<LikedEpisode>> meLiked() async => [
        for (final e in _likedInfo.entries)
          LikedEpisode(
              drama: e.value.$1,
              episodeId: e.key,
              episodeNo: e.value.$2.episodeNo,
              coverUrl: e.value.$2.coverUrl,
              seasonNumber: e.value.$2.seasonNumber,
              likedAt: e.value.$3),
      ]..sort((a, b) => b.likedAt.compareTo(a.likedAt));

  /// GET /api/v1/me/reminders (coming-soon dramas with reminderSet).
  Future<List<ComingSoonDrama>> meReminders() async =>
      (await comingSoon()).where((c) => c.reminderSet).toList();

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

  /// Legacy helper: true on first claim, false on 40903 (already claimed).
  Future<bool> claim(String taskId) async {
    if (_claimed.contains(taskId)) return false;
    _claimed.add(taskId);
    return true;
  }

  /// Placeholder prices: every mock package ends in 99 kobo-naira so nobody
  /// mistakes them for real pricing (backend has not set prices yet).
  static const bool kMockPricesArePlaceholders = true;

  /// GET /api/v1/shop/packages. Shape copied from the contract example;
  /// amounts are PLACEHOLDERS (₦x,x99) until the backend publishes prices.
  /// tag=first_recharge only while the user has no paid order (contract).
  Future<List<ShopPackage>> shopPackages() async {
    final now = DateTime.now().toUtc();
    final items = <Map<String, Object?>>[
      if (!_hasPaidOrder)
        {
          'id': 'pk_coins_first',
          'type': 'coins',
          'title': 'First Recharge Special',
          'coins': 300,
          'bonusCoins': 300,
          'amountKobo': 49900,
          'originalAmountKobo': 99900,
          'tag': 'first_recharge',
          // contract: null = no countdown; mock gives a 24h window to show the timer
          'endsAt': now.add(const Duration(hours: 23, minutes: 59)).toIso8601String(),
          'vipDays': null,
          'playProductId': 'coins_300_first',
        },
      {
        'id': 'pk_vip_week',
        'type': 'vip',
        'title': 'VIP Weekly',
        'coins': 0,
        'bonusCoins': 0,
        'amountKobo': 119900,
        'originalAmountKobo': 199900,
        'tag': 'limited',
        'endsAt': now.add(const Duration(hours: 5, minutes: 30)).toIso8601String(),
        'vipDays': 7,
        'playProductId': 'vip_week',
      },
      for (final (id, c, b, k) in const [
        ('pk_coins_500', 500, 50, 79900),
        ('pk_coins_1000', 1000, 150, 149900),
        ('pk_coins_2500', 2500, 500, 349900),
        ('pk_coins_5000', 5000, 1250, 699900),
      ])
        {
          'id': id,
          'type': 'coins',
          'title': '${c == 1000 ? '1,000' : c == 2500 ? '2,500' : c == 5000 ? '5,000' : '$c'} Coins',
          'coins': c,
          'bonusCoins': b,
          'amountKobo': k,
          'originalAmountKobo': null,
          'tag': null,
          'endsAt': null,
          'vipDays': null,
          'playProductId': 'coins_$c',
        },
      for (final (id, t, d, k) in const [
        ('pk_vip_month', 'VIP Monthly', 30, 349900),
        ('pk_vip_year', 'VIP Yearly', 365, 2999900),
      ])
        {
          'id': id,
          'type': 'vip',
          'title': t,
          'coins': 0,
          'bonusCoins': 0,
          'amountKobo': k,
          'originalAmountKobo': null,
          'tag': null,
          'endsAt': null,
          'vipDays': d,
          'playProductId': id.substring(3),
        },
    ];
    return [for (final j in items) ShopPackage.fromJson(j)];
  }

  bool _hasPaidOrder = false;
  final Map<String, ShopOrder> _orders = {};
  final Map<String, int> _polls = {};
  int _orderSeq = 0;

  /// Number of GET /orders/{id} polls before a mock order turns `paid`.
  int pollsUntilPaid = 2;

  /// GET /api/v1/coupons?status=available|used|expired (contract example + one used).
  Future<List<Coupon>> coupons({String status = 'available'}) async {
    final all = [
      Coupon.fromJson(const {
        'id': 'cp_n200_off',
        'title': '₦200 off your next top-up',
        'type': 'amount_off',
        'amountOffKobo': 20000,
        'bonusCoins': null,
        'minAmountKobo': 100000,
        'packageIds': <String>[],
        'status': 'available',
        'expiresAt': '2026-11-15T22:59:59Z',
      }),
      Coupon.fromJson(const {
        'id': 'cp_bonus_100',
        'title': '+100 bonus coins',
        'type': 'bonus_coins',
        'amountOffKobo': null,
        'bonusCoins': 100,
        'minAmountKobo': 0,
        'packageIds': <String>[],
        'status': 'used',
        'expiresAt': '2026-11-30T22:59:59Z',
      }),
    ];
    return all.where((c) => c.status == status && !_usedCoupons.contains(c.id)).toList();
  }

  final Set<String> _usedCoupons = {};

  /// POST /api/v1/orders {productId, channel, couponId?}. 42202 when the
  /// coupon does not apply, 40401 for unknown product.
  Future<ShopOrder> createOrder(String productId, {String channel = 'paystack', String? couponId}) async {
    final pkgs = await shopPackages();
    final p = pkgs.where((x) => x.id == productId).firstOrNull;
    if (p == null) throw ApiException(40401, 'Not found', status: 404);
    var discount = 0;
    if (couponId != null && channel == 'paystack') {
      final c = (await coupons()).where((x) => x.id == couponId).firstOrNull;
      if (c == null || !c.appliesTo(p)) throw ApiException(42202, 'Coupon not applicable', status: 422);
      discount = c.amountOffKobo ?? 0;
    }
    final o = ShopOrder(
      id: 'ord_${++_orderSeq}',
      productId: p.id,
      channel: channel,
      status: 'pending',
      amountKobo: p.amountKobo - discount,
      coins: p.coins + p.bonusCoins,
      createdAt: DateTime.now().toUtc(),
      paystackAuthorizationUrl: channel == 'paystack' ? 'https://checkout.paystack.com/abc' : null,
      couponId: channel == 'paystack' ? couponId : null,
      discountKobo: discount,
    );
    _orders[o.id] = o;
    _polls[o.id] = 0;
    return o;
  }

  /// GET /api/v1/orders/{id}. Mock: pending for [pollsUntilPaid] polls, then paid.
  Future<ShopOrder> getOrder(String id) async {
    final o = _orders[id];
    if (o == null) throw ApiException(40401, 'Not found', status: 404);
    if (o.isFinal) return o;
    final n = (_polls[id] ?? 0) + 1;
    _polls[id] = n;
    if (n < pollsUntilPaid) return o;
    final paid = o.withStatus('paid');
    _orders[id] = paid;
    _hasPaidOrder = true;
    if (paid.couponId != null) _usedCoupons.add(paid.couponId!);
    return paid;
  }

  /// GET /api/v1/orders (mock: this session's orders, newest first).
  Future<List<ShopOrder>> orders() async => _orders.values.toList().reversed.toList();

  /// Create then poll GET /orders/{id} until final or [maxPolls].
  Future<ShopOrder> buyAndPoll(String productId,
      {String? couponId, Duration interval = const Duration(seconds: 1), int maxPolls = 30}) async {
    var o = await createOrder(productId, couponId: couponId);
    for (var i = 0; i < maxPolls && !o.isFinal; i++) {
      await Future<void>.delayed(interval);
      o = await getOrder(o.id);
    }
    return o;
  }

  int _balanceCoins = 245; // contract example
  final Map<String, int> _claimable = {};

  /// Watch-based progress the mock can bump (tests / demos).
  int bingeProgress = 6;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// GET /api/v1/rewards/summary. Shape and values copied from the contract
  /// example; dates are today's so checkin/binge taskIds stay valid. Claimed
  /// taskIds (this session) flip to `claimed`.
  Future<RewardsSummary> rewardsSummary({DateTime? now}) async {
    final t = (now ?? DateTime.now()).toUtc();
    final today = _day(t);
    _claimable.clear();
    String st(String? id, String s) {
      if (id != null && _claimed.contains(id)) return 'claimed';
      return s;
    }

    Map<String, Object?> day(int d, int c, String s, [String? id]) {
      final status = st(id, s);
      if (status == 'claimable' && id != null) _claimable[id] = c;
      return {'day': d, 'rewardCoins': c, 'status': status, 'taskId': status == 'claimable' ? id : null};
    }

    Map<String, Object?> task(String id, String title, int c, int p, int target, String? dramaId) {
      final s = st(id, p >= target ? 'claimable' : 'in_progress');
      if (s == 'claimable') _claimable[id] = c;
      return {
        'taskId': id,
        'title': title,
        'rewardCoins': c,
        'progress': p > target ? target : p,
        'target': target,
        'status': s,
        'dramaId': dramaId
      };
    }

    final checkinId = 'checkin:$today';
    final checked = _claimed.contains(checkinId);
    final unlock1 = t.add(const Duration(hours: 1, minutes: 45));
    final chest1 = st('chest:ch_1', t.isBefore(unlock1) ? 'unlocking' : 'claimable');
    final j = <String, Object?>{
      'balanceCoins': _balanceCoins,
      'cashKobo': 0, // contract: display-only, always 0 in MVP
      'newbie7Day': {
        'days': [
          day(1, 50, 'claimed'),
          day(2, 30, 'claimed'),
          day(3, 30, 'claimable', 'newbie:3'),
          day(4, 40, 'locked'),
          day(5, 40, 'locked'),
          day(6, 50, 'locked'),
          day(7, 100, 'locked'),
        ]
      },
      'checkin7Day': {
        'streak': checked ? 4 : 3,
        'todayChecked': checked,
        'days': [
          day(1, 10, 'claimed'),
          day(2, 10, 'claimed'),
          day(3, 15, 'claimed'),
          day(4, 15, 'claimable', checkinId),
          day(5, 20, 'locked'),
          day(6, 20, 'locked'),
          day(7, 50, 'locked'),
        ]
      },
      'bingeStreak': task('binge:$today', 'Watch 10 episodes today', 30, bingeProgress, 10, null),
      'dramaCompletion': [
        task('complete:dr_prince', "Finish The Prince's Secret Bride", 100, 40, 40, 'dr_prince'),
      ],
      'chests': [
        {
          'id': 'ch_1',
          'taskId': 'chest:ch_1',
          'status': chest1,
          'unlockAt': unlock1.toIso8601String(),
          'progress': null,
          'target': null,
          'rewardCoinsMin': 5,
          'rewardCoinsMax': 50,
        },
        {
          'id': 'ch_2',
          'taskId': 'chest:ch_2',
          'status': st('chest:ch_2', 'locked'),
          'unlockAt': null,
          'progress': 12,
          'target': 30,
          'rewardCoinsMin': 10,
          'rewardCoinsMax': 100,
        },
      ],
    };
    if (chest1 == 'claimable') _claimable['chest:ch_1'] = 25;
    return RewardsSummary.fromJson(j);
  }

  /// POST /api/v1/rewards/{taskId}/claim → `{taskId, rewardCoins, balanceCoins}`.
  /// Second call (or not claimable) throws 40903; unknown format 40401.
  Future<Map<String, Object?>> claimReward(String taskId) async {
    if (!RegExp(r'^(checkin|newbie|binge|complete|chest):.+$').hasMatch(taskId)) {
      throw ApiException(40401, 'Not found', status: 404);
    }
    if (_claimed.contains(taskId) || !_claimable.containsKey(taskId)) {
      throw ApiException(kErrAlreadyClaimed, 'Task not claimable', status: 409);
    }
    final c = _claimable.remove(taskId)!;
    _claimed.add(taskId);
    _balanceCoins += c;
    return {'taskId': taskId, 'rewardCoins': c, 'balanceCoins': _balanceCoins};
  }
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

/// GET /me
final meProvider = FutureProvider.autoDispose<MeProfile>((ref) => ref.watch(mockApiProvider).me());

/// GET /me/history?status=
final meHistoryProvider = FutureProvider.autoDispose
    .family<List<MeHistoryItem>, String>((ref, status) => ref.watch(mockApiProvider).meHistory(status: status));

/// GET /me/saved
final meSavedProvider = FutureProvider.autoDispose<List<SavedDrama>>((ref) => ref.watch(mockApiProvider).meSaved());

/// GET /me/liked
final meLikedProvider = FutureProvider.autoDispose<List<LikedEpisode>>((ref) => ref.watch(mockApiProvider).meLiked());

/// GET /me/reminders
final meRemindersProvider =
    FutureProvider.autoDispose<List<ComingSoonDrama>>((ref) => ref.watch(mockApiProvider).meReminders());

/// GET /rewards/summary
final rewardsSummaryProvider =
    FutureProvider.autoDispose<RewardsSummary>((ref) => ref.watch(mockApiProvider).rewardsSummary());

/// GET /shop/packages
final shopPackagesProvider =
    FutureProvider.autoDispose<List<ShopPackage>>((ref) => ref.watch(mockApiProvider).shopPackages());

/// GET /coupons?status=available
final couponsProvider = FutureProvider.autoDispose<List<Coupon>>((ref) => ref.watch(mockApiProvider).coupons());

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
