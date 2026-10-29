import '../app/env.dart';

class Drama {
  const Drama({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.tags,
    required this.episodeCount,
    this.description,
    this.episodes = const [],
    this.completed = false,
    this.heatCount,
    this.watchingCount,
    this.badge,
    this.status,
    this.totalEpisodes,
    this.topComment,
  });

  /// Contract T13 fields (null until the backend ships them; mocked in data/mock).
  final int? heatCount;
  final int? watchingCount;

  /// 'hot' | 'new' | null
  final String? badge;

  /// 'completed' | 'ongoing'
  final String? status;

  /// Planned total episodes; [episodeCount] is released so far.
  final int? totalEpisodes;
  final TopComment? topComment;

  int get plannedEpisodes => totalEpisodes ?? episodeCount;

  Drama copyWith({
    int? heatCount,
    int? watchingCount,
    String? badge,
    String? status,
    int? totalEpisodes,
    TopComment? topComment,
    List<EpisodeItem>? episodes,
  }) =>
      Drama(
        id: id,
        title: title,
        coverUrl: coverUrl,
        tags: tags,
        episodeCount: episodeCount,
        description: description,
        episodes: episodes ?? this.episodes,
        completed: status != null ? status == 'completed' : completed,
        heatCount: heatCount ?? this.heatCount,
        watchingCount: watchingCount ?? this.watchingCount,
        badge: badge ?? this.badge,
        status: status ?? this.status,
        totalEpisodes: totalEpisodes ?? this.totalEpisodes,
        topComment: topComment ?? this.topComment,
      );

  /// All episodes released (API `status: completed` / `completed: true`).
  final bool completed;
  final String id;
  final String title;
  final String coverUrl;
  final List<String> tags;
  final int episodeCount;
  final String? description;
  final List<EpisodeItem> episodes;

  factory Drama.fromJson(Map<String, dynamic> j) => Drama(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        coverUrl: Env.resolve(j['coverUrl'] as String?),
        tags: ((j['tags'] as List?) ?? const []).cast<String>(),
        episodeCount: (j['episodeCount'] as num?)?.toInt() ?? 0,
        description: j['description'] as String?,
        episodes: ((j['episodes'] as List?) ?? const [])
            .map((e) => EpisodeItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        completed: j['completed'] == true ||
            (j['status'] as String?)?.toLowerCase() == 'completed' ||
            ((j['episodeCount'] as num?)?.toInt() ?? 0) > 0 &&
                ((j['episodes'] as List?)?.length ?? 0) >= ((j['episodeCount'] as num?)?.toInt() ?? 0),
        heatCount: (j['heatCount'] as num?)?.toInt(),
        watchingCount: (j['watchingCount'] as num?)?.toInt(),
        badge: j['badge'] as String?,
        status: j['status'] as String?,
        totalEpisodes: (j['totalEpisodes'] as num?)?.toInt(),
        topComment: TopComment.tryParse(j['topComment']),
      );
}

/// Contract `TopComment` (nullable object).
class TopComment {
  const TopComment({required this.text, required this.likeCount, this.userName});
  final String text;
  final int likeCount;
  final String? userName;
  static TopComment? tryParse(Object? o) {
    if (o is! Map || o['text'] is! String) return null;
    return TopComment(
        text: o['text'] as String,
        likeCount: (o['likeCount'] as num?)?.toInt() ?? 0,
        userName: o['userName'] as String?);
  }
}

/// Contract `FeedEpisode`.
class FeedEpisode {
  const FeedEpisode({
    required this.id,
    required this.episodeNo,
    required this.durationSec,
    required this.locked,
    this.free = false,
    this.priceCoins = 0,
    this.coverUrl,
    this.hlsUrl,
    this.hlsUrlExpiresAt,
    this.subtitles = const [],
  });
  final String id;
  final int episodeNo;
  final int durationSec;
  final bool locked;
  final bool free;
  final int priceCoins;
  final String? coverUrl;

