import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/player/player_pool.dart';
import 'demo_videos.dart';

/// Vertical PageView feed to validate the player + preload pool.
class DemoFeedPage extends StatefulWidget {
  const DemoFeedPage({super.key});

  @override
  State<DemoFeedPage> createState() => _DemoFeedPageState();
}

class _DemoFeedPageState extends State<DemoFeedPage> {
  final _pool = PlayerPool(maxPlayers: 3);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _focus(0);
  }

  Future<void> _focus(int i) async {
    final next = i + 1 < demoEpisodes.length ? demoEpisodes[i + 1].videoUrl : null;
    await _pool.focus(demoEpisodes[i].videoUrl, next: next);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pool.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: demoEpisodes.length,
        onPageChanged: (i) {
          _index = i;
          _focus(i);
        },
        itemBuilder: (_, i) {
          final ep = demoEpisodes[i];
          final pooled = _pool.get(ep.videoUrl);
          return Stack(fit: StackFit.expand, children: [
            if (pooled != null)
              Video(
                controller: pooled.controller,
                fit: BoxFit.cover,
                controls: NoVideoControls,
              )
            else
              const Center(child: CircularProgressIndicator()),
            Positioned(
              left: 16,
              bottom: 48,
              child: Text(
                '${ep.title}  ${i == _index ? "▶" : ""}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
