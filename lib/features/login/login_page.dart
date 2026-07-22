import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../../services/session.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usr = TextEditingController();
  final _pwd = TextEditingController();
  late final TextEditingController _baseUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(
      text: ref.read(chatAiSessionProvider).baseUrl,
    );
  }

  @override
  void dispose() {
    _usr.dispose();
    _pwd.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final session = ref.read(chatAiSessionProvider);
    session.updateBaseUrl(_baseUrl.text.trim());
    setState(() => _busy = true);
    final result = await session.login(usr: _usr.text.trim(), pwd: _pwd.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is ErpnextLoginOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signed in as ${result.session.fullName}')),
      );
      context.go('/chat');
    } else if (result is ErpnextLoginFail) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatAiSessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'ZatGo',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Chat AI',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Talk to your ERP assistant. Sign in with ERPNext.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(labelText: 'Site URL'),
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usr,
                  decoration: const InputDecoration(labelText: 'Email / User'),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwd,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _login(),
                ),
                if (session.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    session.lastError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          session.updateBaseUrl(_baseUrl.text.trim());
                          setState(() => _busy = true);
                          final r = await session.ping();
                          if (!mounted) return;
                          setState(() => _busy = false);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(r.message)));
                        },
                  child: const Text('Test site'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
