import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// Adaptive quality: start on the lowest rung (fast first frame), then
  /// measure real throughput on the top rung's first segment and switch the
  /// video track to the highest rung the link sustains. Rungs come from the
  /// master playlist (nothing hard-coded), so a new "original" rung is used
  /// automatically.
  Future<void> _upgradeHlsBitrate() async {
    if (_upgradedBitrate) return;
    _upgradedBitrate = true;
    final native = player.platform;
    if (native is! NativePlayer) return;
    try {
      await native.setProperty('hls-bitrate', 'max');
      final variants = await fetchHlsVariants(url);
      if (variants.isEmpty) return;
      debugPrint('[Quality] master rungs: '
          '${variants.map((v) => '${v.resolution ?? '?'}@${v.bandwidth ~/ 1000}k').join(', ')}');
      final top = variants.last;
      final bps = await measureThroughput(top.uri);
      final target = pickVariant(variants, bps);
      debugPrint('[Quality] measured ${bps ~/ 1000} kbps -> target '
          '${target.resolution ?? '?'}@${target.bandwidth ~/ 1000}k');
      final vids = player.state.tracks.video.where((t) => (t.h ?? 0) > 0).toList();
      debugPrint('[Quality] video tracks: ${vids.map((t) => '${t.id}:${t.w}x${t.h}@${t.bitrate}').toList()}');
      final th = target.height;
      VideoTrack? match;
      for (final t in vids) {
        if (th != null && t.h == th) match = t;
      }
      if (match == null && vids.isNotEmpty && th != null) {
        vids.sort((a, b) => (a.h! - th).abs().compareTo((b.h! - th).abs()));
        match = vids.first;
      }
      if (match != null && match.h != player.state.height) {
        debugPrint('[Quality] switch video track -> ${match.id} ${match.w}x${match.h}');
        await player.setVideoTrack(match);
      }
    } catch (e) {
      debugPrint('[Quality] upgrade failed: $e');
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
      if ((h ?? 0) > 0) {
        _markReady('height=$h');
        debugPrint('[Quality] now ${player.state.width}x$h url=$url');
      }
    }));
    _subs.add(player.stream.position.listen((pos) {
      if (pos > Duration.zero) _markReady('position=$pos');
    }));
    // NOTE: no "playing for 1s" fallback. mpv reports playing=true while it is
    // still waiting for the first HLS segment; dropping the poster then left a
    // pure black screen (root cause of the 03:06 black-screen report). Only a
    // decoded frame (width/height) or advancing position counts as ready.
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
  bool _fallbackReady = false;
  Timer? _fallbackTimer;

  /// What is currently applied (for tests/logs).
  String? get appliedSubtitle => _applied;

  Future<void> setSubtitleLang(String? lang) async {
    _subtitleLang = lang;
    await _applySubtitle();
  }

  /// Picks the HLS track for [subtitleLang]; if the player exposes none,
  /// loads the matching `subtitles[].url` WebVTT via [SubtitleTrack.uri].
  String? _hlsUsedFor; // language whose HLS rendition is active for this media
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
      // Switching HLS renditions mid-playback is unreliable in mpv/ffmpeg
      // (the newly selected rendition never delivers cues; seen on CI for
      // yo/fr/zh after en). So the HLS track is used for the language active
      // when the stream starts; a later switch to another language loads that
      // language's WebVTT directly when one exists.
      final midSwitch = _hlsUsedFor != null && _hlsUsedFor != lang && ext != null;
      if (hls != null && !midSwitch) {
        key = 'hls:${hls.id}';
        target = hls;
      } else if (ext != null && _tracksSeen && !_fallbackReady) {
        // HLS renditions are often listed a moment after the first track
        // event; give them a grace period before loading the external VTT.
        _fallbackTimer ??= Timer(const Duration(seconds: 3), () {
          _fallbackReady = true;
          unawaited(_applySubtitle());
        });
        return;
      } else if (ext != null && (_fallbackReady || midSwitch)) {
        key = 'uri:${ext.url}';
        target = SubtitleTrack.uri(ext.url, title: ext.label, language: lang);
      } else {
        return; // wait for the track list
      }
    }
    if (_applied == key) return;
    _applied = key;
    if (key.startsWith('hls:')) _hlsUsedFor ??= lang;
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
    _hlsUsedFor = null;
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
    // Lowest rung until first frame, then [_upgradeHlsBitrate].
    await native.setProperty('hls-bitrate', 'min');
    // Subtitles are off by default: never let mpv autoselect a track.
    if (_subtitleLang == null) await native.setProperty('sid', 'no');
    debugPrint('[Play] startup props: cache=no hls-bitrate=min url=$url');
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
    _fallbackTimer?.cancel();
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

