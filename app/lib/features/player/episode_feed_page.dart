import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../core/player/player_pool.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/widgets/episode_cover.dart';
import '../rewards/rewards_page.dart';
import 'subtitle_controls.dart';

class _EpState {
  String? url;
  List<SubtitleRef> subtitles = const [];
  int? lockedPrice;
  String? error;
  bool loading = false;
}

/// Vertical swipe player over a drama's episodes (9:16).
/// Locked episodes (403/40301) show an unlock dialog with priceCoins;
/// coin unlock failing with 402/40201 shows "not enough coins".
class EpisodeFeedPage extends ConsumerStatefulWidget {
  const EpisodeFeedPage(
      {super.key,
      required this.dramaId,
      this.initialIndex = 0,
      this.tab,
      this.systemLocale});
  final String dramaId;
  final int initialIndex;

  /// Selected genre tab (a drama tag); null = "For You".
  final String? tab;

  /// Test hook; defaults to the device locale.
  final Locale Function()? systemLocale;

  @override
  ConsumerState<EpisodeFeedPage> createState() => _EpisodeFeedPageState();
}

class _EpisodeFeedPageState extends ConsumerState<EpisodeFeedPage> {
  final _pool = PlayerPool(maxPlayers: 3);
  final _states = <int, _EpState>{};
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  List<EpisodeItem> _episodes = const [];
  int _index = 0;
  bool _dialogOpen = false;
  String? _title;
  String _dramaCover = '';
  String? _description;
  String? _loadError;
  bool _completed = false;
  bool _immersive = false; // fullscreen: only video + subtitles
  bool _synopsisOpen = false;
  double _rate = 1.0;

  /// Per-episode local UX state (no backend yet).
  final _liked = <int, bool>{};
  final _likeCount = <int, int>{};
  final _saved = <int, bool>{};
  final _localComments = <int, List<String>>{};
  bool _showPlayIcon = false;
  Offset? _heartAt;
  int _heartKey = 0;

