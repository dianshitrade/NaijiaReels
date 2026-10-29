import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../home/discover_page.dart';

class DramaListPage extends ConsumerWidget {
  const DramaListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(dramaListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('All dramas')),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Load failed: $e')),
        data: (items) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 9 / 16),
          itemCount: items.length,
          itemBuilder: (_, i) => DramaCard(items[i]),
        ),
      ),
    );
  }
}
