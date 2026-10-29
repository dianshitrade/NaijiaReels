import 'package:media_kit/media_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../core/player/player_pool.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/widgets/episode_cover.dart';
import '../../shared/widgets/wallet_chip.dart';

class _EpState {
  String? url;
  int? lockedPrice;
  String? error;
  bool loading = false;
}

/// Vertical swipe player over a drama's episodes (9:16).
/// Locked episodes (403/40301) show an unlock dialog with priceCoins;
/// coin unlock failing with 402/40201 shows "not enough coins".
class EpisodeFeedPage extends ConsumerStatefulWidget {
  const EpisodeFeedPage({super.key, required this.dramaId, this.initialIndex = 0});
  final String dramaId;
  final int initialIndex;

  @override
  ConsumerState<EpisodeFeedPage> createState() => _EpisodeFeedPageState();
}

class _EpisodeFeedPageState extends ConsumerState<EpisodeFeedPage> {
  final _pool = PlayerPool(maxPlayers: 3);
  final _states = <int, _EpState>{};
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  List<EpisodeItem> _episodes = const [];
  int _index = 0;
  bool _dialogOpen = false;
  String? _title;
  String _dramaCover = '';

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
  }

  Future<void> _load() async {
    final d = await ref.read(dramaDetailProvider(widget.dramaId).future);
    if (!mounted) return;
    setState(() {
      _episodes = d.episodes;
      _title = d.title;
      _dramaCover = d.coverUrl;
    });
    await _focus(_index);
  }

  Future<_EpState> _resolve(int i, {bool force = false}) async {
    final st = _states.putIfAbsent(i, _EpState.new);
    if (!force && (st.url != null || st.lockedPrice != null)) return st;
    st
      ..loading = true
      ..error = null;
    try {
      final info = await ref.read(repositoryProvider).play(_episodes[i].id);
      st
        ..url = info.hlsUrl
        ..lockedPrice = null;
    } on ApiException catch (e) {
      if (e.isLocked) {
        final data = e.data;
        st.lockedPrice = data is Map ? (data['priceCoins'] as num?)?.toInt() : null;
        st.lockedPrice ??= _episodes[i].priceCoins;
      } else {
        st.error = e.message;
      }
    } catch (e) {
      // Timeouts / no network / Render cold start failures must be visible.
      st.error = 'Network error: $e';
    } finally {
      st.loading = false;
    }
    return st;
  }

  Future<void> _focus(int i) async {
    if (_episodes.isEmpty) return;
    final cur = await _resolve(i);
    String? nextUrl;
    if (i + 1 < _episodes.length) nextUrl = (await _resolve(i + 1)).url;
    if (!mounted || i != _index) return;
    if (cur.url != null) {
      // Don't await before building: on Android media_kit's open() waits for
      // the Video texture, which only exists once the Video widget is mounted.
      // Awaiting here deadlocked the page on the cover poster.
      final f = _pool.focus(cur.url!, next: nextUrl);
      if (mounted) setState(() {});
      try {
        await f;
      } catch (e) {
        debugPrint('[Play] focus error $e');
      }
    } else {
      await _pool.pauseAll();
      if (nextUrl != null) await _pool.obtain(nextUrl);
    }
    if (!mounted) return;
    setState(() {});
    if (cur.lockedPrice != null) _showUnlock(i);
  }

  Future<void> _showUnlock(int i) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final price = _states[i]?.lockedPrice ?? _episodes[i].priceCoins;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlock EP ${_episodes[i].episodeNo}'),
        content: Row(children: [
          const Icon(Icons.monetization_on, color: AppColors.gold),
          const SizedBox(width: 8),
          Text('$price coins'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Unlock ($price)')),
        ],
      ),
    );
    _dialogOpen = false;
    if (ok == true) await _unlock(i);
  }

  Future<void> _unlock(int i) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(repositoryProvider).unlockWithCoins(_episodes[i].id);
      ref.invalidate(walletProvider);
      ref.invalidate(dramaDetailProvider(widget.dramaId));
      messenger.showSnackBar(SnackBar(content: Text('Unlocked · balance ${r.balanceCoins}')));
      await _resolve(i, force: true);
      if (mounted && i == _index) await _focus(i);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.isInsufficientCoins
            ? 'Not enough coins — top up to continue'
            : 'Unlock failed: ${e.message}'),
      ));
    }
  }

  Future<void> _retry(int i) async {
    final st = _states[i];
    if (st?.url != null) await _pool.remove(st!.url!);
    _states.remove(i);
    if (mounted) setState(() {});
    await _resolve(i, force: true);
    if (mounted) setState(() {});
    if (mounted && i == _index) await _focus(i);
  }

  @override
  void dispose() {
    _pool.disposeAll();
    _page.dispose();
    super.dispose();
  }

  void _showEpisodes() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_title ?? ''} · ${_episodes.length} episodes',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              EpisodeGrid(
                episodes: _episodes,
                dramaCoverUrl: _dramaCover,
                dramaTitle: _title ?? '',
                currentIndex: _index,
                onTap: (i) {
                  Navigator.of(ctx).pop();
                  _page.jumpToPage(i);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, actions: [
        if (_episodes.isNotEmpty)
          IconButton(
            key: const ValueKey('episodes-button'),
            tooltip: 'Episodes',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: _showEpisodes,
          ),
        const WalletChip(),
      ]),
      body: _episodes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _page,
              scrollDirection: Axis.vertical,
              itemCount: _episodes.length,
              onPageChanged: (i) {
                _index = i;
                _focus(i);
              },
              itemBuilder: (_, i) => _buildPage(i),
            ),
    );
  }

  Widget _buildPage(int i) {
    final ep = _episodes[i];
    final st = _states[i];
    final pooled = st?.url == null ? null : _pool.get(st!.url!);
    Widget content;
    if (st?.lockedPrice != null) {
      content = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock, size: 56, color: AppColors.gold),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _showUnlock(i),
            child: Text('Unlock for ${st!.lockedPrice} coins'),
          ),
        ]),
      );
    } else if (st?.error != null) {
      content = PlayerErrorView(message: st!.error!, onRetry: () => _retry(i));
    } else if (pooled != null) {
      content = LayoutBuilder(builder: (ctx, c) {
        final boxH = (c.maxWidth * 16 / 9).clamp(0.0, c.maxHeight);
        final gap = (c.maxHeight - boxH) / 2; // letterbox below the 9:16 box
        return Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Video(
              key: ValueKey(pooled.url),
              controller: pooled.controller,
              fit: BoxFit.cover,
              controls: NoVideoControls,
              subtitleViewConfiguration: playerSubtitleConfig(gap),
            ),
          ),
        );
      });
    } else {
      content = const Center(child: CircularProgressIndicator());
    }
    return Stack(fit: StackFit.expand, children: [
      content, // Video (or spinner / lock / resolve-error) — bottom layer
      // Cover poster ON TOP of Video until ready; must be removable (not opacity).
      if (st?.lockedPrice == null && st?.error == null)
        FirstFramePoster(
          key: ValueKey('poster-${ep.id}'),
          pooled: pooled,
          onRetry: () => _retry(i),
          child: EpisodeCover(
            episodeCoverUrl: ep.coverUrl,
            dramaCoverUrl: _dramaCover,
            title: _title ?? '',
            showFallbackTitle: false,
          ),
        ),
      PlayerChrome(
        title: _title ?? '',
        episodeNo: ep.episodeNo,
        episodeTitle: ep.title,
        total: _episodes.length,
        index: i,
      ),
      // Own subtitle layer, bound only to this page's player.
      if (pooled != null && st?.lockedPrice == null && st?.error == null)
        PlayerSubtitleOverlay(key: ValueKey('subs-${pooled.url}'), player: pooled.player),
    ]);
  }
}

