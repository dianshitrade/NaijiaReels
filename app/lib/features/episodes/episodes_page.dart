import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../player/demo_videos.dart';

class EpisodesPage extends StatelessWidget {
  const EpisodesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Episodes')),
      body: ListView.builder(
        itemCount: demoEpisodes.length,
        itemBuilder: (_, i) {
          final e = demoEpisodes[i];
          return ListTile(
            leading: e.coverUrl == null
                ? const Icon(Icons.movie)
                : CachedNetworkImage(imageUrl: e.coverUrl!, width: 48),
            title: Text(e.title),
            subtitle: Text('EP ${e.index + 1}'),
          );
        },
      ),
    );
  }
}
