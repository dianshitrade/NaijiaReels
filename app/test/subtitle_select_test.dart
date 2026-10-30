import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:naija_reels/core/player/subtitle_select.dart';

void main() {
  test('picks en track over others and pseudo tracks', () {
    final tracks = [
      SubtitleTrack.auto(),
      SubtitleTrack.no(),
      const SubtitleTrack('1', 'Yoruba', 'yo'),
      const SubtitleTrack('2', 'English', 'en'),
    ];
    expect(pickSubtitleTrack(tracks)?.id, '2');
  });
  test('falls back to English title, then first real track', () {
    expect(pickSubtitleTrack([SubtitleTrack.auto(), const SubtitleTrack('3', 'Pidgin', null),
      const SubtitleTrack('4', 'Main', null, isDefault: true)])?.id, '4');
    expect(pickSubtitleTrack([SubtitleTrack.no(), const SubtitleTrack('5', null, 'fr')])?.id, '5');
  });
  test('null when only auto/no', () {
    expect(pickSubtitleTrack([SubtitleTrack.auto(), SubtitleTrack.no()]), isNull);
    expect(pickSubtitleTrack(const []), isNull);
  });
}