/// Subtitles: white, black outline, translucent black box, 17sp, centered and
/// wrapped, lifted above the PlayerChrome progress bar / title block and kept
/// clear of the right-hand action column. media_kit's built-in SubtitleView is
/// disabled because it scales text by sqrt(area/1920x1080) (~1/3 on phones).
const kSubtitleBottomFromScreen = 175.0;
const kSubtitleStyle = TextStyle(
  fontSize: 17,
  height: 1.3,
  color: Colors.white,
  fontWeight: FontWeight.w600,
  backgroundColor: Color(0x8C000000),
  shadows: [
    Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
    Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1, -1)),
  ],
);

SubtitleViewConfiguration playerSubtitleConfig(double letterboxGap) =>
    const SubtitleViewConfiguration(visible: false);

/// Shows [child] (cover) ABOVE the Video until [pooled] is ready.
/// Ready signals: width>0, height>0, position>0, or playing continuously
/// for >=1s (vivo / some devices never emit width). On ready returns
/// [SizedBox.shrink] so the poster is removed from the Stack — not hidden
/// via opacity. On failure/timeout shows error + Retry instead of a stuck cover.
class FirstFramePoster extends StatelessWidget {
  const FirstFramePoster({super.key, required this.pooled, required this.child, required this.onRetry});
  final PooledPlayer? pooled;
  final Widget child;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = pooled;
    final poster = IgnorePointer(child: KeyedSubtree(key: const ValueKey('first-frame-poster'), child: child));
    if (p == null) return poster;
    return ValueListenableBuilder<String?>(
      valueListenable: p.failure,
      builder: (ctx, fail, _) => fail != null
          ? PlayerErrorView(message: fail, onRetry: onRetry)
          : ValueListenableBuilder<bool>(
              valueListenable: p.ready,
              builder: (ctx, ready, _) => ready
                  ? const SizedBox.shrink()
                  : Stack(fit: StackFit.expand, children: [
                      poster,
                      const Center(child: CircularProgressIndicator()),
                    ]),
            ),
    );
  }
}

