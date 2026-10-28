import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/env.dart';
import '../../app/router.dart';
import '../../shared/widgets/brand_logo.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const BrandLogo(fontSize: 22)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('API: ${Env.apiRoot}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push(Routes.demo),
            child: const Text('Player demo (vertical feed)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push(Routes.episodes),
            child: const Text('Episodes'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push(Routes.login),
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}
