import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/models.dart';
import 'subtitle_select.dart';

/// One media_kit player bound to a source URL (HLS .m3u8 or MP4).
class PooledPlayer {
  PooledPlayer._(this.url)
      : player = Player(
          configuration: const PlayerConfiguration(
            // Default 32MB demuxer cache delays first frame on slow links.
            bufferSize: 4 * 1024 * 1024,
            logLevel: MPVLogLevel.warn,
          ),
        ) {
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
  bool _upgradedBitrate = false;

  void _markReady(String why) {
    if (ready.value) return;
    ready.value = true;
    failure.value = null;
    _timeout?.cancel();
    _errGrace?.cancel();
    _playingFallback?.cancel();
    debugPrint('[Play] ready ($why) ${_sw.elapsedMilliseconds}ms url=$url');
    // After first frame at low HLS rung, allow 720p upgrade.
    unawaited(_upgradeHlsBitrate());
  }

  Future<void> _upgradeHlsBitrate() async {
    if (_upgradedBitrate) return;
    _upgradedBitrate = true;
    final native = player.platform;
    if (native is! NativePlayer) return;
    try {
      // "no" = unlimited → mpv may switch to higher HLS variant (720p).
      await native.setProperty('hls-bitrate', 'no');
      debugPrint('[Play] hls-bitrate upgraded to unlimited url=$url');
    } catch (e) {
      debugPrint('[Play] hls-bitrate upgrade failed: $e');
    }
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
      if (l.level == 'error' || l.level == 'fatal' || l.level == 'warn') {
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

  /// External WebVTT files from /play (fallback when HLS tracks are missing).
  List<SubtitleRef> subtitles = const [];

  /// Desired subtitle language for THIS player; null = subtitles off.
  String? get subtitleLang => _subtitleLang;
  String? _subtitleLang;
  String? _applied; // 'off' | 'hls:<id>' | 'uri:<url>'
  bool _tracksSeen = false;

  /// What is currently applied (for tests/logs).
  String? get appliedSubtitle => _applied;

  Future<void> setSubtitleLang(String? lang) async {
    _subtitleLang = lang;
    await _applySubtitle();
  }

  /// Picks the HLS track for [subtitleLang]; if the player exposes none,
  /// loads the matching `subtitles[].url` WebVTT via [SubtitleTrack.uri].
  Future<void> _applySubtitle() async {
    final lang = _subtitleLang;
    final tracks = player.state.tracks.subtitle;
    String key;
    SubtitleTrack target;
    if (lang == null) {
      key = 'off';
      target = SubtitleTrack.no();
    } else {
      final hls = pickSubtitleTrackForLang(tracks, lang);
      final ext = subtitles.where((s) => s.lang == lang).firstOrNull;
      if (hls != null) {
        key = 'hls:${hls.id}';
        target = hls;
      } else if (ext != null && _tracksSeen) {
        key = 'uri:${ext.url}';
        target = SubtitleTrack.uri(ext.url, title: ext.label, language: lang);
      } else {
        return; // wait for the track list
      }
    }
    if (_applied == key) return;
    _applied = key;
    debugPrint('[Subs] apply $key lang=$lang url=$url');
    try {
      await player.setSubtitleTrack(target);
    } catch (e) {
      debugPrint('[Subs] apply failed $e');
      _applied = null;
    }
  }

  /// Each player re-applies ITS OWN language whenever its track list changes
  /// (initial open, re-open after unlock), so tracks never leak between
  /// pooled episodes.
  void _watchSubtitles() {
    _tracksSub?.cancel();
    _applied = null;
    _tracksSub = player.stream.tracks.listen((tracks) async {
      _tracksSeen = true;
      debugPrint('[Subs] url=$url tracks.subtitle='
          '${tracks.subtitle.map((t) => '${t.id}/${t.language}/${t.title}').toList()} '
          'want=$_subtitleLang applied=$_applied');
      await _applySubtitle();
    });
  }

  Future<void> _applyStartupProps() async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    // media_kit defaults cache-on-disk=yes; without a writable cache-dir
    // lavf logs "Failed to create file cache" and can stall start.
    await native.setProperty('cache', 'no');
    await native.setProperty('cache-on-disk', 'no');
    // Prefer ~360p (master lists 1Mbps) until first frame, then upgrade.
    await native.setProperty('hls-bitrate', '1100000');
    // Subtitles are off by default: never let mpv autoselect a track.
    if (_subtitleLang == null) await native.setProperty('sid', 'no');
    debugPrint('[Play] startup props: cache=no hls-bitrate=1100000 url=$url');
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
    await _applyStartupProps();
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

  /// Subtitle language applied to every player (null = off).
  String? subtitleLang;

  /// External VTT lists keyed by stream url (set before [focus]/[obtain]).
  final Map<String, List<SubtitleRef>> subtitlesFor = {};

  Future<void> setSubtitleLang(String? lang) async {
    subtitleLang = lang;
    for (final p in _players.values) {
      await p.setSubtitleLang(lang);
    }
  }

  Future<PooledPlayer> obtain(String url, {bool play = false}) async {
    final existing = _players.remove(url);
    if (existing != null) {
      _players[url] = existing; // move to MRU
      existing.subtitles = subtitlesFor[url] ?? existing.subtitles;
      if (existing.subtitleLang != subtitleLang) await existing.setSubtitleLang(subtitleLang);
      return existing;
    }
    final p = PooledPlayer._(url)
      ..subtitles = subtitlesFor[url] ?? const []
      .._subtitleLang = subtitleLang;
    _players[url] = p;
    await _evict();
    await p._open(play: play);
    return p;
  }

  /// Activate [current] (play) and preload [next] (paused); pause others.
  Future<PooledPlayer> focus(String current, {String? next}) async {
    final cur = await obtain(current, play: true);
    if (next != null) {
      // Preload next while current plays — open paused so first swipe is warm.
      debugPrint('[PlayerPool] preload next=$next');
      await obtain(next);
    }
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