class PlayerErrorView extends StatelessWidget {
  const PlayerErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('player-error'),
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('player-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      ),
    );
  }
}

class PlayerSubtitleOverlay extends StatelessWidget {
  const PlayerSubtitleOverlay({super.key, required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 76,
      bottom: kSubtitleBottomFromScreen,
      child: IgnorePointer(
        child: StreamBuilder<List<String>>(
          stream: player.stream.subtitle,
          initialData: player.state.subtitle,
          builder: (ctx, snap) {
            final text = (snap.data ?? const [])
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .join('\n');
            if (text.isEmpty) return const SizedBox.shrink();
            return Text(text,
                key: const ValueKey('player-subtitle-text'),
                textAlign: TextAlign.center,
                softWrap: true,
                textScaler: TextScaler.noScaling,
                style: kSubtitleStyle);
          },
        ),
      ),
    );
  }
}

/// Short-drama style overlay: bottom gradient, title, EP badge, side actions.
class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    required this.title,
    required this.episodeNo,
    required this.episodeTitle,
    required this.total,
    required this.index,
  });
  final String title;
  final int episodeNo;
  final String episodeTitle;
  final int total;
  final int index;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, 0.2),
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xE6000000)],
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 140,
          child: Column(children: [
            for (final a in const [
              (Icons.favorite, 'Like'),
              (Icons.bookmark, 'Save'),
              (Icons.share, 'Share'),
            ]) ...[
              Icon(a.$1, size: 32, color: Colors.white),
              Text(a.$2, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 16),
            ],
          ]),
        ),
        Positioned(
          left: 16,
          right: 72,
          bottom: 40,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
              child: Text('EP $episodeNo / $total',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            if (title.isNotEmpty)
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(episodeTitle,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : (index + 1) / total,
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: Colors.white24,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
