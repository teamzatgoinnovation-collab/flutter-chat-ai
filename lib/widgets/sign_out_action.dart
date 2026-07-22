import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/session.dart';

class SignOutAction extends ConsumerWidget {
  const SignOutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sign out',
      onPressed: () async {
        await ref.read(chatAiSessionProvider).logout();
        if (context.mounted) context.go('/login');
      },
      icon: const Icon(Icons.logout_rounded),
    );
  }
}
