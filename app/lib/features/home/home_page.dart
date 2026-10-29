import 'package:flutter/material.dart';

import '../inbox/inbox_page.dart';
import '../profile/profile_page.dart';
import '../rewards/rewards_page.dart';
import 'discover_page.dart';

/// Main shell with the bottom navigation.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [
        DiscoverPage(),
        RewardsPage(),
        InboxPage(),
        ProfilePage(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(
              icon: Icon(Icons.card_giftcard_outlined),
              selectedIcon: Icon(Icons.card_giftcard),
              label: 'Rewards'),
          NavigationDestination(
              icon: Icon(Icons.mail_outline), selectedIcon: Icon(Icons.mail), label: 'Inbox'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}
