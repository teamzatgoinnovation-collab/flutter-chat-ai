import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/chat/chat_page.dart';
import 'features/login/login_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shell/app_shell.dart';
import 'services/session.dart';
import 'theme.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(chatAiSessionProvider);

  return GoRouter(
    initialLocation: '/chat',
    refreshListenable: session,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      if (!session.canEnterApp && !loggingIn) return '/login';
      if (session.canEnterApp && loggingIn) return '/chat';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                builder: (context, state) => const ChatPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class ChatAiApp extends ConsumerWidget {
  const ChatAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: 'ZatGo Chat AI',
      theme: buildChatAiTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
