import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/widgets/brand_logo.dart';

/// Ensures a guest session (deviceId + tokens in Hive), then goes home.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      if (LocalStorage.accessToken == null) await guestLogin();
      if (mounted) context.go(Routes.home);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const BrandLogo(fontSize: 40),
          const SizedBox(height: 24),
          if (_error == null)
            const CircularProgressIndicator()
          else ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Connect failed:\n$_error', textAlign: TextAlign.center),
            ),
            FilledButton(onPressed: _boot, child: const Text('Retry')),
            TextButton(
              onPressed: () => context.push(Routes.settings).then((_) => _boot()),
              child: const Text('Debug settings'),
            ),
          ],
        ]),
      ),
    );
  }
}
