import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../data/mock/mock_api.dart';
import '../../data/models.dart';
import '../../shared/widgets/ankara_pattern.dart';
import '../shop/shop_page.dart' show countdownText;

/// Rewards tab: GET /rewards/summary + POST /rewards/{taskId}/claim (mocked).
/// 40903 on claim means "already claimed" and is shown as claimed, not an error.
class RewardsPage extends ConsumerStatefulWidget {
  const RewardsPage({super.key});
  @override
  ConsumerState<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends ConsumerState<RewardsPage> {
  final Set<String> _claimedLocal = {};
  String? _busy;
  Timer? _tick;
  DateTime _now = DateTime.now();

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

  bool _isClaimed(String? id, String status) => status == 'claimed' || (id != null && _claimedLocal.contains(id));

  Future<void> _claim(String taskId) async {
    if (_busy != null) return;
    setState(() => _busy = taskId);
    final m = ScaffoldMessenger.of(context);
    try {
      final r = await ref.read(mockApiProvider).claimReward(taskId);
      _claimedLocal.add(taskId);
      m.showSnackBar(
          SnackBar(duration: const Duration(seconds: 2), content: Text('+${r['rewardCoins']} coins. Nice one!')));
      ref.invalidate(rewardsSummaryProvider);
    } on ApiException catch (e) {
      if (e.code == kErrAlreadyClaimed) {
        _claimedLocal.add(taskId); // treat as claimed
        ref.invalidate(rewardsSummaryProvider);
      } else {
        m.showSnackBar(const SnackBar(content: Text('Could not claim right now. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rewards', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Stack(children: [
        const Positioned.fill(child: TextilePattern(opacity: .05)),
        ref.watch(rewardsSummaryProvider).when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(rewardsSummaryProvider), child: const Text('Tap to retry'))),
              data: _body,
            ),
      ]),
    );
  }

  Widget _claimBtn(String? taskId, String status, {String label = 'Claim'}) {
    final done = _isClaimed(taskId, status);
    if (done) {
      return const OutlinedButton(onPressed: null, child: Text('Claimed'));
    }
    final can = status == 'claimable' && taskId != null;
    return FilledButton(
      key: taskId == null ? null : ValueKey('claim-$taskId'),
      onPressed: can && _busy == null ? () => _claim(taskId) : null,
      style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.muted),
      child: _busy == taskId && taskId != null
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _body(RewardsSummary s) {
    return ListView(key: const ValueKey('rewards-list'), padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
      _balances(s),
      const SizedBox(height: 14),
      if (s.newbie7Day != null) ...[
        _card('New here? 7-day welcome gift', Icons.card_giftcard, _days(s.newbie7Day!, 'newbie'),
            key: 'rewards-newbie'),
        const SizedBox(height: 12),
      ],
      _card('Daily check-in · ${s.checkinStreak}-day streak', Icons.event_available, _days(s.checkin7Day, 'checkin'),
          key: 'rewards-checkin'),
      const SizedBox(height: 12),
      if (s.bingeStreak != null) ...[
        _card('Binge streak bonus', Icons.local_fire_department, _task(s.bingeStreak!), key: 'rewards-binge'),
        const SizedBox(height: 12),
      ],
      if (s.dramaCompletion.isNotEmpty) ...[
        _card('Finish a drama, earn coins', Icons.emoji_events_outlined,
            Column(children: [for (final t in s.dramaCompletion) _task(t)]),
            key: 'rewards-complete'),
        const SizedBox(height: 12),
      ],
      if (s.chests.isNotEmpty)
        _card('Treasure chests', Icons.inventory_2_outlined,
            Row(children: [for (final c in s.chests) Expanded(child: _chest(c))]),
            key: 'rewards-chests'),
    ]);
  }

  Widget _balances(RewardsSummary s) => Container(
        key: const ValueKey('rewards-balances'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [AppColors.greenDark, Color(0xFF0F3D26)]),
        ),
        child: Stack(children: [
          const Positioned.fill(child: TextilePattern(opacity: .10)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: _bal('My coins', '${s.balanceCoins}', Icons.monetization_on, 'rewards-coins')),
              Container(width: 1, height: 44, color: Colors.white24),
              const SizedBox(width: 16),
              Expanded(child: _bal('Cash (₦)', formatNaira(s.cashKobo), Icons.payments_outlined, 'rewards-cash')),
            ]),
          ),
        ]),
      );

  Widget _bal(String l, String v, IconData i, String k) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(i, color: AppColors.gold, size: 22),
          const SizedBox(width: 6),
          Flexible(
              child: Text(v,
                  key: ValueKey(k),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.w900))),
        ]),
      ]);

  Widget _card(String title, IconData icon, Widget child, {required String key}) => Container(
        key: ValueKey(key),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: .18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: AppColors.gold, size: 20),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _days(List<RewardDay> days, String kind) {
    final claimable = days.where((d) => d.status == 'claimable' && !_isClaimed(d.taskId, d.status)).firstOrNull;
    return Column(children: [
      Row(children: [
        for (final d in days)
          Expanded(
            child: Container(
              key: ValueKey('$kind-day-${d.day}'),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: d.status == 'claimable' && !_isClaimed(d.taskId, d.status)
                    ? AppColors.gold.withValues(alpha: .22)
                    : AppColors.surfaceHigh,
                border: Border.all(
                    color: d.status == 'claimable' && !_isClaimed(d.taskId, d.status)
                        ? AppColors.gold
                        : Colors.transparent),
              ),
              child: Column(children: [
                Icon(_isClaimed(d.taskId, d.status) ? Icons.check_circle : Icons.monetization_on,
                    size: 18, color: _isClaimed(d.taskId, d.status) ? AppColors.primary : AppColors.gold),
                const SizedBox(height: 2),
                Text('+${d.rewardCoins}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('Day ${d.day}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: claimable != null
            ? _claimBtn(claimable.taskId, claimable.status, label: 'Oya, claim am! +${claimable.rewardCoins}')
            : const OutlinedButton(onPressed: null, child: Text('Come back tomorrow')),
      ),
    ]);
  }

  Widget _task(RewardTask t) => Padding(
        key: ValueKey('task-${t.taskId}'),
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: t.target == 0 ? 0 : t.progress / t.target,
                    minHeight: 8,
                    color: AppColors.gold,
                    backgroundColor: AppColors.surfaceHigh),
              ),
              const SizedBox(height: 4),
              Text('${t.progress}/${t.target} · +${t.rewardCoins} coins',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          _claimBtn(t.taskId, t.status),
        ]),
      );

  Widget _chest(RewardChest c) {
    final done = _isClaimed(c.taskId, c.status);
    String sub;
    if (done) {
      sub = 'Opened';
    } else if (c.status == 'unlocking' && c.unlockAt != null) {
      sub = 'Opens in ${countdownText(c.unlockAt!, _now)}';
    } else if (c.status == 'locked' && c.target != null) {
      sub = 'Watch ${c.progress ?? 0}/${c.target} min';
    } else {
      sub = 'Ready';
    }
    return Container(
      key: ValueKey('chest-${c.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(done ? Icons.inventory_2 : Icons.redeem, size: 34, color: AppColors.gold),
        const SizedBox(height: 4),
        Text('${c.rewardCoinsMin}-${c.rewardCoinsMax} coins', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 6),
        _claimBtn(c.taskId, c.status),
      ]),
    );
  }
}
