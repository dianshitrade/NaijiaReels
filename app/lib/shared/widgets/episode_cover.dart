import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import 'cover_image.dart';

/// Ordered cover candidates: episode cover first, then drama cover.
/// Empty / null entries are skipped. When the list is exhausted the
/// [CoverFallback] title placeholder is shown.
List<String> coverCandidates({String? episodeCoverUrl, String? dramaCoverUrl}) => [
      for (final u in [episodeCoverUrl, dramaCoverUrl])
        if (u != null && u.trim().isNotEmpty) u.trim(),
    ];

/// 3-level cover: episode coverUrl -> drama coverUrl -> CoverFallback.
/// A level that fails to load falls through to the next one.
class EpisodeCover extends StatelessWidget {
  const EpisodeCover({
    super.key,
    this.episodeCoverUrl,
    this.dramaCoverUrl,
    this.title = '',
    this.showFallbackTitle = true,
    this.decodeWidth,
    this.imageProviderOverride,
  });

  final String? episodeCoverUrl;
  final String? dramaCoverUrl;
  final String title;
  final bool showFallbackTitle;

  /// Limits decoded bitmap width (px) for thumbnails (memCacheWidth).
  final int? decodeWidth;

  /// Tests only: supply images without network.
  final ImageProvider Function(String url)? imageProviderOverride;

  @override
  Widget build(BuildContext context) {
    final c = coverCandidates(episodeCoverUrl: episodeCoverUrl, dramaCoverUrl: dramaCoverUrl);
    return _level(c, 0);
  }

  Widget _level(List<String> c, int i) {
    if (i >= c.length) {
      return CoverFallback(title: title, showTitle: showFallbackTitle);
    }
    final url = c[i];
    final o = imageProviderOverride;
    if (o != null) {
      return Image(
        key: ValueKey('cover-$i'),
        image: o(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _level(c, i + 1),
      );
    }
    return CachedNetworkImage(
      key: ValueKey('cover-$i'),
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: decodeWidth,
      placeholder: (_, __) => Container(color: AppColors.surfaceHigh),
      errorWidget: (_, __, ___) => _level(c, i + 1),
    );
  }
}

/// Episode picker grid: cover thumbnail + EP number + lock/price badge.
class EpisodeGrid extends StatelessWidget {
  const EpisodeGrid({
    super.key,
    required this.episodes,
    required this.dramaCoverUrl,
    required this.dramaTitle,
    required this.onTap,
    this.currentIndex,
    this.columns = 5,
    this.imageProviderOverride,
  });

  final List<EpisodeItem> episodes;
  final String dramaCoverUrl;
  final String dramaTitle;
  final void Function(int index) onTap;
  final int? currentIndex;
  final int columns;
  final ImageProvider Function(String url)? imageProviderOverride;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 3;
    // A plain Wrap of fixed-size tiles: no shrink-wrapped GridView inside the
    // sheet's scroll view (that rendered an empty panel on device).
    return LayoutBuilder(builder: (ctx, c) {
      final maxW =
          c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : (MediaQuery.maybeOf(ctx)?.size.width ?? 360) - 32;
      final tileW = ((maxW - (columns - 1) * 8) / columns).floorToDouble();
      final decodeW = (tileW * dpr).ceil().clamp(64, 400);
      Widget tile(int i) {
        final e = episodes[i];
        return GestureDetector(
          key: ValueKey('ep-tile-${e.episodeNo}'),
          onTap: () => onTap(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(fit: StackFit.expand, children: [
              EpisodeCover(
                episodeCoverUrl: e.coverUrl,
                dramaCoverUrl: dramaCoverUrl,
                title: dramaTitle,
                showFallbackTitle: false,
                decodeWidth: decodeW,
                imageProviderOverride: imageProviderOverride,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              if (currentIndex == i)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 4,
                child: Text('${e.episodeNo}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 3)])),
              ),
              if (e.locked)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock, size: 11, color: AppColors.gold),
                      if (e.priceCoins > 0)
                        Text(' ${e.priceCoins}', style: const TextStyle(fontSize: 9, color: AppColors.gold)),
                    ]),
                  ),
                ),
            ]),
          ),
        );
      }

      return Wrap(
        key: const ValueKey('episode-grid'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < episodes.length; i++) SizedBox(width: tileW, height: tileW * 16 / 9, child: tile(i)),
        ],
      );
    });
  }
}

/// Episode picker grouped by `seasonNumber` (contract: episodeNo restarts per
/// season). Single-season dramas render a plain [EpisodeGrid]. [onTap] gets
/// the index into the flat [episodes] list.
class SeasonedEpisodeGrid extends StatelessWidget {
  const SeasonedEpisodeGrid({
    super.key,
    required this.episodes,
    required this.dramaCoverUrl,
    required this.dramaTitle,
    required this.onTap,
    this.currentIndex,
  });
  final List<EpisodeItem> episodes;
  final String dramaCoverUrl;
  final String dramaTitle;
  final void Function(int index) onTap;
  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    final seasons = {for (final e in episodes) e.seasonNumber}.toList()..sort();
    if (seasons.length <= 1) {
      return EpisodeGrid(
          episodes: episodes,
          dramaCoverUrl: dramaCoverUrl,
          dramaTitle: dramaTitle,
          currentIndex: currentIndex,
          onTap: onTap);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final s in seasons)
        ...() {
          final idx = [
            for (var k = 0; k < episodes.length; k++)
              if (episodes[k].seasonNumber == s) k
          ];
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Season $s',
                  key: ValueKey('episodes-season-$s'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            EpisodeGrid(
              key: ValueKey('episodes-grid-s$s'),
              episodes: [for (final k in idx) episodes[k]],
              dramaCoverUrl: dramaCoverUrl,
              dramaTitle: dramaTitle,
              currentIndex: currentIndex != null && idx.contains(currentIndex) ? idx.indexOf(currentIndex!) : null,
              onTap: (j) => onTap(idx[j]),
            ),
          ];
        }(),
    ]);
  }
}
