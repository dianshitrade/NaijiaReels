import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/ankara_pattern.dart';
import '../inbox/inbox_page.dart';
import '../profile/profile_page.dart';

/// Simple English placeholder used until a tab is built out.
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.actions = const [],
    this.cta,
  });
  final String title;
  final IconData icon;
  final String message;
  final List<Widget> actions;
  final Widget? cta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), actions: actions),
      body: Stack(children: [
        const Positioned.fill(child: TextilePattern(opacity: .06)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 56, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              if (cta != null) ...[const SizedBox(height: 20), cta!],
            ]),
          ),
        ),
      ]),
    );
  }
}

class ShopPlaceholder extends StatelessWidget {
  const ShopPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const TabPlaceholder(
      title: 'Shop', icon: Icons.storefront_outlined, message: 'Coin packs and VIP passes in ₦ are coming soon.');
}

class MePlaceholder extends StatelessWidget {
  const MePlaceholder({super.key});
  @override
  Widget build(BuildContext context) => TabPlaceholder(
        title: 'Me',
        icon: Icons.person_outline,
        message: 'History, saved dramas and likes are coming soon.',
        actions: [
          IconButton(
            key: const ValueKey('me-inbox'),
            tooltip: 'Inbox',
            icon: const Icon(Icons.mail_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InboxPage())),
          ),
        ],
        cta: OutlinedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfilePage())),
          child: const Text('Account & settings'),
        ),
      );
}
