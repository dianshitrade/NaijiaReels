import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../data/mock/mock_api.dart';
import '../../data/models.dart';
import '../../shared/widgets/ankara_pattern.dart';

/// "05:29:59" until [end]; "00:00:00" once passed.
String countdownText(DateTime end, DateTime now) {
  var d = end.difference(now);
  if (d.isNegative) d = Duration.zero;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Shop tab: coin packs + VIP in ₦ (GET /shop/packages, POST /orders, poll GET /orders/{id}).
class ShopPage extends ConsumerStatefulWidget {
  const ShopPage({super.key, this.pollInterval = const Duration(seconds: 1)});
  final Duration pollInterval;
  @override
  ConsumerState<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends ConsumerState<ShopPage> {
  Timer? _tick;
  DateTime _now = DateTime.now();
  String? _buying;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _buy(ShopPackage p) async {
    if (_buying != null) return;
    setState(() => _buying = p.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final o = await ref.read(mockApiProvider).buyAndPoll(p.id, interval: widget.pollInterval);
      messenger.showSnackBar(SnackBar(
          content: Text(o.status == 'paid'
              ? (p.isVip ? '${p.title} activated. Enjoy!' : '${o.coins} coins added. Oya, enjoy!')
              : 'Payment ${o.status}. Check My orders.')));
      ref.invalidate(shopPackagesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not start payment. Try again.')));
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('shop-page'),
      appBar: AppBar(title: const Text('Shop', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Stack(children: [
        const Positioned.fill(child: TextilePattern(opacity: .05)),
        ref.watch(shopPackagesProvider).when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(shopPackagesProvider), child: const Text('Tap to retry'))),
              data: _body,
            ),
      ]),
    );
  }

  Widget _body(List<ShopPackage> all) {
    final offers = all.where((p) => p.tag != null).toList();
    final coins = all.where((p) => p.tag == null && !p.isVip).toList();
    final vip = all.where((p) => p.tag == null && p.isVip).toList();
    return ListView(key: const ValueKey('shop-list'), padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
      _QuickRow(onTap: (k) => _open(k)),
      const SizedBox(height: 14),
      for (final o in offers) ...[
        _OfferCard(p: o, now: _now, busy: _buying == o.id, onBuy: () => _buy(o)),
        const SizedBox(height: 12)
      ],
      if (kUseMocks)
        const Padding(
          key: ValueKey('shop-placeholder-note'),
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Sample prices · placeholder only, final ₦ prices coming soon',
              style: TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic)),
        ),
      _section('Coin packs', Icons.monetization_on),
      _grid([for (final p in coins) _PackCard(p: p, busy: _buying == p.id, onBuy: () => _buy(p))]),
      const SizedBox(height: 16),
      _section('VIP passes', Icons.workspace_premium),
      _grid([for (final p in vip) _PackCard(p: p, busy: _buying == p.id, onBuy: () => _buy(p))]),
      const SizedBox(height: 12),
      const Text('Payments secured by Paystack.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }

  Widget _section(String t, IconData i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(i, color: AppColors.gold, size: 20),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _grid(List<Widget> c) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.25,
        children: c,
      );

  void _open(String k) {
    final Widget page = switch (k) {
      'orders' => const _OrdersPage(),
      'coupons' => const _CouponsPage(),
      _ => const _WalletPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.onTap});
  final void Function(String) onTap;
  @override
  Widget build(BuildContext context) {
    Widget b(String k, IconData i, String l) => Expanded(
          child: InkWell(
            key: ValueKey('shop-$k'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(k),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Icon(i, color: AppColors.primary, size: 26),
                const SizedBox(height: 4),
                Text(l, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        b('orders', Icons.receipt_long_outlined, 'My orders'),
        b('coupons', Icons.confirmation_number_outlined, 'Coupons'),
        b('wallet', Icons.account_balance_wallet_outlined, 'Wallet'),
      ]),
    );
  }
}

Widget _price(ShopPackage p, {double size = 20}) => Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
      Text(formatNaira(p.amountKobo),
          style: TextStyle(color: AppColors.gold, fontSize: size, fontWeight: FontWeight.w900)),
      if (p.originalAmountKobo != null) ...[
        const SizedBox(width: 6),
        Text(formatNaira(p.originalAmountKobo!),
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, decoration: TextDecoration.lineThrough)),
      ],
    ]);

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.p, required this.now, required this.busy, required this.onBuy});
  final ShopPackage p;
  final DateTime now;
  final bool busy;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    final first = p.tag == 'first_recharge';
    final off = p.originalAmountKobo == null ? 0 : (100 - p.amountKobo * 100 ~/ p.originalAmountKobo!);
    return Container(
      key: ValueKey('offer-${p.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: .55)),
        gradient: LinearGradient(colors: [AppColors.greenDark, AppColors.surfaceHigh.withValues(alpha: .95)]),
      ),
      child: Stack(children: [
        const Positioned.fill(child: TextilePattern(opacity: .08)),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
                    child: Text(first ? 'FIRST TOP-UP' : 'LIMITED',
                        style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                  if (off > 0) ...[
                    const SizedBox(width: 6),
                    Text('-$off%', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  ],
                ]),
                const SizedBox(height: 6),
                Text(p.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                    p.isVip
                        ? '${p.vipDays} days ad-free, all episodes unlocked'
                        : '${p.coins} coins + ${p.bonusCoins} bonus',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                _price(p, size: 22),
                if (p.endsAt != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.timer_outlined, size: 15, color: AppColors.gold),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('Ends in ${countdownText(p.endsAt!, now)}',
                          key: ValueKey('countdown-${p.id}'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.gold, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ],
              ]),
            ),
            FilledButton(
              key: ValueKey('buy-${p.id}'),
              onPressed: busy ? null : onBuy,
              style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Buy now', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.p, required this.busy, required this.onBuy});
  final ShopPackage p;
  final bool busy;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('pack-${p.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onBuy,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(p.isVip ? Icons.workspace_premium : Icons.monetization_on, color: AppColors.gold, size: 22),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(p.isVip ? p.title : '${p.coins}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            ]),
            const SizedBox(height: 4),
            Text(p.isVip ? '${p.vipDays} days VIP' : (p.bonusCoins > 0 ? '+${p.bonusCoins} bonus' : 'coins'),
                style: TextStyle(color: p.isVip ? Colors.white70 : AppColors.primary, fontSize: 13)),
            const Spacer(),
            busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
                : _price(p, size: 18),
          ]),
        ),
      ),
    );
  }
}

