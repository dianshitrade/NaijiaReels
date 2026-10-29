import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One media_kit player bound to a source URL (HLS .m3u8 or MP4).
class PooledPlayer {
  PooledPlayer._(this.url) : player = Player() {
    controller = VideoController(player);
  }

  final String url;
  final Player player;
  late final VideoController controller;
  final Stopwatch _sw = Stopwatch();
  StreamSubscription<int?>? _firstFrameSub;
  Duration? firstFrame;

  Future<void> _open({required bool play}) async {
    _sw.start();
    _firstFrameSub = player.stream.width.listen((w) {
      if (w != null && w > 0 && firstFrame == null) {
        firstFrame = _sw.elapsed;
        _sw.stop();
        debugPrint('[PlayerPool] first frame ${firstFrame!.inMilliseconds}ms '
            'url=$url');
        _firstFrameSub?.cancel();
      }
    });
    await player.setPlaylistMode(PlaylistMode.single);
    await player.open(Media(url), play: play);
  }

  Future<void> dispose() async {
    await _firstFrameSub?.cancel();
    await player.dispose();
  }
}

/// Keeps current + next episode loaded; never holds more than [maxPlayers].
/// Least recently used players beyond the limit are disposed.
class PlayerPool {
  PlayerPool({this.maxPlayers = 3});

  final int maxPlayers;
  final LinkedHashMap<String, PooledPlayer> _players = LinkedHashMap();

  int get size => _players.length;
  bool contains(String url) => _players.containsKey(url);

  Future<PooledPlayer> obtain(String url, {bool play = false}) async {
    final existing = _players.remove(url);
    if (existing != null) {
      _players[url] = existing; // move to MRU
      return existing;
    }
    final p = PooledPlayer._(url);
    _players[url] = p;
    await _evict();
    await p._open(play: play);
    return p;
  }

  /// Activate [current] (play) and preload [next] (paused); pause others.
  Future<PooledPlayer> focus(String current, {String? next}) async {
    final cur = await obtain(current, play: true);
    if (next != null) await obtain(next);
    // make sure current stays MRU
    _players.remove(current);
    _players[current] = cur;
    await _evict();
    for (final p in _players.values) {
      if (p.url == current) {
        await p.player.play();
      } else {
        await p.player.pause();
      }
    }
    return cur;
  }

  PooledPlayer? get(String url) => _players[url];

  Future<void> pauseAll() async {
    for (final p in _players.values) {
      await p.player.pause();
    }
  }

  Future<void> _evict() async {
    while (_players.length > maxPlayers) {
      final oldestKey = _players.keys.first;
      final p = _players.remove(oldestKey);
      debugPrint('[PlayerPool] dispose $oldestKey');
      await p?.dispose();
    }
  }

  Future<void> disposeAll() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
  }
}
