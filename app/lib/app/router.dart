import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/episodes/episodes_page.dart';
import '../features/home/home_page.dart';
import '../features/player/demo_feed_page.dart';
import '../features/splash/splash_page.dart';

class Routes {
  Routes._();
  static const splash = '/';
  static const home = '/home';
  static const demo = '/demo';
  static const episodes = '/episodes';
  static const login = '/login';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.splash,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashPage()),
      GoRoute(path: Routes.home, builder: (_, __) => const HomePage()),
      GoRoute(path: Routes.demo, builder: (_, __) => const DemoFeedPage()),
      GoRoute(path: Routes.episodes, builder: (_, __) => const EpisodesPage()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginPage()),
    ],
  );
});