  /// Injectable for tests / share_plus mock.
  Future<void> Function(String text, {String? subject}) shareFn = (text,
          {subject}) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _subs = SubtitleSettings(systemLocale: widget.systemLocale);
    _pool.subtitleLang = _subs.activeLang;
    _subs.addListener(_onSubsChanged);
    _load();
  }

  late final SubtitleSettings _subs;

  void _onSubsChanged() {
    if (!mounted) return;
    setState(() {});
    _pool.setSubtitleLang(_subs.activeLang);
  }

  void _pickSubs() => showSubtitlePicker(context, _subs);

  Future<void> _load() async {
    if (mounted && _loadError != null) setState(() => _loadError = null);
    final Drama d;
    try {
      d = await ref
          .read(dramaDetailProvider(widget.dramaId).future)
          .timeout(const Duration(seconds: 75));
    } catch (e) {
      debugPrint('[Play] drama detail failed: $e');
      ref.invalidate(dramaDetailProvider(widget.dramaId));
      if (mounted) {
        setState(() =>
            _loadError = 'Could not load this drama. Check your connection.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _episodes = d.episodes;
      _title = d.title;
      _dramaCover = d.coverUrl;
      _description = d.description;
      _completed = d.completed;
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
        ..subtitles = info.subtitles
        ..lockedPrice = null;
      _pool.subtitlesFor[info.hlsUrl] = info.subtitles;
    } on ApiException catch (e) {
      if (e.isLocked) {
        final data = e.data;
        st.lockedPrice =
            data is Map ? (data['priceCoins'] as num?)?.toInt() : null;
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
    setState(() => _showPlayIcon = false);
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Unlock ($price)')),
        ],
      ),
    );
    _dialogOpen = false;
    if (ok == true) await _unlock(i);
  }

  Future<void> _unlock(int i) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r =
          await ref.read(repositoryProvider).unlockWithCoins(_episodes[i].id);
      ref.invalidate(walletProvider);
      ref.invalidate(dramaDetailProvider(widget.dramaId));
      messenger.showSnackBar(
          SnackBar(content: Text('Unlocked · balance ${r.balanceCoins}')));
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

  PooledPlayer? _pooledFor(int i) {
    final st = _states[i];
    if (st?.url == null) return null;
    return _pool.get(st!.url!);
  }

  Future<void> _togglePlayPause(int i) async {
    final p = _pooledFor(i);
    if (p == null || !(p.ready.value)) return;
    if (p.player.state.playing) {
      await p.player.pause();
      if (mounted) setState(() => _showPlayIcon = true);
    } else {
      await p.player.play();
      if (mounted) setState(() => _showPlayIcon = false);
    }
  }

  void _toggleLike(int i) {
    setState(() {
      final next = !(_liked[i] ?? false);
      _liked[i] = next;
      final base = _likeCount.putIfAbsent(i, () => 128 + (i * 7) % 50);
      _likeCount[i] = (base + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
  }

  /// Double-tap on the video: like (never unlike) and pop a heart at [at].
  /// The right-rail button only toggles state and never shows a heart.
  void _doubleTapLike(int i, Offset at) {
    if (!(_liked[i] ?? false)) _toggleLike(i);
    setState(() {
      _heartAt = at;
      _heartKey++; // new key replaces any running heart: no stacking
    });
  }

  void _onHeartEnd(int key) {
    if (mounted && key == _heartKey && _heartAt != null) {
      setState(() => _heartAt = null);
    }
  }

  void _toggleSave(int i) {
    setState(() => _saved[i] = !(_saved[i] ?? false));
    final on = _saved[i] ?? false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(on ? 'Saved to watchlist (local)' : 'Removed from watchlist'),
      duration: const Duration(seconds: 1),
    ));
  }

  Future<void> _share(int i) async {
    final ep = _episodes[i];
    final title = _title ?? 'NaijaReels';
    final text =
        'Watch "$title" EP${ep.episodeNo} on NaijaReels 🎬\nhttps://naijareels.app/drama/${widget.dramaId}?ep=$i';
    await shareFn(text, subject: title);
  }

  void _showComments(int i) {
    final ctrl = TextEditingController();
    final list = _localComments.putIfAbsent(i, () => <String>[]);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.55,
              child: Column(children: [
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Text('Comments',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('coming soon',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text('No comments yet — local only for now',
                              style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          itemBuilder: (_, j) => ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.person, size: 18)),
                            title: Text(list[j]),
                            dense: true,
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('comment-input'),
                        controller: ctrl,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment (saved locally)',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('comment-send'),
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        final t = ctrl.text.trim();
                        if (t.isEmpty) return;
                        setState(() => list.add(t));
                        ctrl.clear();
                        Navigator.pop(ctx);
                        _showComments(i); // refresh sheet
                      },
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _showEpisodes() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16181A),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          key: const ValueKey('episodes-panel'),
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  '${_completed ? 'Completed' : 'Ongoing'} · All ${_episodes.length} EPs',
                  style: const TextStyle(fontSize: 13, color: Colors.white60)),
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

  Player? get _currentPlayer {
    final u = _states[_index]?.url;
    return u == null ? null : _pool.get(u)?.player;
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181A),
      builder: (ctx) => SafeArea(
        child: Column(
            key: const ValueKey('more-menu'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('menu-speed'),
                leading: const Icon(Icons.speed),
                title: const Text('Playback speed'),
                trailing: Text('${_rate}x'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickSpeed();
                },
              ),
              ListTile(
                key: const ValueKey('menu-quality'),
                leading: const Icon(Icons.hd_outlined),
                title: const Text('Quality'),
                trailing: const Text('Auto'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickQuality();
                },
              ),
              ListTile(
                key: const ValueKey('menu-translation'),
                leading: const Icon(Icons.translate),
                title: const Text('Translation'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickSubs();
                },
              ),
              ListTile(
                key: const ValueKey('menu-report'),
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Thanks. We will review this episode.')));
                },
              ),
            ]),
      ),
    );
  }

  void _pickSpeed() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181A),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
            ListTile(
              title: Text('${r}x'),
              trailing: r == _rate
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() => _rate = r);
                for (final st in _states.values) {
                  final u = st.url;
                  if (u != null) _pool.get(u)?.player.setRate(r);
                }
              },
            ),
        ]),
      ),
    );
  }

  void _pickQuality() {
    final p = _currentPlayer;
    final tracks = (p?.state.tracks.video ?? const <VideoTrack>[])
        .where((t) => (t.h ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181A),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('Auto'),
            subtitle: const Text('Adapts to your network'),
            onTap: () => Navigator.of(ctx).pop(),
          ),
          for (final t in tracks)
            ListTile(
              title: Text(
                  '${t.w != null && t.h != null && t.w! < t.h! ? t.w : t.h}p'),
              onTap: () {
                Navigator.of(ctx).pop();
                p?.setVideoTrack(t);
              },
            ),
        ]),
      ),
    );
  }

  void _openRewards() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const RewardsPage()));
  }

  void _openDetail() =>
      GoRouter.of(context).push(Routes.dramaDetail(widget.dramaId));

  @override
  void dispose() {
    _subs.removeListener(_onSubsChanged);
    _subs.dispose();
    _pool.disposeAll();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ep = _episodes.isEmpty
        ? null
        : _episodes[_index.clamp(0, _episodes.length - 1)];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        _buildBody(),
        if (!_immersive)
          PlayerTopBar(
            episodeNo: ep?.episodeNo,
            onBack: () => Navigator.of(context).maybePop(),
            onMore: _showMore,
          ),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return PlayerErrorView(message: _loadError!, onRetry: _load);
    }
    return _episodes.isEmpty
        ? const PlayerLoadingView(message: 'Loading drama…')
        : PageView.builder(
            controller: _page,
            scrollDirection: Axis.vertical,
            itemCount: _episodes.length,
            onPageChanged: (i) {
              _index = i;
              _focus(i);
            },
            itemBuilder: (_, i) => _buildPage(i),
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
      // /play request in flight: the poster layer above shows cover + spinner.
      content = const SizedBox.shrink();
    }
    return Stack(fit: StackFit.expand, children: [
      content, // Video (or spinner / lock / resolve-error) — bottom layer
      // Cover poster ON TOP of Video until ready; must be removable (not opacity).
      if (st?.lockedPrice == null && st?.error == null)
        FirstFramePoster(
          key: ValueKey('poster-${ep.id}'),
          pooled: pooled,
          onRetry: () => _retry(i),
          message: (st == null || st.loading || pooled == null)
              ? 'Loading episode…'
              : null,
          child: EpisodeCover(
            episodeCoverUrl: ep.coverUrl,
            dramaCoverUrl: _dramaCover,
            title: _title ?? '',
            showFallbackTitle: false,
          ),
        ),
      // Tap layer ABOVE video/poster, BELOW chrome actions.
      // Only onTap/onDoubleTap — no drag handlers — so PageView vertical swipe works.
      if (st?.lockedPrice == null && st?.error == null)
        PlayerTapLayer(
          key: ValueKey('tap-$i'),
          showPlayIcon: i == _index && _showPlayIcon,
          heartAt: i == _index ? _heartAt : null,
          heartKey: _heartKey,
          onTap: () => _togglePlayPause(i),
          onDoubleTap: (pos) => _doubleTapLike(i, pos),
          onHeartEnd: _onHeartEnd,
        ),
      if (!_immersive)
        PlayerChrome(
          title: _title ?? '',
          episodeNo: ep.episodeNo,
          episodeTitle: ep.title,
          total: _episodes.length,
          completed: _completed,
          liked: _liked[i] ?? false,
          likeCount: _likeCount[i] ?? (128 + (i * 7) % 50),
          saved: _saved[i] ?? false,
          commentCount: 24 + (i * 5) % 17 + (_localComments[i]?.length ?? 0),
          saveCount: 40 + (i * 3) % 23 + ((_saved[i] ?? false) ? 1 : 0),
          description: _description,
          synopsisOpen: _synopsisOpen,
          onToggleSynopsis: () =>
              setState(() => _synopsisOpen = !_synopsisOpen),
          onTitle: _openDetail,
          onRewards: _openRewards,
          coins: ref
              .watch(walletProvider)
              .maybeWhen(data: (w) => '${w.balanceCoins}', orElse: () => '…'),
          onLike: () => _toggleLike(i),
          onComment: () => _showComments(i),
          onSave: () => _toggleSave(i),
          onShare: () => _share(i),
          onEpisodes: _showEpisodes,
          onFullscreen: () => setState(() => _immersive = true),
          translation: SeeTranslationLink(settings: _subs, onPick: _pickSubs),
          progress:
              pooled != null && st?.lockedPrice == null && st?.error == null
                  ? PlayerProgress(
                      key: ValueKey('progress-${pooled.url}'),
                      player: pooled.player)
                  : null,
        ),
      if (_immersive)
        Positioned(
          right: 8,
          bottom: 8,
          child: SafeArea(
            child: IconButton(
              key: const ValueKey('exit-fullscreen'),
              icon: const Icon(Icons.fullscreen_exit, color: Colors.white70),
              onPressed: () => setState(() => _immersive = false),
            ),
          ),
        ),
      // Own subtitle layer, bound only to this page's player.
      if (pooled != null && st?.lockedPrice == null && st?.error == null)
        PlayerSubtitleOverlay(
            key: ValueKey('subs-${pooled.url}'),
            player: pooled.player,
            enabled: _subs.enabled,
            bottom: _immersive
                ? kSubtitleBottomImmersive
                : kSubtitleBottomFromScreen +
                    (_synopsisOpen ? kSynopsisExtra : 0)),
    ]);
  }
}

