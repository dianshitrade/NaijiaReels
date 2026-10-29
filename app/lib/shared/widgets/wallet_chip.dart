import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repository.dart';

class WalletChip extends ConsumerWidget {
  const WalletChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.monetization_on, color: AppColors.gold, size: 18),
        const SizedBox(width: 4),
        Text(
            w.when(
              data: (v) => '${v.balanceCoins}',
              loading: () => '…',
              error: (_, __) => '--',
            ),
            style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
