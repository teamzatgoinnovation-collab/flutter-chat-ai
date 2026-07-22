import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../../data/chat_ai_repo.dart';
import '../../models/chat_models.dart';
import '../../services/session.dart';
import '../../widgets/sign_out_action.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  String? _lastProbe;
  String? _error;
  UiLocale? _locale;
  String? _language;
  String? _mode;
  late final TextEditingController _baseUrl;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(
      text: ref.read(chatAiSessionProvider).baseUrl,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final session = ref.read(chatAiSessionProvider);
    if (!session.connected) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(chatAiRepoProvider);
      final locale = await repo.getUiLocale(session);
      final sessions = await repo.listSessions(session);
      final activeName = session.activeSessionName;
      ChatSession? active;
      for (final s in sessions) {
        if (s.name == activeName) {
          active = s;
          break;
        }
      }
      active ??= sessions.isNotEmpty ? sessions.first : null;
      if (!mounted) return;
      setState(() {
        _locale = locale;
        _language = active?.language ?? locale.language;
        _mode = active?.assistantMode ?? 'ERP Assistant';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ZatGoApiError ? e.message : e.toString();
      });
    }
  }

  Future<void> _applyLanguage(String code) async {
    final session = ref.read(chatAiSessionProvider);
    final active = session.activeSessionName;
    if (active == null) {
      setState(() => _error = 'Open a chat session first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(chatAiRepoProvider)
          .setLanguage(session, sessionName: active, language: code);
      if (!mounted) return;
      setState(() {
        _language = code;
        _busy = false;
        _lastProbe = 'Language set to $code';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _applyMode(String mode) async {
    final session = ref.read(chatAiSessionProvider);
    final active = session.activeSessionName;
    if (active == null) {
      setState(() => _error = 'Open a chat session first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(chatAiRepoProvider)
          .setMode(session, sessionName: active, assistantMode: mode);
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _busy = false;
        _lastProbe = 'Mode set to $mode';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatAiSessionProvider);
    final theme = Theme.of(context);
    final languages =
        _locale?.languages ??
        const [
          UiLanguage(code: 'en', label: 'English'),
          UiLanguage(code: 'ar', label: 'Arabic'),
          UiLanguage(code: 'ml', label: 'Malayalam'),
        ];

    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [SignOutAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Chat preferences',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Language and assistant mode apply to the active chat session.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: languages.any((l) => l.code == _language)
                        ? _language
                        : (languages.isNotEmpty ? languages.first.code : null),
                    decoration: const InputDecoration(labelText: 'Language'),
                    items: [
                      for (final l in languages)
                        DropdownMenuItem(
                          value: l.code,
                          child: Text(
                            l.native.isNotEmpty
                                ? '${l.label} (${l.native})'
                                : l.label,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) _applyLanguage(v);
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: assistantModes.contains(_mode)
                        ? _mode
                        : 'ERP Assistant',
                    decoration: const InputDecoration(
                      labelText: 'Assistant mode',
                    ),
                    items: [
                      for (final m in assistantModes)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) _applyMode(v);
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'LLM provider keys and site-wide Chat AI Settings are '
                    'configured in Desk (managers only).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Connection',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ERPNext session for chat_ai APIs.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Chip(
                    avatar: Icon(
                      session.connected
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                      size: 18,
                      color: session.connected ? scheme.primary : scheme.error,
                    ),
                    label: Text(
                      session.connected
                          ? 'Signed in as ${session.fullName ?? session.user}'
                          : 'Not signed in',
                    ),
                    backgroundColor: session.connected
                        ? scheme.primary.withValues(alpha: 0.1)
                        : scheme.errorContainer.withValues(alpha: 0.4),
                    side: BorderSide.none,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(
                      labelText: 'Site URL',
                      prefixIcon: Icon(Icons.language_outlined),
                    ),
                    enabled: !session.connected,
                    onChanged: (v) => session.updateBaseUrl(v),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                session.updateBaseUrl(_baseUrl.text.trim());
                                setState(() => _busy = true);
                                final r = await session.ping();
                                if (!mounted) return;
                                setState(() {
                                  _busy = false;
                                  _lastProbe = r.message;
                                });
                              },
                        child: const Text('Test site'),
                      ),
                      OutlinedButton(
                        onPressed: _busy || !session.connected
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  final env = await session.store.callMethod(
                                    ZatGoApiMethods.chatAiListSessions,
                                    args: {'status': 'Active'},
                                  );
                                  final n = env.data is List
                                      ? (env.data as List).length
                                      : 0;
                                  if (!mounted) return;
                                  setState(() {
                                    _busy = false;
                                    _lastProbe = 'Sessions ok — count=$n';
                                  });
                                } catch (e) {
                                  if (!mounted) return;
                                  setState(() {
                                    _busy = false;
                                    _lastProbe = '$e';
                                  });
                                }
                              },
                        child: const Text('Probe chat'),
                      ),
                    ],
                  ),
                  if (_lastProbe != null) ...[
                    const SizedBox(height: 12),
                    Text(_lastProbe!),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await session.logout();
                    if (!mounted) return;
                    setState(() => _busy = false);
                    if (!context.mounted) return;
                    context.go('/login');
                  },
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Sign out'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}
