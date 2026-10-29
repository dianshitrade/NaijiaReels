import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/wallet_chip.dart';

/// Rewards: 7-day check-in + daily tasks. No backend yet -> local mock state.
class RewardsPage extends StatefulWidget {
  const RewardsPage({super.key});
  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  static const _rewards = [10, 10, 15, 20, 25, 30, 50];
  final int _checked = 3; // mock: days 1-3 done
  bool _today = false;

  static const _tasks = [
    ('Watch 5 episodes', '3/5 today', 20, Icons.play_circle_outline),
    ('Watch 3 ads', 'Earn coins anytime', 30, Icons.ondemand_video),
    ('Share to WhatsApp', 'Invite your pals', 15, Icons.share),
    ('Turn on notifications', 'One time', 10, Icons.notifications_active_outlined),
    ('Invite a friend', 'Both get 100 coins', 100, Icons.person_add_alt),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rewards', style: TextStyle(fontWeight: FontWeight.w800)), actions: const [WalletChip()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(colors: [AppColors.greenDark, Color(0xFF0F3D26)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Daily Check-in · ${_checked + (_today ? 1 : 0)}-day streak',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _day(i),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
                onPressed: _today ? null : () => setState(() => _today = true),
                child: Text(_today ? 'Checked in today' : 'Check in today · +${_rewards[_checked]} coins',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        const Row(children: [
          Text('Daily Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Spacer(),
          Text('Resets 00:00 WAT', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        for (final t in _tasks)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(t.$4, color: AppColors.primary),
              title: Text(t.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t.$2, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(16)),
                child: Text('+${t.$3}',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _day(int i) {
    final done = i < _checked || (_today && i == _checked);
    final isToday = i == _checked;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: done ? AppColors.primary : Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: isToday ? Border.all(color: AppColors.gold, width: 1.5) : null,
      ),
      child: FittedBox(
        child: Column(children: [
          Text('Day ${i + 1}', style: const TextStyle(fontSize: 10)),
          Icon(done ? Icons.check_circle : Icons.monetization_on,
              size: 16, color: done ? Colors.white : AppColors.gold),
          Text('+${_rewards[i]}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