/// One `#EXT-X-STREAM-INF` rung of an HLS master playlist.
class HlsVariant {
  const HlsVariant(this.bandwidth, this.resolution, this.uri);
  final int bandwidth;
  final String? resolution; // "720x1280"
  final String uri; // absolute
  int? get height => resolution == null ? null : int.tryParse(resolution!.split('x').last);
}

/// Parses rungs (sorted by bandwidth ascending), resolving relative URIs.
List<HlsVariant> parseHlsMaster(String body, String masterUrl) {
  final base = Uri.parse(masterUrl);
  final out = <HlsVariant>[];
  final lines = body.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (!l.startsWith('#EXT-X-STREAM-INF:')) continue;
    final bw = int.tryParse(RegExp(r'(?:^|[:,])BANDWIDTH=(\d+)').firstMatch(l)?.group(1) ?? '');
    final res = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(l)?.group(1);
    var j = i + 1;
    while (j < lines.length && (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
      j++;
    }
    if (bw == null || j >= lines.length) continue;
    var u = base.resolve(lines[j].trim());
    if (u.query.isEmpty && base.query.isNotEmpty) u = u.replace(query: base.query);
    out.add(HlsVariant(bw, res, u.toString()));
  }
  out.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
  return out;
}

/// Highest rung whose BANDWIDTH fits in 80% of [bps]; lowest if none fits.
HlsVariant pickVariant(List<HlsVariant> v, int bps) {
  var best = v.first;
  for (final x in v) {
    if (x.bandwidth <= bps * 0.8) best = x;
  }
  return best;
}

Future<String> _httpGet(String u, {int maxBytes = 1 << 20}) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final r = await (await c.getUrl(Uri.parse(u))).close().timeout(const Duration(seconds: 15));
    final b = BytesBuilder();
    await for (final chunk in r.timeout(const Duration(seconds: 15))) {
      b.add(chunk);
      if (b.length > maxBytes) break;
    }
    return utf8.decode(b.takeBytes(), allowMalformed: true);
  } finally {
    c.close(force: true);
  }
}

Future<List<HlsVariant>> fetchHlsVariants(String masterUrl) async =>
    parseHlsMaster(await _httpGet(masterUrl), masterUrl);

/// Downloads (up to ~3 MB of) the first media segment of [variantUrl] and
/// returns bits per second.
Future<int> measureThroughput(String variantUrl) async {
  final pl = await _httpGet(variantUrl);
  final base = Uri.parse(variantUrl);
  final seg = pl.split(RegExp(r'\r?\n')).map((l) => l.trim()).firstWhere(
      (l) => l.isNotEmpty && !l.startsWith('#'),
      orElse: () => '');
  if (seg.isEmpty) return 0;
  var u = base.resolve(seg);
  if (u.query.isEmpty && base.query.isNotEmpty) u = u.replace(query: base.query);
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final sw = Stopwatch()..start();
  var n = 0;
  try {
    final r = await (await c.getUrl(u)).close().timeout(const Duration(seconds: 15));
    await for (final chunk in r.timeout(const Duration(seconds: 15))) {
      n += chunk.length;
      if (n > 3 << 20) break;
    }
  } finally {
    c.close(force: true);
  }
  final ms = sw.elapsedMilliseconds.clamp(1, 1 << 30);
  return (n * 8 * 1000) ~/ ms;
}