class _OrdersPage extends ConsumerWidget {
  const _OrdersPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('My orders')),
        body: FutureBuilder<List<ShopOrder>>(
          future: ref.read(mockApiProvider).orders(),
          builder: (_, s) {
            final l = s.data ?? const [];
            if (l.isEmpty) return const Center(child: Text('No orders yet', style: TextStyle(color: AppColors.muted)));
            return ListView(children: [
              for (final o in l)
                ListTile(
                  title: Text(o.productId),
                  subtitle: Text(o.status),
                  trailing: Text(formatNaira(o.amountKobo), style: const TextStyle(color: AppColors.gold)),
                ),
            ]);
          },
        ),
      );
}

class _CouponsPage extends ConsumerWidget {
  const _CouponsPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Coupons')),
        body: ref.watch(couponsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (_, __) => const Center(child: Text('Could not load coupons')),
              data: (l) => l.isEmpty
                  ? const Center(child: Text('No coupons yet', style: TextStyle(color: AppColors.muted)))
                  : ListView(children: [
                      for (final c in l)
                        ListTile(
                          key: ValueKey('coupon-${c.id}'),
                          leading: const Icon(Icons.confirmation_number, color: AppColors.gold),
                          title: Text(c.title),
                          subtitle: Text(
                              'Min ${formatNaira(c.minAmountKobo)} · expires ${c.expiresAt.toLocal().toString().substring(0, 10)}'),
                        ),
                    ]),
            ),
      );
}

class _WalletPage extends StatelessWidget {
  const _WalletPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wallet')),
        body: const Center(
            child: Text('Coin balance and history live in Rewards for now.', style: TextStyle(color: AppColors.muted))),
      );
}
