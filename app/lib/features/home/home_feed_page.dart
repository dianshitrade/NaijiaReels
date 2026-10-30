import 'package:naija_reels/shared/ai_label.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/player/player_pool.dart';
import '../../data/mock/mock_api.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/widgets/ankara_pattern.dart';
import '../../shared/widgets/comments_sheet.dart';
import '../../shared/widgets/episode_cover.dart';
import '../../shared/widgets/measure_size.dart';
import '../player/episode_feed_page.dart';
import '../player/subtitle_controls.dart';

/// Feed channels: label → contract `tag`.
const kFeedTabs = <(String, String)>[
  ('Following', 'following'),
  ('Nollywood', 'nollywood'),
  ('Comedy', 'comedy'),
  ('Romance', 'romance'),
  ('For You', 'for_you'),
];

/// Home: vertical immersive recommendation feed (GET /feed, mocked).
class HomeFeedPage extends ConsumerStatefulWidget {
  const HomeFeedPage({super.key, this.active = true, this.onOpenRewards});
  final bool active;
  final VoidCallback? onOpenRewards;
  @override
  ConsumerState<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends ConsumerState<HomeFeedPage> with RouteAware {
  int _tab = kFeedTabs.length - 1; // For You
  final PlayerPool _pool = PlayerPool(maxPlayers: 2);
  final PageController _page = PageController();
  List<FeedItem> _items = const [];
  int _index = 0;
  PooledPlayer? _current;
  bool _covered = false;
  bool _immersive = false;
  bool _paused = false;

  /// Measured height of the bottom info block (title/tags/comment/translation).
  double _infoH = 200;
  static const double _infoBottom = 84;
  Offset? _heartAt;
  int _heartKey = 0;
  final Map<String, bool> _liked = {};
  final Map<String, bool> _saved = {};
  final Map<String, int> _likeCount = {};
  late final SubtitleSettings _subs = SubtitleSettings();

  /// Serialises pool operations so a dispose never races an in-flight open.
  Future<void> _ops = Future<void>.value();
  Future<void> _serial(Future<void> Function() fn) => _ops = _ops.then((_) => fn()).catchError((Object e) {
        debugPrint('[HomeFeed] pool op failed: $e');
      });

  @override
  void initState() {
    super.initState();
    _subs.addListener(_onSubsChanged);
  }

  // Same behaviour as the player page: switch the active track in place.
  void _onSubsChanged() {
    if (!mounted) return;
    setState(() {});
    _pool.setSubtitleLang(_subs.activeLang);
  }

  bool get _visible => widget.active && !_covered && mounted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (r != null) routeObserver.subscribe(this, r);
  }

  @override
  void didUpdateWidget(HomeFeedPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncVisibility();
  }

  @override
  void didPushNext() {
    _covered = true;
    _syncVisibility();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncVisibility();
  }

