import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/wallet_chip.dart';

const kCategories = ['For You', 'Romance', 'Revenge', 'Royal', 'Family', 'CEO', 'Village'];

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});
  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const SizedBox(height: 28, child: BrandLogo(fontSize: 22)),
        actions: [
          const WalletChip(),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'All dramas',
            onPressed: () => context.push(Routes.dramas),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
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
          data: (h) => CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _chips()),
            ..._sectionsFor(h),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      ),
    );
  }

  Widget _chips() => SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: kCategories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ChoiceChip(
            label: Text(kCategories[i]),
            selected: _cat == i,
            showCheckmark: false,
            labelStyle: TextStyle(
                color: _cat == i ? Colors.white : AppColors.muted, fontWeight: FontWeight.w600),
            onSelected: (_) => setState(() => _cat = i),
          ),
        ),
      );

  List<Widget> _sectionsFor(HomeData h) {
    final cat = kCategories[_cat].toLowerCase();
    bool keep(Drama d) => _cat == 0 || d.tags.any((t) => t.toLowerCase().contains(cat));
    final popular = <Drama>[];
    final latest = <Drama>[];
    final seen = <String>{};
    for (var i = 0; i < h.sections.length; i++) {
      for (final d in h.sections[i].items.where(keep)) {
        if (seen.add(d.id)) (i == 0 ? popular : latest).add(d);
      }
    }
    final popularTitle = h.sections.isNotEmpty ? h.sections.first.title : 'Popular';
    return [
      if (popular.isNotEmpty) ...[
        _header('Popular', popularTitle),
        _grid(popular),
      ],
      if (latest.isNotEmpty) ...[
        _header('Latest', h.sections.length > 1 ? h.sections[1].title : 'New'),
        _grid(latest),
      ],
      if (popular.isEmpty && latest.isEmpty)
        const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No dramas in this category yet')))),
    ];
  }

  Widget _header(String title, String sub) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Flexible(
                child: Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          ]),
        ),
      );

  Widget _grid(List<Drama> items) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 9 / 16,
          ),
          delegate: SliverChildBuilderDelegate((_, i) => DramaCard(items[i]), childCount: items.length),
        ),
      );
}

/// 9:16 rounded poster with title overlay.
class DramaCard extends StatelessWidget {
  const DramaCard(this.drama, {super.key});
  final Drama drama;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(Routes.dramaDetail(drama.id)),
      child: Stack(fit: StackFit.expand, children: [
        CoverImage(drama.coverUrl, title: drama.title, radius: 14, showFallbackTitle: false),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xDD000000)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(drama.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text('${drama.episodeCount} EPs${drama.tags.isEmpty ? '' : ' · ${drama.tags.first}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
        if (drama.episodeCount > 0)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
              child: const Text('HOT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}
