import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/storage/local_storage.dart';
import '../../data/repository.dart';
import '../home/discover_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final list = ref.watch(dramaListProvider);
    String id;
    try {
      id = LocalStorage.deviceId;
    } catch (_) {
      id = 'guest';
    }
    final shortId = id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Me', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push(Routes.settings)),
        ],
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person, size: 36, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Guest', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('ID $shortId', style: const TextStyle(color: AppColors.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(children: [
                    _stat(wallet.when(data: (w) => '${w.balanceCoins}', loading: () => '…', error: (_, __) => '--'),
                        'Coins', AppColors.gold),
                    _stat(wallet.when(data: (w) => '${w.bonusCoins}', loading: () => '…', error: (_, __) => '--'),
                        'Bonus', AppColors.gold),
                    _stat(list.maybeWhen(data: (l) => '${l.length}', orElse: () => '…'), 'My List',
                        AppColors.primary),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text('Continue Watching', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
        list.when(
          loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Text('Load failed: $e'))),
          data: (items) => SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 9 / 16),
              delegate: SliverChildBuilderDelegate((_, i) => DramaCard(items[i]), childCount: items.length),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String v, String label, Color c) => Expanded(
        child: Column(children: [
          Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}
