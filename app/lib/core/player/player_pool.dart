import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'subtitle_select.dart';

/// One media_kit player bound to a source URL (HLS .m3u8 or MP4).
class PooledPlayer {
  PooledPlayer._(this.url) : player = Player() {
    controller = VideoController(player);
  }

  final String url;
  final Player player;

  /// True once a real frame is decoded (width>0 or position>0).
  final ValueNotifier<bool> ready = ValueNotifier(false);

  /// Non-null when playback failed (open error, mpv error with no frame,
  /// or no first frame within [firstFrameTimeout]).
  final ValueNotifier<String?> failure = ValueNotifier(null);
  static Duration firstFrameTimeout = const Duration(seconds: 60);
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _timeout;
  Timer? _errGrace;
  Timer? _playingFallback;
  String? lastError;

  void _markReady(String why) {
    if (ready.value) return;
    ready.value = true;
    failure.value = null;
    _timeout?.cancel();
    _errGrace?.cancel();
    _playingFallback?.cancel();
    debugPrint('[Play] ready ($why) ${_sw.elapsedMilliseconds}ms url=$url');
  }

  void _fail(String msg) {
    if (ready.value || failure.value != null) return;
    debugPrint('[Play] FAIL "$msg" state: playing=${player.state.playing} '
        'buffering=${player.state.buffering} w=${player.state.width} '
        'pos=${player.state.position} dur=${player.state.duration} url=$url');
    failure.value = msg;
  }

  void _watchHealth() {
    // Seed from current state (events may have already fired).
    if ((player.state.width ?? 0) > 0) _markReady('seed-width=${player.state.width}');
    if (player.state.position > Duration.zero) {
      _markReady('seed-position=${player.state.position}');
    }
    _subs.add(player.stream.width.listen((w) {
      if ((w ?? 0) > 0) _markReady('width=$w');
    }));
    _subs.add(player.stream.height.listen((h) {
      if ((h ?? 0) > 0) _markReady('height=$h');
    }));
    _subs.add(player.stream.position.listen((pos) {
      if (pos > Duration.zero) _markReady('position=$pos');
    }));
    // Safety net for devices where width/height never fire but playback works:
    // if playing continuously for >=1s, drop the poster.
    DateTime? playingSince;
    _subs.add(player.stream.playing.listen((playing) {
      if (playing) {
        playingSince ??= DateTime.now();
        final elapsed = DateTime.now().difference(playingSince!);
        if (elapsed >= const Duration(seconds: 1)) {
          _markReady('playing>${elapsed.inMilliseconds}ms');
        } else {
          _playingFallback?.cancel();
          _playingFallback = Timer(
            const Duration(seconds: 1) - elapsed,
            () {
              if (player.state.playing) _markReady('playing>=1s');
            },
          );
        }
      } else {
        playingSince = null;
        _playingFallback?.cancel();
      }
    }));
    if (player.state.playing) {
      _playingFallback = Timer(const Duration(seconds: 1), () {
        if (player.state.playing) _markReady('seed-playing>=1s');
      });
    }
    _subs.add(player.stream.error.listen((e) {
      debugPrint('[Play] mpv error: $e url=$url');
      lastError = e;
      _errGrace?.cancel();
      _errGrace = Timer(const Duration(seconds: 10), () => _fail('Playback error: $e'));
    }));
    _subs.add(player.stream.log.listen((l) {
      if (l.level == 'error' || l.level == 'fatal') {
        debugPrint('[Play] mpv ${l.level} ${l.prefix}: ${l.text.trim()}');
      }
    }));
    _timeout = Timer(firstFrameTimeout, () => _fail(lastError != null
        ? 'Playback error: $lastError'
        : 'Video took too long to start. Check your network and retry.'));
  }
  late final VideoController controller;
  final Stopwatch _sw = Stopwatch();
  StreamSubscription<int?>? _firstFrameSub;
  Duration? firstFrame;
  StreamSubscription<Tracks>? _tracksSub;
  String? _pickedSubId;

  /// Each player selects its own subtitle track whenever its track list
  /// changes (initial open, re-open after unlock), so tracks never leak
  /// between pooled episodes.
  void _watchSubtitles() {
    _tracksSub?.cancel();
    _pickedSubId = null;
    _tracksSub = player.stream.tracks.listen((tracks) async {
      final pick = pickSubtitleTrack(tracks.subtitle);
      final cur = player.state.track.subtitle;
      debugPrint('[Subs] url=$url tracks.subtitle='
          '${tracks.subtitle.map((t) => '${t.id}/${t.language}/${t.title}').toList()} '
          'current=${cur.id} pick=${pick?.id}/${pick?.language}');
      if (pick == null || (cur.id == pick.id && _pickedSubId == pick.id)) return;
      _pickedSubId = pick.id;
      await player.setSubtitleTrack(pick);
      debugPrint('[Subs] selected ${pick.id}/${pick.language} url=$url');
    });
  }

  Future<void> _open({required bool play}) async {
    _sw.start();
    _watchHealth();
    _firstFrameSub = player.stream.width.listen((w) {
      if (w != null && w > 0 && firstFrame == null) {
        firstFrame = _sw.elapsed;
        _sw.stop();
        debugPrint('[PlayerPool] first frame ${firstFrame!.inMilliseconds}ms '
            'url=$url');
        _firstFrameSub?.cancel();
      }
    });
    _watchSubtitles();
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('slang', 'en,eng');
      await native.setProperty('sub-auto', 'fuzzy');
    }
    await player.setPlaylistMode(PlaylistMode.single);
    try {
      await player.open(Media(url), play: play);
      debugPrint('[Play] open returned ${_sw.elapsedMilliseconds}ms url=$url');
    } catch (e) {
      debugPrint('[Play] open threw $e url=$url');
      _fail('Could not open video: $e');
    }
  }

  Future<void> dispose() async {
    await _firstFrameSub?.cancel();
    await _tracksSub?.cancel();
    _timeout?.cancel();
    _errGrace?.cancel();
    _playingFallback?.cancel();
    ready.dispose();
    failure.dispose();
    for (final x in _subs) {
      await x.cancel();
    }
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

  /// Drop a (failed) player so the next obtain re-opens from scratch.
  Future<void> remove(String url) async {
    final p = _players.remove(url);
    await p?.dispose();
  }

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
