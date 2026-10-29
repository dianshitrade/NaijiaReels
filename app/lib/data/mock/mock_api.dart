// Central mock layer for the five-tab contract (naija-backend
// contracts/openapi.yaml, branch feat/T13-five-tabs-contract @ bedf328).
// None of these endpoints exist on the backend yet. Field names and sample
// values are copied from the contract. Flip [kUseMocks] off once they ship;
// every mocked call lives in this file only.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../repository.dart';

/// Master switch for the whole mock layer.
const bool kUseMocks = true;

/// Contract error: reward already claimed (treat as claimed, not an error).
const int kErrAlreadyClaimed = 40903;

/// Per-drama contract fields missing from the live API (Drama + DramaDetail).
class _DramaExtras {
  const _DramaExtras(this.heatCount, this.watchingCount, this.badge, this.status, this.totalEpisodes,
      [this.topComment]);
  final int heatCount;
  final int watchingCount;
  final String? badge;
  final String status;
  final int totalEpisodes;
  final TopComment? topComment;
}

/// Contract examples for known ids; others derive stable values from the id.
const Map<String, _DramaExtras> _extras = {
  'dr_mama': _DramaExtras(1284000, 3120, 'hot', 'ongoing', 60,
      TopComment(text: 'Mama Bisi no go kill me with laugh 😂', likeCount: 4210, userName: 'Tunde_Ib')),
  'dr_prince': _DramaExtras(856000, 1450, 'new', 'completed', 40),
  'dr_lagos': _DramaExtras(402000, 610, null, 'ongoing', 50),
};

/// Contract chart examples: rankChange per id (null = new entry).
const Map<String, int?> _rankChange = {'dr_mama': 2, 'dr_prince': null, 'dr_lagos': -1};

const _comments = [
  'Wetin you dey watch? This one sweet die!',
  'I no fit wait for the next episode o',
  'The plot twist for episode 2 shock me',
];

Drama enrichDrama(Drama d) {
  final e = _extras[d.id];
  if (e != null) {
    return d.copyWith(
        heatCount: d.heatCount ?? e.heatCount,
        watchingCount: d.watchingCount ?? e.watchingCount,
        badge: d.badge ?? e.badge,
        status: d.status ?? e.status,
        totalEpisodes: d.totalEpisodes ?? e.totalEpisodes,
        topComment: d.topComment ?? e.topComment);
  }
  final h = d.id.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
  return d.copyWith(
    heatCount: d.heatCount ?? 120000 + h % 900000,
    watchingCount: d.watchingCount ?? 300 + h % 4000,
    badge: d.badge ?? (h % 3 == 0 ? 'hot' : (h % 3 == 1 ? 'new' : null)),
    status: d.status ?? (d.completed ? 'completed' : 'ongoing'),
    totalEpisodes: d.totalEpisodes ?? (d.completed ? d.episodeCount : d.episodeCount + 20),
    topComment:
        d.topComment ?? TopComment(text: _comments[h % _comments.length], likeCount: 200 + h % 3000, userName: null),
  );
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
      final h = d.id.hashCode.abs();
      return FeedItem(
        drama: d,
        episode: FeedEpisode(
          id: ep.id,
          episodeNo: ep.episodeNo,
          durationSec: ep.durationSec,
          locked: ep.locked,
          free: ep.free,
          priceCoins: ep.priceCoins,
          coverUrl: ep.coverUrl ?? d.coverUrl,
          hlsUrl: play?.hlsUrl,
          hlsUrlExpiresAt: play?.expiresAt,
          subtitles: play?.subtitles ?? const [],
        ),
        liked: _liked.contains(ep.id),
        saved: _saved.contains(d.id),
        likeCount: d.id == 'dr_mama' ? 2310 : 400 + h % 5000,
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
