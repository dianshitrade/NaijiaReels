import 'package:flutter/material.dart';

import '../rewards/rewards_page.dart';
import '../shell/tab_placeholders.dart';
import '../theater/theater_page.dart';
import 'home_feed_page.dart';

/// Main shell: Home / Theater / Shop / Rewards / Me.
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
      body: IndexedStack(index: _tab, children: [
        HomeFeedPage(active: _tab == 0, onOpenRewards: () => setState(() => _tab = 3)),
        const TheaterPage(),
        const ShopPlaceholder(),
        const RewardsPage(),
        const MePlaceholder(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.theaters_outlined), selectedIcon: Icon(Icons.theaters), label: 'Theater'),
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Shop'),
          NavigationDestination(
              icon: Icon(Icons.card_giftcard_outlined), selectedIcon: Icon(Icons.card_giftcard), label: 'Rewards'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}
