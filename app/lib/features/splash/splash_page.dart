import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/widgets/brand_logo.dart';

/// Ensures a guest session (deviceId + tokens in Hive), then goes home.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.autoBoot = true});
  final bool autoBoot;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _error;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoBoot) _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _error = null;
      _slow = false;
    });
    // If the server does not answer within 3s it is most likely cold-starting.
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      await wakeServer();
      if (LocalStorage.accessToken == null) await guestLogin();
      if (mounted) context.go(Routes.home);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _slowTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.1,
            colors: [Color(0xFF0F3D26), AppColors.background],
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 56, child: BrandLogo(fontSize: 40)),
          const SizedBox(height: 8),
          const Text('Naija stories. Short & sweet.',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 32),
          if (_error == null) ...[
            const CircularProgressIndicator(),
            if (_slow)
              const Padding(
                key: Key('wakingHint'),
                padding: EdgeInsets.all(16),
                child: Text(
                  'Waking up the server, this can take about 1 minute…\n服务器唤醒中，约需 1 分钟…',
                  textAlign: TextAlign.center,
                ),
              ),
          ]
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
