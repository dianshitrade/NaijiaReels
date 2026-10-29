import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/episodes/drama_detail_page.dart';
import '../features/episodes/drama_list_page.dart';
import '../features/home/home_page.dart';
import '../features/player/episode_feed_page.dart';
import '../features/settings/debug_settings_page.dart';
import '../features/splash/splash_page.dart';

class Routes {
  Routes._();
  static const splash = '/';
  static const home = '/home';
  static const dramas = '/dramas';
  static const login = '/login';
  static const settings = '/settings';
  static String dramaDetail(String id) => '/drama/$id';
  static String play(String id, int index) => '/drama/$id/play?ep=$index';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.splash,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashPage()),
      GoRoute(path: Routes.home, builder: (_, __) => const HomePage()),
      GoRoute(path: Routes.dramas, builder: (_, __) => const DramaListPage()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginPage()),
      GoRoute(path: Routes.settings, builder: (_, __) => const DebugSettingsPage()),
      GoRoute(
        path: '/drama/:id',
        builder: (_, s) => DramaDetailPage(dramaId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'play',
            builder: (_, s) => EpisodeFeedPage(
              dramaId: s.pathParameters['id']!,
              initialIndex: int.tryParse(s.uri.queryParameters['ep'] ?? '') ?? 0,
            ),
          ),
        ],
      ),
    ],
  );
});