/// Full-screen tap/double-tap layer. Display-only overlays use IgnorePointer;
/// this layer owns pause/play + double-tap like without claiming vertical drags.
class PlayerTapLayer extends StatelessWidget {
  const PlayerTapLayer({
    super.key,
    required this.onTap,
    required this.onDoubleTap,
    this.showPlayIcon = false,
    this.heartAt,
    this.heartKey = 0,
    this.onHeartEnd,
  });
  final void Function(int heartKey)? onHeartEnd;
  final VoidCallback onTap;
  final void Function(Offset normalized) onDoubleTap;
  final bool showPlayIcon;
  final Offset? heartAt;
  final int heartKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      return GestureDetector(
        key: const ValueKey('player-tap-layer'),
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        onDoubleTapDown: (d) {
          final n = Offset(
            (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0),
            (d.localPosition.dy / c.maxHeight).clamp(0.0, 1.0),
          );
          onDoubleTap(n);
        },
        onDoubleTap: () {}, // required paired with onDoubleTapDown
        child: Stack(fit: StackFit.expand, children: [
          if (showPlayIcon)
            const IgnorePointer(
              child: Center(
                child: Icon(Icons.play_arrow_rounded,
                    key: ValueKey('player-play-icon'),
                    size: 88,
                    color: Colors.white70),
              ),
            ),
          if (heartAt != null)
            Positioned(
              left: heartAt!.dx * c.maxWidth - 40,
              top: heartAt!.dy * c.maxHeight - 40,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('heart-$heartKey'),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  onEnd: () => onHeartEnd?.call(heartKey),
                  builder: (_, t, child) => Opacity(
                    // full until 40%, then linearly to exactly 0 at the end
                    opacity: t <= 0.4
                        ? 1.0
                        : (1.0 - (t - 0.4) / 0.6).clamp(0.0, 1.0),
                    child: Transform.scale(scale: 0.6 + 0.8 * t, child: child),
                  ),
                  child: const Icon(Icons.favorite,
                      size: 80, color: Colors.redAccent),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

/// Subtitles: white, black outline, translucent black box, 17sp, centered and
/// wrapped, lifted above the PlayerChrome progress bar / title block and kept
/// clear of the right-hand action column. media_kit's built-in SubtitleView is
/// disabled because it scales text by sqrt(area/1920x1080) (~1/3 on phones).
/// Above the bottom info block (title, synopsis, translation, AI note,
/// progress, Episodes bar). Measured in tests: subtitle never overlaps it.
const kSubtitleBottomFromScreen = 236.0;
const kSynopsisExtra = 90.0;
const kSubtitleBottomImmersive = 64.0;
const kSubtitleStyle = TextStyle(
  fontSize: 17,
  height: 1.3,
  color: Colors.white,
  fontWeight: FontWeight.w600,
  backgroundColor: Color(0x8C000000),
  fontFamilyFallback: kSubtitleFontFallback,
  shadows: [
    Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
    Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1, -1)),
  ],
);

SubtitleViewConfiguration playerSubtitleConfig(double letterboxGap) =>
    const SubtitleViewConfiguration(visible: false);

/// Shows [child] (cover) ABOVE the Video until [pooled] is ready.
/// Ready signals: width>0, height>0 or position>0 (a frame really exists). On ready returns
/// [SizedBox.shrink] so the poster is removed from the Stack — not hidden
/// via opacity. On failure/timeout shows error + Retry instead of a stuck cover.
class FirstFramePoster extends StatelessWidget {
  const FirstFramePoster(
      {super.key,
      required this.pooled,
      required this.child,
      required this.onRetry,
      this.message});
  final PooledPlayer? pooled;
  final String? message;
  final Widget child;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = pooled;
    final poster = IgnorePointer(
        child: KeyedSubtree(
            key: const ValueKey('first-frame-poster'), child: child));
    final spinner = IgnorePointer(
        child: PlayerLoadingView(message: message, transparent: true));
    if (p == null) {
      return Stack(fit: StackFit.expand, children: [poster, spinner]);
    }
    return ValueListenableBuilder<String?>(
      valueListenable: p.failure,
      builder: (ctx, fail, _) => fail != null
          ? PlayerErrorView(message: fail, onRetry: onRetry)
          : ValueListenableBuilder<bool>(
              valueListenable: p.ready,
              builder: (ctx, ready, _) => ready
                  ? IgnorePointer(child: _BufferingSpinner(player: p.player))
                  : Stack(fit: StackFit.expand, children: [poster, spinner]),
            ),
    );
  }
}

/// Spinner shown over the video while it re-buffers after the first frame.
class _BufferingSpinner extends StatelessWidget {
  const _BufferingSpinner({required this.player});
  final Player player;
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
        stream: player.stream.buffering,
        initialData: player.state.buffering,
        builder: (_, s) => s.data == true
            ? const Center(
                child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                        key: ValueKey('player-buffering'),
                        strokeWidth: 3,
                        color: Colors.white70)))
            : const SizedBox.shrink(),
      );
}

