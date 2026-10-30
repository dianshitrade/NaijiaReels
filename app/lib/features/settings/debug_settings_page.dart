import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_storage.dart';
import '../../data/repository.dart';

/// Debug: switch API base at runtime (stored in Hive). Quick tunnels change
/// address on restart, so this avoids rebuilding the APK.
class DebugSettingsPage extends ConsumerStatefulWidget {
  const DebugSettingsPage({super.key});

  @override
  ConsumerState<DebugSettingsPage> createState() => _DebugSettingsPageState();
}

class _DebugSettingsPageState extends ConsumerState<DebugSettingsPage> {
  late final _ctrl = TextEditingController(text: Env.apiBaseUrl);
  String? _status;

  Future<void> _apply(String? value) async {
    await LocalStorage.setApiBaseOverride(value);
    await LocalStorage.clearTokens(); // tokens are per-backend
    setState(() => _status = 'Connecting…');
    try {
      await guestLogin();
      setState(() => _status = 'OK: ${Env.apiRoot}');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    }
    ref.invalidate(homeProvider);
    ref.invalidate(walletProvider);
    ref.invalidate(dramaListProvider);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'API_BASE_URL (without /api/v1)',
            hintText: 'https://xxx.trycloudflare.com',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _apply(_ctrl.text), child: const Text('Save & reconnect')),
        TextButton(
          onPressed: () {
            _ctrl.text = Env.defaultApiBaseUrl;
            _apply(null);
          },
          child: Text('Reset to build default (${Env.defaultApiBaseUrl})'),
        ),
        const SizedBox(height: 12),
        Text('Device: ${LocalStorage.deviceId}', style: Theme.of(context).textTheme.bodySmall),
        if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
      ]),
    );
  }
}
