import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/core/player/player_pool.dart';

void main() {
  const master = '''#EXTM3U
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",URI="subs/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=720x1280,SUBTITLES="subs"
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=360x640,SUBTITLES="subs"
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1080x1920,SUBTITLES="subs"
orig/index.m3u8
''';
  test('parses rungs from master (no hard-coding), sorted, resolved', () {
    final v = parseHlsMaster(master, 'https://m.example/hls/ep1/master.m3u8?t=1');
    expect(v.map((e) => e.height), [640, 1280, 1920]);
    expect(v.last.uri, 'https://m.example/hls/ep1/orig/index.m3u8?t=1');
  });
  test('picks highest rung within 80% of throughput', () {
    final v = parseHlsMaster(master, 'https://m.example/master.m3u8');
    expect(pickVariant(v, 500000).height, 640);
    expect(pickVariant(v, 3100000).height, 1280);
    expect(pickVariant(v, 20000000).height, 1920);
  });
}