/// Never pure black: dark gradient + spinner + text.
class PlayerLoadingView extends StatelessWidget {
  const PlayerLoadingView({super.key, this.message, this.transparent = false});
  final String? message;
  final bool transparent;
  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(
            key: ValueKey('player-loading'), color: Colors.white),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!,
              style:
                  const TextStyle(color: Colors.white, fontSize: 13, shadows: [
                Shadow(color: Colors.black, blurRadius: 4),
              ])),
        ],
      ]),
    );
    if (transparent) return body;
    return DecoratedBox(
      key: const ValueKey('player-loading-view'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1A3A), Color(0xFF0E0E14)],
        ),
      ),
      child: body,
    );
  }
}

class PlayerErrorView extends StatelessWidget {
  const PlayerErrorView(
      {super.key, required this.message, required this.onRetry});
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
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
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
  const PlayerSubtitleOverlay(
      {super.key,
      required this.player,
      this.enabled = true,
      this.bottom = kSubtitleBottomFromScreen});
  final Player player;
  final double bottom;

  /// When false nothing is drawn, even if a stale cue is still buffered.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return Positioned(
      left: 24,
      right: 76,
      bottom: bottom,
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

/// Hongguo-style overlay. Right: reward-coin widget (upper middle), then
/// follow-star, comments, like, share near the bottom. Bottom info block:
/// title + ">", "EP n | synopsis… More/Less", See translation, AI note,
/// green progress bar, "Episodes · Completed · All N EPs ^" + fullscreen.
class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    required this.title,
    required this.episodeNo,
    required this.episodeTitle,
    required this.total,
    this.index = 0,
    this.completed = false,
    this.liked = false,
    this.likeCount = 0,
    this.saved = false,
    this.commentCount = 0,
    this.saveCount = 0,
    this.description,
    this.synopsisOpen = false,
    this.onToggleSynopsis,
    this.onTitle,
    this.onRewards,
    this.coins = '…',
    this.onLike,
    this.onComment,
    this.onSave,
    this.onShare,
    this.onEpisodes,
    this.onFullscreen,
    this.translation,
    this.progress,
  });
  final String title;
  final int episodeNo;
  final String episodeTitle;
  final int total;
  final int index;
  final bool completed;
  final bool liked;
  final int likeCount;
  final bool saved;
  final int commentCount;
  final int saveCount;
  final String? description;
  final bool synopsisOpen;
  final VoidCallback? onToggleSynopsis;
  final VoidCallback? onTitle;
  final VoidCallback? onRewards;
  final String coins;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final VoidCallback? onEpisodes;
  final VoidCallback? onFullscreen;
  final Widget? translation;
  final Widget? progress;

  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];

  @override
  Widget build(BuildContext context) {
    final desc = (description ?? '').trim();
    final synopsis = desc.isEmpty ? episodeTitle : desc;
    return Stack(fit: StackFit.expand, children: [
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, 0.3),
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xD9000000)],
            ),
          ),
        ),
      ),
      Align(
        alignment: const Alignment(0.97, -0.28),
        child: RewardCoinWidget(coins: coins, onTap: onRewards),
      ),
      Positioned(
        right: 4,
        bottom: 128,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PlayerRailButton(
            key: const ValueKey('player-save'),
            icon: Icons.star_rounded,
            color: saved ? AppColors.gold : Colors.white,
            label: _fmtCount(saveCount),
            onTap: onSave,
          ),
          const SizedBox(height: 14),
          PlayerRailButton(
            key: const ValueKey('player-comment'),
            icon: Icons.chat_bubble_rounded,
            label: _fmtCount(commentCount),
            onTap: onComment,
          ),
          const SizedBox(height: 14),
          PlayerRailButton(
            key: const ValueKey('player-like'),
            icon: Icons.favorite,
            color: liked ? const Color(0xFFFE2C55) : Colors.white,
            label: _fmtCount(likeCount),
            onTap: onLike,
          ),
          const SizedBox(height: 14),
          PlayerRailButton(
            key: const ValueKey('player-share'),
            icon: Icons.reply_rounded,
            mirror: true,
            label: 'Share',
            onTap: onShare,
          ),
        ]),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 8,
        child: Column(
          key: const ValueKey('player-info'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 60),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      GestureDetector(
                        key: const ValueKey('player-title'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onTitle,
                        child: Row(children: [
                          Flexible(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    shadows: _shadow)),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 20, color: Colors.white),
                        ]),
                      ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      key: const ValueKey('synopsis-toggle'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggleSynopsis,
                      child: synopsisOpen
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 110),
                              child: SingleChildScrollView(
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                        text: 'EP $episodeNo | $synopsis  '),
                                    const TextSpan(
                                        text: 'Less',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ]),
                                  key: const ValueKey('player-desc'),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.35,
                                      color: Colors.white70,
                                      shadows: _shadow),
                                ),
                              ),
                            )
                          : Row(children: [
                              Expanded(
                                child: Text('EP $episodeNo | $synopsis',
                                    key: const ValueKey('player-desc'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                        shadows: _shadow)),
                              ),
                              const SizedBox(width: 10),
                              const Text('More',
                                  key: ValueKey('synopsis-more'),
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      shadows: _shadow)),
                            ]),
                    ),
                    if (translation != null) translation!,
                    const SizedBox(height: 2),
                    const IgnorePointer(
                      child: Row(key: ValueKey('ai-note'), children: [
                        Icon(Icons.info_outline,
                            size: 12, color: Colors.white54),
                        SizedBox(width: 4),
                        Text('AI-generated content',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white54)),
                      ]),
                    ),
                  ]),
            ),
            if (progress != null) progress! else const SizedBox(height: 32),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('episodes-button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onEpisodes,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: const Color(0xFF26282B),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                            'Episodes · ${completed ? 'Completed' : 'Ongoing'} · All $total EPs',
                            key: const ValueKey('episodes-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('player-fullscreen'),
                onPressed: onFullscreen,
                icon:
                    const Icon(Icons.fullscreen, size: 28, color: Colors.white),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }

  static String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Reward widget: red-packet coin icon, wallet balance, small "Claim" pill.
class RewardCoinWidget extends StatelessWidget {
  const RewardCoinWidget({super.key, this.coins = '…', this.onTap});
  final String coins;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('reward-widget'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF5A3C), Color(0xFFD7261E)],
              ),
            ),
            child: const Icon(Icons.monetization_on,
                color: AppColors.gold, size: 30),
          ),
          Transform.translate(
            offset: const Offset(0, -6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(coins,
                  key: const ValueKey('reward-coins'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 3)])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Claim',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class PlayerRailButton extends StatelessWidget {
  const PlayerRailButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = Colors.white,
    this.mirror = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    Widget ic = Icon(icon, size: 34, color: color, shadows: const [
      Shadow(color: Color(0x66000000), blurRadius: 4),
    ]);
    if (mirror) ic = Transform.flip(flipX: true, child: ic);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ic,
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Color(0x99000000), blurRadius: 3),
                  ])),
        ]),
      ),
    );
  }
}