  void _syncVisibility() {
    if (_visible) {
      _focus(_index);
    } else {
      // Free decoders for the page on top (player page has its own pool).
      _current = null;
      unawaited(_serial(_pool.disposeAll));
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _page.dispose();
    unawaited(_serial(_pool.disposeAll));
    _subs.dispose();
    super.dispose();
  }

  Future<void> _focus(int i) => _serial(() => _doFocus(i));

  Future<void> _doFocus(int i) async {
    if (!_visible || i >= _items.length) return;
    final ep = _items[i].episode;
    final url = ep.hlsUrl;
    if (url == null) {
      await _pool.pauseAll();
      setState(() => _current = null);
      return;
    }
    _pool.subtitlesFor[url] = ep.subtitles;
    _pool.subtitleLang = _subs.activeLang;
    String? next;
    if (i + 1 < _items.length) {
      final n = _items[i + 1].episode;
      if (n.hlsUrl != null) {
        next = n.hlsUrl;
        _pool.subtitlesFor[next!] = n.subtitles;
      }
    }
    // Synchronous: Video must mount right away (open() waits for its texture).
    final p = _pool.activate(url, next: next);
    debugPrint('[HomeFeed] focus i=$i url=$url');
    if (!mounted || _index != i || !_visible) return;
    setState(() {
      _current = p;
      _paused = false;
    });
  }

  void _setTab(int t) {
    if (t == _tab) return;
    unawaited(_serial(_pool.disposeAll));
    setState(() {
      _tab = t;
      _items = const [];
      _index = 0;
      _current = null;
    });
  }

  bool _isLiked(FeedItem it) => _liked[it.episode.id] ?? it.liked;
  bool _isSaved(FeedItem it) => _saved[it.drama.id] ?? it.saved;
  int _likes(FeedItem it) => _likeCount[it.episode.id] ?? it.episode.likeCount;

  void _toggleLike(FeedItem it, {bool? to}) {
    final now = to ?? !_isLiked(it);
    if (now == _isLiked(it)) return;
    setState(() {
      _liked[it.episode.id] = now;
      _likeCount[it.episode.id] = _likes(it) + (now ? 1 : -1);
    });
    unawaited(ref.read(mockApiProvider).setLiked(it.episode.id, now)); // optimistic
  }

  void _toggleSave(FeedItem it) {
    final now = !_isSaved(it);
    setState(() => _saved[it.drama.id] = now);
    unawaited(ref.read(mockApiProvider).setSaved(it.drama.id, now));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(now ? 'Saved to My List' : 'Removed from My List'), duration: const Duration(seconds: 1)));
  }

  void _openFull(FeedItem it) {
    final idx = (it.episode.episodeNo - 1).clamp(0, 9999);
    context.push(Routes.play(it.drama.id, idx));
  }

  final Map<String, int> _commentCount = {};
  int _comments(FeedItem it) => _commentCount[it.episode.id] ?? it.episode.commentCount;

  void _showComments(FeedItem it) => showCommentsSheet(context,
      episodeId: it.episode.id,
      commentCount: _comments(it),
      onPosted: (n) => setState(() => _commentCount[it.episode.id] = n));

  @override
  Widget build(BuildContext context) {
    final tag = kFeedTabs[_tab].$2;
    final feed = ref.watch(feedProvider(tag));
    final top = MediaQuery.paddingOf(context).top;
    Widget body = feed.when(
      // Never a bare black/loading screen: real /dramas cover + skeleton.
      loading: () => const FeedPlaceholder(),
      error: (e, _) =>
          PlayerErrorView(message: 'Feed failed to load', onRetry: () => ref.invalidate(feedProvider(tag))),
      data: (items) {
        if (!identical(items, _items)) {
          _items = items;
          WidgetsBinding.instance.addPostFrameCallback((_) => _focus(_index));
        }
        if (items.isEmpty) {
          return _EmptyFeed(following: tag == 'following', onBrowse: () => _setTab(kFeedTabs.length - 1));
        }
        return PageView.builder(
          key: ValueKey('feed-$tag'),
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: items.length,
          onPageChanged: (i) {
            setState(() {
              _index = i;
              _current = null;
            });
            _focus(i);
          },
          itemBuilder: (_, i) => _card(items[i], i),
        );
      },
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        body,
        if (!_immersive) Positioned(top: 0, left: 0, right: 0, child: FeedTopBar(top: top, tab: _tab, onTab: _setTab)),
      ]),
    );
  }

  Widget _card(FeedItem it, int i) {
    final focused = i == _index;
    final u = it.episode.hlsUrl;
    // Focused card plays; the next card shows its preloaded (paused) player
    // as soon as it is scrolled into view.
    final pooled = focused ? _current : (u == null ? null : _pool.get(u));
    final d = it.drama;
    return Stack(key: ValueKey('feed-card-${d.id}'), fit: StackFit.expand, children: [
      if (pooled != null)
        Video(
          key: ValueKey(pooled.url),
          controller: pooled.controller,
          fit: BoxFit.cover,
          controls: NoVideoControls,
          subtitleViewConfiguration: playerSubtitleConfig(0),
        ),
      if (it.episode.locked)
        Stack(fit: StackFit.expand, children: [
          EpisodeCover(
              episodeCoverUrl: it.episode.coverUrl,
              dramaCoverUrl: d.coverUrl,
              title: d.title,
              showFallbackTitle: false,
              decodeWidth: 720),
          Container(color: Colors.black54),
          const Center(child: Icon(Icons.lock, size: 48, color: Colors.white70)),
        ])
      else
        FirstFramePoster(
          key: ValueKey('feed-poster-${it.episode.id}'),
          pooled: pooled,
          onRetry: () async {
            final u = it.episode.hlsUrl;
            if (u != null) await _serial(() => _pool.remove(u));
            _focus(i);
          },
          message: pooled == null ? 'Loading…' : null,
          child: EpisodeCover(
              episodeCoverUrl: it.episode.coverUrl,
              dramaCoverUrl: d.coverUrl,
              title: d.title,
              showFallbackTitle: false,
              decodeWidth: 720),
        ),
      if (pooled != null)
        PlayerTapLayer(
          showPlayIcon: _paused,
          heartAt: _heartAt,
          heartKey: _heartKey,
          onHeartEnd: (k) {
            if (k == _heartKey) setState(() => _heartAt = null);
          },
          onTap: () {
            pooled.player.playOrPause();
            setState(() => _paused = !_paused);
          },
          onDoubleTap: (pos) {
            setState(() {
              _heartAt = pos;
              _heartKey++;
            });
            _toggleLike(it, to: true);
          },
        ),
      if (pooled != null)
        PlayerSubtitleOverlay(
            key: const ValueKey('feed-subtitle'),
            player: pooled.player,
            enabled: _subs.activeLang != null,
            bottom: _immersive ? 64 : subtitleBottomAbove(infoBottom: _infoBottom, infoHeight: _infoH)),
      if (!_immersive) ...[
        Positioned(left: 0, right: 0, bottom: 0, height: _infoBottom + _infoH + 120, child: const IgnorePointer(child: _BottomShade())),
        Positioned(
          right: 6,
          top: MediaQuery.sizeOf(context).height * .3,
          child: RewardCoinWidget(
            coins:
                ref.watch(walletProvider).maybeWhen(data: (w) => '${w.balanceCoins + w.bonusCoins}', orElse: () => '…'),
            onTap: widget.onOpenRewards,
          ),
        ),
        Positioned(
          right: 4,
          bottom: 92,
          child: Column(children: [
            PlayerRailButton(
                key: const ValueKey('feed-save'),
                icon: _isSaved(it) ? Icons.star : Icons.star_border,
                color: _isSaved(it) ? AppColors.gold : Colors.white,
                label: compactCount(
                    (d.saveCount ?? 0) + (_isSaved(it) && !it.saved ? 1 : 0) - (!_isSaved(it) && it.saved ? 1 : 0)),
                onTap: () => _toggleSave(it)),
            const SizedBox(height: 14),
            PlayerRailButton(
                key: const ValueKey('feed-comment'),
                icon: Icons.chat_bubble,
                label: compactCount(_comments(it)),
                onTap: () => _showComments(it)),
            const SizedBox(height: 14),
            PlayerRailButton(
                key: const ValueKey('feed-like'),
                icon: Icons.favorite,
                color: _isLiked(it) ? AppColors.primary : Colors.white,
                label: compactCount(_likes(it)),
                onTap: () => _toggleLike(it)),
            const SizedBox(height: 14),
            PlayerRailButton(
                icon: Icons.reply,
                mirror: true,
                label: 'Share',
                onTap: () => SharePlus.instance.share(ShareParams(text: 'Watch "${d.title}" on NaijaReels'))),
          ]),
        ),
        Positioned(
            left: 14,
            right: 84,
            bottom: _infoBottom,
            child: MeasureSize(
              key: const ValueKey('feed-info'),
              onHeight: (h) {
                if (mounted && (h - _infoH).abs() > 0.5) setState(() => _infoH = h);
              },
              child: _Info(
                item: it,
                onTitle: () => context.push(Routes.dramaDetail(d.id)),
                onFullscreen: () => setState(() => _immersive = true),
                subs: _subs,
                onTranslate: () => showSubtitlePicker(context, _subs),
                onComment: () => _showComments(it)),
            )),
      ] else
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 8,
          child: IconButton(
            key: const ValueKey('feed-exit-fullscreen'),
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 30),
            onPressed: () => setState(() => _immersive = false),
          ),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (pooled != null) PlayerProgress(player: pooled.player),
          if (!_immersive) WatchFullBar(total: d.plannedEpisodes, onTap: () => _openFull(it)),
        ]),
      ),
    ]);
  }
}

