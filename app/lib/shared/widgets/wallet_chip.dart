import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repository.dart';

class WalletChip extends ConsumerWidget {
  const WalletChip({super.key, this.tappable = false});
  final bool tappable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    final balance = w.when(
      data: (v) => '${v.balanceCoins}',
      loading: () => '…',
      error: (_, __) => '--',
    );
    final child = Container(
      key: const ValueKey('wallet-chip'),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.monetization_on, color: AppColors.gold, size: 18),
        const SizedBox(width: 4),
        Text(balance,
            style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
      ]),
    );
    if (!tappable) return child;
    return InkWell(
      key: const ValueKey('wallet-chip-button'),
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF1A1A1A),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.monetization_on, color: AppColors.gold, size: 40),
                const SizedBox(height: 8),
                Text('Balance: $balance coins', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Top-up coming soon', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
              ]),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
