import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../core/player/player_pool.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
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

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
  }

  Future<void> _load() async {
    final d = await ref.read(dramaDetailProvider(widget.dramaId).future);
    if (!mounted) return;
    setState(() => _episodes = d.episodes);
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
      await _pool.focus(cur.url!, next: nextUrl);
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

  @override
  void dispose() {
    _pool.disposeAll();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, actions: const [WalletChip()]),
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
      content = Center(child: Text('Error: ${st!.error}'));
    } else if (pooled != null) {
      content = Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Video(controller: pooled.controller, fit: BoxFit.cover, controls: NoVideoControls),
        ),
      );
    } else {
      content = const Center(child: CircularProgressIndicator());
    }
    return Stack(fit: StackFit.expand, children: [
      content,
      Positioned(
        left: 16,
        bottom: 40,
        child: Text('EP ${ep.episodeNo} · ${ep.title}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}
