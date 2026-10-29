import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Inbox with category tabs (mock data, no backend yet).
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});

  static const _tabs = ['All', 'Rewards', 'Updates', 'System'];
  static const _msgs = [
    ('Rewards', 'Check-in bonus ready', 'Claim today\'s +15 coins before midnight.', '09:12'),
    ('Updates', 'New episodes dropped', 'My Village Husband is a Prince · EP 16–20 now live.', 'Yesterday'),
    ('Rewards', 'Welcome gift', '100 coins added to your wallet. Enjoy!', 'Mon'),
    ('System', 'Guest account created', 'Bind your phone to keep your coins safe.', 'Mon'),
    ('Updates', 'Trending in Lagos', 'The Billionaire\'s Secret Wife is #1 this week.', 'Sun'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inbox', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in _tabs) Tab(text: t)],
          ),
        ),
        body: TabBarView(children: [
          for (final t in _tabs)
            ListView(padding: const EdgeInsets.all(12), children: [
              for (final m in _msgs.where((m) => t == 'All' || m.$1 == t))
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (m.$1 == 'Rewards' ? AppColors.gold : AppColors.primary)
                          .withValues(alpha: 0.2),
                      child: Icon(
                        m.$1 == 'Rewards'
                            ? Icons.monetization_on
                            : m.$1 == 'Updates'
                                ? Icons.movie_filter
                                : Icons.info_outline,
                        color: m.$1 == 'Rewards' ? AppColors.gold : AppColors.primary,
                      ),
                    ),
                    title: Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(m.$3, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text(m.$4, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
                ),
            ]),
        ]),
      ),
    );
  }
}
