import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/repository.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/episode_cover.dart';
import '../../shared/widgets/wallet_chip.dart';

class DramaDetailPage extends ConsumerWidget {
  const DramaDetailPage({super.key, required this.dramaId});
  final String dramaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(dramaDetailProvider(dramaId));
    return Scaffold(
      appBar: AppBar(actions: const [WalletChip()]),
      body: d.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Load failed: $e')),
        data: (drama) => ListView(padding: const EdgeInsets.all(16), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: CoverImage(drama.coverUrl, title: drama.title)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(drama.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('${drama.episodeCount} episodes · ${drama.tags.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  onPressed: () => context.push(Routes.play(drama.id, 0)),
                ),
              ]),
            ),
          ]),
          if (drama.description != null) ...[
            const SizedBox(height: 16),
            Text(drama.description!),
          ],
          const SizedBox(height: 16),
          SeasonedEpisodeGrid(
            episodes: drama.episodes,
            dramaCoverUrl: drama.coverUrl,
            dramaTitle: drama.title,
            onTap: (i) => context.push(Routes.play(drama.id, i)),
          ),
        ]),
      ),
    );
  }
}
