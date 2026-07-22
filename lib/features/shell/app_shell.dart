import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        height: 72,
        elevation: 0,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline, color: scheme.onSurfaceVariant),
            selectedIcon: Icon(Icons.chat_bubble, color: scheme.primary),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: scheme.onSurfaceVariant),
            selectedIcon: Icon(Icons.settings, color: scheme.primary),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
