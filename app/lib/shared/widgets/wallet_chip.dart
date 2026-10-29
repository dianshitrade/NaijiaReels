import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repository.dart';

class WalletChip extends ConsumerWidget {
  const WalletChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Chip(
        avatar: const Icon(Icons.monetization_on, color: AppColors.gold, size: 18),
        label: Text(w.when(
          data: (v) => '${v.balanceCoins}',
          loading: () => '…',
          error: (_, __) => '--',
        )),
      ),
    );
  }
}
