import '../episodes/episode.dart';

/// Public placeholder streams used only to exercise the player (HLS + MP4).
const demoEpisodes = <Episode>[
  Episode(
    id: 'demo-1',
    title: 'Demo 1 (HLS)',
    videoUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    index: 0,
  ),
  Episode(
    id: 'demo-2',
    title: 'Demo 2 (MP4)',
    videoUrl:
        'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    index: 1,
  ),
  Episode(
    id: 'demo-3',
    title: 'Demo 3 (MP4)',
    videoUrl:
        'https://test-videos.co.uk/vids/jellyfish/mp4/h264/360/Jellyfish_360_10s_1MB.mp4',
    index: 2,
  ),
];