/// Top bar: back + "EP n" on the left, ⋮ more on the right.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({super.key, this.episodeNo, this.onBack, this.onMore});
  final int? episodeNo;
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Row(children: [
            IconButton(
              key: const ValueKey('player-back'),
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: onBack,
            ),
            if (episodeNo != null)
              Text('EP $episodeNo',
                  key: const ValueKey('top-ep'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0x99000000), blurRadius: 3),
                      ])),
            const Spacer(),
            IconButton(
              key: const ValueKey('player-more'),
              icon: const Icon(Icons.more_vert, size: 26),
              onPressed: onMore,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Binds [PlayerSeekBar] to a media_kit [Player].
class PlayerProgress extends StatelessWidget {
  const PlayerProgress({super.key, required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (_, pos) => StreamBuilder<Duration>(
        stream: player.stream.duration,
        initialData: player.state.duration,
        builder: (_, dur) => StreamBuilder<Duration>(
          stream: player.stream.buffer,
          initialData: player.state.buffer,
          builder: (_, buf) => PlayerSeekBar(
            position: pos.data ?? Duration.zero,
            duration: dur.data ?? Duration.zero,
            buffer: buf.data ?? Duration.zero,
            onSeek: (d) => player.seek(d),
          ),
        ),
      ),
    );
  }
}

String fmtDur(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Real playback progress (position/duration) with drag-to-seek.
/// 32dp touch area; claims horizontal AND vertical drags so dragging the bar
/// never swipes episodes, and has its own tap so it never toggles pause.
class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.buffer = Duration.zero,
  });
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final ValueChanged<Duration> onSeek;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _drag; // 0..1 while dragging

  double _frac(Duration d) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (d.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _update(Offset local, double width) {
    setState(() => _drag = (local.dx / width).clamp(0.0, 1.0));
  }

  void _end() {
    final f = _drag;
    setState(() => _drag = null);
    if (f == null || widget.duration <= Duration.zero) return;
    widget.onSeek(
        Duration(milliseconds: (f * widget.duration.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _drag != null;
    final value = _drag ?? _frac(widget.position);
    final shown = dragging
        ? Duration(
            milliseconds: (value * widget.duration.inMilliseconds).round())
        : widget.position;
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (dragging)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${fmtDur(shown)} / ${fmtDur(widget.duration)}',
                key: const ValueKey('seek-time'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
          ),
        GestureDetector(
          key: const ValueKey('player-seekbar'),
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // swallow so the tap layer doesn't pause
          onHorizontalDragStart: (d) => _update(d.localPosition, w),
          onHorizontalDragUpdate: (d) => _update(d.localPosition, w),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          onVerticalDragStart:
              (_) {}, // block PageView episode swipe on the bar
          onVerticalDragUpdate: (_) {},
          child: SizedBox(
            height: 32,
            width: w,
            child: Stack(alignment: Alignment.centerLeft, children: [
              Center(
                child: SizedBox(
                  height: dragging ? 6 : 3,
                  child: Stack(fit: StackFit.expand, children: [
                    const ColoredBox(color: Colors.white24),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _frac(widget.buffer),
                      child: const ColoredBox(color: Colors.white38),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: const ColoredBox(color: AppColors.primary),
                    ),
                  ]),
                ),
              ),
              Positioned(
                left: (value * w - (dragging ? 8 : 5))
                    .clamp(0.0, w - (dragging ? 16 : 10)),
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('seek-thumb'),
                    width: dragging ? 16 : 10,
                    height: dragging ? 16 : 10,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]);
    });
  }
}