  /// Signed, ~10 min; always null when [locked].
  final String? hlsUrl;
  final String? hlsUrlExpiresAt;
  final List<SubtitleRef> subtitles;
}

/// Contract `FeedItem`: GET /feed?tag=… item.
class FeedItem {
  const FeedItem({
    required this.drama,
    required this.episode,
    this.liked = false,
    this.saved = false,
    this.likeCount = 0,
  });
  final Drama drama;
  final FeedEpisode episode;
  final bool liked;
  final bool saved;
  final int likeCount;
}

class EpisodeItem {
  const EpisodeItem({
    required this.id,
    required this.episodeNo,
    required this.title,
    required this.free,
    required this.locked,
    required this.priceCoins,
    this.durationSec = 0,
    this.coverUrl,
  });

  final String id;
  final int episodeNo;
  final String title;
  final bool free;
  final bool locked;
  final int priceCoins;
  final int durationSec;

  /// Optional 9:16 episode cover; null when the API omits it.
  final String? coverUrl;

  factory EpisodeItem.fromJson(Map<String, dynamic> j) => EpisodeItem(
        id: j['id'] as String,
        episodeNo: (j['episodeNo'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        free: j['free'] as bool? ?? false,
        locked: j['locked'] as bool? ?? false,
        priceCoins: (j['priceCoins'] as num?)?.toInt() ?? 0,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        coverUrl: j['coverUrl'] is String && (j['coverUrl'] as String).isNotEmpty
            ? Env.resolve(j['coverUrl'] as String)
            : null,
      );
}

class HomeSection {
  const HomeSection(this.title, this.items);
  final String title;
  final List<Drama> items;
}

class HomeData {
  const HomeData({required this.banners, required this.sections});
  final List<Drama> banners;
  final List<HomeSection> sections;

  factory HomeData.fromJson(Map<String, dynamic> j) {
    List<Drama> list(Object? l) => ((l as List?) ?? const [])
        .map((e) => Drama.fromJson(e as Map<String, dynamic>))
        .toList();
    return HomeData(
      banners: list(j['banners']),
      sections: ((j['sections'] as List?) ?? const [])
          .map((s) => HomeSection((s as Map)['title'] as String? ?? '', list(s['items'])))
          .toList(),
    );
  }
}

class Wallet {
  const Wallet({required this.balanceCoins, required this.bonusCoins});
  final int balanceCoins;
  final int bonusCoins;
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        balanceCoins: (j['balanceCoins'] as num?)?.toInt() ?? 0,
        bonusCoins: (j['bonusCoins'] as num?)?.toInt() ?? 0,
      );
}

/// External WebVTT subtitle for an episode (fallback when HLS tracks are
/// not exposed by the player).
class SubtitleRef {
  const SubtitleRef({required this.lang, required this.label, required this.url});
  final String lang;
  final String label;
  final String url;

  static SubtitleRef? tryParse(Object? o) {
    if (o is! Map) return null;
    final lang = o['lang'];
    final url = o['url'];
    if (lang is! String || lang.isEmpty || url is! String || url.isEmpty) return null;
    final label = o['label'];
    return SubtitleRef(lang: lang, label: label is String && label.isNotEmpty ? label : lang, url: Env.resolve(url));
  }
}

class PlayInfo {
  const PlayInfo(this.hlsUrl, this.expiresAt, {this.subtitles = const []});
  final String hlsUrl;
  final String? expiresAt;

  /// Empty when the API omits `subtitles` (older backend).
  final List<SubtitleRef> subtitles;
  factory PlayInfo.fromJson(Map<String, dynamic> j) => PlayInfo(
        j['hlsUrl'] as String,
        j['expiresAt'] as String?,
        subtitles: ((j['subtitles'] as List?) ?? const [])
            .map(SubtitleRef.tryParse)
            .whereType<SubtitleRef>()
            .toList(),
      );
}

class UnlockResult {
  const UnlockResult(this.episodeId, this.balanceCoins);
  final String episodeId;
  final int balanceCoins;
  factory UnlockResult.fromJson(Map<String, dynamic> j) => UnlockResult(
      j['episodeId'] as String, (j['balanceCoins'] as num?)?.toInt() ?? 0);
}
