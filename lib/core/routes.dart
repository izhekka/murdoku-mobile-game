import 'package:go_router/go_router.dart';

import '../ui/screens/game_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/how_to_play_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/stats_screen.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/game', builder: (_, _) => const GameScreen()),
        GoRoute(
            path: '/how-to-play',
            builder: (_, _) => const HowToPlayScreen()),
        GoRoute(path: '/stats', builder: (_, _) => const StatsScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      ],
    );
