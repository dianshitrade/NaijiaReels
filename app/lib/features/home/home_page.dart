import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/wallet_chip.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const BrandLogo(fontSize: 22),
        actions: [
          const WalletChip(),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'All dramas',
            onPressed: () => context.push(Routes.dramas),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeProvider);
          ref.invalidate(walletProvider);
        },
        child: home.when(
          loading: () => const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading… (server may need ~1 min to wake up)'),
          ])),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(24), child: Text('Load failed: $e')),
          ]),
          data: (h) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final s in h.sections) _Section(s),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.section);
  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(section.title, style: Theme.of(context).textTheme.titleMedium),
      ),
      SizedBox(
        height: 230,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: section.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => DramaCard(section.items[i]),
        ),
      ),
    ]);
  }
}

class DramaCard extends StatelessWidget {
  const DramaCard(this.drama, {super.key});
  final Drama drama;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(Routes.dramaDetail(drama.id)),
      child: SizedBox(
        width: 112,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverImage(drama.coverUrl),
          const SizedBox(height: 4),
          Text(drama.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