class _BottomShade extends StatelessWidget {
  const _BottomShade();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]),
        ),
      );
}

/// Edge fade width of the category tabs; scroll padding equals it so a fully
/// scrolled tab never sits under the fade.
const double kTabFade = 16;

class FeedTopBar extends StatefulWidget {
  const FeedTopBar({super.key, required this.top, required this.tab, required this.onTab});
  final double top;
  final int tab;
  final ValueChanged<int> onTab;

  @override
  State<FeedTopBar> createState() => FeedTopBarState();
}

class FeedTopBarState extends State<FeedTopBar> {
  final _keys = [for (final _ in kFeedTabs) GlobalKey()];

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(FeedTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) _reveal(animate: true);
  }

  /// Scrolls the selected tab fully into view (centered when possible) so it
  /// is never clipped, on any screen width.
  void _reveal({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[widget.tab].currentContext;
      if (c == null || !mounted) return;
      Scrollable.ensureVisible(c,
          alignment: 0.5, duration: animate ? const Duration(milliseconds: 200) : Duration.zero);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return Container(
      padding: EdgeInsets.only(top: widget.top + 4, bottom: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Colors.transparent]),
      ),
      child: Row(children: [
        IconButton(
            key: const ValueKey('feed-menu'),
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () => context.push(Routes.dramas)),
        Expanded(
          // Soft fade at both edges: a tab scrolled partly out of view fades
          // instead of showing a hard-cut fragment like "edy".
          child: ShaderMask(
            shaderCallback: (r) {
              final f = r.width <= 0 ? 0.0 : (kTabFade / r.width).clamp(0.0, 0.3);
              return LinearGradient(
                colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                stops: [0, f, 1 - f, 1],
              ).createShader(r);
            },
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              key: const ValueKey('feed-tabs-scroll'),
              scrollDirection: Axis.horizontal,
              reverse: true, // "For You" (default) starts at the right edge
              padding: const EdgeInsets.symmetric(horizontal: kTabFade),
              child: Row(children: [
                for (var i = 0; i < kFeedTabs.length; i++)
                  GestureDetector(
                    key: ValueKey('feed-tab-${kFeedTabs[i].$2}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onTab(i),
                    child: Padding(
                      key: _keys[i],
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(kFeedTabs[i].$1,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                color: i == tab ? Colors.white : Colors.white60,
                                fontSize: i == tab ? 19 : 17,
                                fontWeight: i == tab ? FontWeight.w800 : FontWeight.w600,
                                shadows: const [Shadow(color: Color(0x88000000), blurRadius: 4)])),
                        const SizedBox(height: 4),
                        Container(
                            width: 18,
                            height: 3,
                            decoration: BoxDecoration(
                                color: i == tab ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(2))),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        IconButton(
            key: const ValueKey('feed-search'),
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            onPressed: () => context.push(Routes.dramas)),
      ]),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(
      {required this.item,
      required this.onTitle,
      required this.onFullscreen,
      required this.onComment,
      required this.subs,
      required this.onTranslate});
  final SubtitleSettings subs;
  final VoidCallback onTranslate;
  final FeedItem item;
  final VoidCallback onTitle;
  final VoidCallback onFullscreen;
  final VoidCallback onComment;

  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 4)];

  Widget _chip(String t) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(4)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final d = item.drama;
    final tags = [
      for (final t in d.tags.take(3)) t.isEmpty ? t : t[0].toUpperCase() + t.substring(1),
      'Season ${item.episode.seasonNumber}',
    ];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: Alignment.center,
        child: GestureDetector(
          key: const ValueKey('feed-fullscreen'),
          onTap: onFullscreen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration:
                BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fullscreen, size: 18, color: Colors.white),
              SizedBox(width: 4),
              Text('Full screen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Season + watching bar
      GestureDetector(
        onTap: onTitle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.video_library, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text('Season ${item.episode.seasonNumber}', style: const TextStyle(color: Colors.white, fontSize: 13)),
            Container(width: 1, height: 12, color: Colors.white38, margin: const EdgeInsets.symmetric(horizontal: 8)),
            Text('${compactCount(d.watchingCount ?? 0)} watching',
                key: const ValueKey('feed-watching'), style: const TextStyle(color: Colors.white, fontSize: 13)),
            const Icon(Icons.chevron_right, size: 16, color: Colors.white70),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: onTitle,
        child: Row(children: [
          if (d.badge != null)
            Container(
              key: const ValueKey('feed-badge'),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: d.badge == 'hot' ? AppColors.primary : AppColors.gold, borderRadius: BorderRadius.circular(4)),
              child: Text(d.badge == 'hot' ? 'Hot' : 'New',
                  style: TextStyle(
                      color: d.badge == 'hot' ? Colors.white : Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          Flexible(
            child: Text(d.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, shadows: _shadow)),
          ),
          const Icon(Icons.chevron_right, color: Colors.white),
        ]),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final t in tags) _chip(t)])),
      if (d.topComment != null) ...[
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onComment,
          child: Row(children: [
            const Icon(Icons.local_fire_department, size: 16, color: AppColors.gold),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Top comment: ${d.topComment!.text}',
                  key: const ValueKey('feed-top-comment'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, shadows: _shadow)),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 6),
      KeyedSubtree(
          key: const ValueKey('feed-see-translation'), child: SeeTranslationLink(settings: subs, onPick: onTranslate)),
      const SizedBox(height: 4),
      const Row(children: [
        Icon(Icons.info_outline, size: 13, color: Colors.white54),
        SizedBox(width: 4),
        Text(kAiContentLabel, style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    ]);
  }
}

class WatchFullBar extends StatelessWidget {
  const WatchFullBar({super.key, required this.total, required this.onTap});
  final int total;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('feed-watch-full'),
      onTap: onTap,
      child: Container(
        height: 52,
        color: const Color(0xFF161A18),
        child: Stack(children: [
          const Positioned.fill(child: TextilePattern(opacity: .07, cell: 22)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Watch full drama · $total EPs',
                      style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.following, required this.onBrowse});
  final bool following;
  final VoidCallback onBrowse;
  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const TextilePattern(style: TextileStyle.adire, opacity: .07),
      Center(
        key: const ValueKey('feed-empty'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(following ? Icons.favorite_border : Icons.movie_outlined, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(following ? 'You never follow any drama yet' : 'Nothing here yet',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                following
                    ? 'Save dramas you like and their new episodes will show here.'
                    : 'Check back soon for new dramas.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            FilledButton(onPressed: onBrowse, child: const Text('Oya, find something to watch')),
          ]),
        ),
      ),
    ]);
  }
}

/// First-screen / tab-switch placeholder: the first real /dramas cover with a
/// skeleton of the info block (falls back to a plain skeleton), never black.
class FeedPlaceholder extends ConsumerWidget {
  const FeedPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(dramaListProvider).valueOrNull ?? const <Drama>[];
    final cover = list.isEmpty ? null : list.first.coverUrl;
    Widget bar(double w) => Container(
        width: w,
        height: 12,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)));
    return Stack(key: const ValueKey('feed-placeholder'), fit: StackFit.expand, children: [
      if (cover != null && cover.isNotEmpty)
        EpisodeCover(dramaCoverUrl: cover, title: list.first.title, showFallbackTitle: false, decodeWidth: 720)
      else
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E2A24), Color(0xFF101412)]),
          ),
        ),
      const Positioned(left: 0, right: 0, bottom: 0, height: 360, child: _BottomShade()),
      Positioned(
        left: 14,
        bottom: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(180), bar(120), bar(220)]),
      ),
      const Center(
          child: SizedBox(
              width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70))),
    ]);
  }
}
