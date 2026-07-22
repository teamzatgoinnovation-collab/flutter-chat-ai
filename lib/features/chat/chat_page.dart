import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../../data/chat_ai_repo.dart';
import '../../models/chat_models.dart';
import '../../services/session.dart';
import '../../widgets/sign_out_action.dart';

String formatChatError(Object error) {
  final raw = error is ZatGoApiError ? error.message : error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('402') ||
      lower.contains('credits') ||
      lower.contains('max_tokens') ||
      lower.contains('payment required')) {
    return 'AI provider needs more credits or a lower token limit. '
        'Try again, or ask an admin to top up OpenRouter / lower Max Tokens '
        'in Chat AI Settings.';
  }
  return raw;
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = false;
  bool _sending = false;
  String? _error;
  List<ChatSession> _sessions = [];
  List<ChatMessage> _messages = [];
  SendResult? _pending;

  static const _suggestions = [
    'What open sales orders do I have?',
    'Summarize today’s receivables',
    'List pending purchase invoices',
    'Show stock shortages',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = ref.read(chatAiSessionProvider);
    if (!session.connected) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(chatAiRepoProvider);
      final list = await repo.listSessions(session);
      if (!mounted) return;
      _sessions = list;
      var active = session.activeSessionName;
      if (active == null || !_sessions.any((s) => s.name == active)) {
        if (_sessions.isNotEmpty) {
          active = _sessions.first.name;
          session.setActiveSession(active);
        } else {
          active = await repo.newSession(session);
          session.setActiveSession(active);
          _sessions = await repo.listSessions(session);
        }
      }
      _messages = await repo.history(session, active);
      _pending = repo.pendingConfirmation;
      setState(() => _loading = false);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = formatChatError(e);
      });
    }
  }

  Future<void> _selectSession(String name) async {
    final session = ref.read(chatAiSessionProvider);
    final repo = ref.read(chatAiRepoProvider);
    session.setActiveSession(name);
    setState(() {
      _loading = true;
      _error = null;
      _pending = null;
    });
    try {
      _messages = await repo.history(session, name);
      if (!mounted) return;
      setState(() => _loading = false);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = formatChatError(e);
      });
    }
  }

  Future<void> _newChat() async {
    final session = ref.read(chatAiSessionProvider);
    final repo = ref.read(chatAiRepoProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final name = await repo.newSession(session);
      session.setActiveSession(name);
      _sessions = await repo.listSessions(session);
      _messages = [];
      _pending = null;
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = formatChatError(e);
      });
    }
  }

  Future<void> _send({
    int confirmed = 0,
    int planConfirmed = 0,
    String message = '',
  }) async {
    final text = message.isNotEmpty ? message : _composer.text.trim();
    if (text.isEmpty && confirmed == 0 && planConfirmed == 0) return;

    final session = ref.read(chatAiSessionProvider);
    final repo = ref.read(chatAiRepoProvider);
    final active = session.activeSessionName;
    setState(() {
      _sending = true;
      _error = null;
    });
    if (confirmed == 0 && planConfirmed == 0) {
      _composer.clear();
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            name: 'local-${DateTime.now().millisecondsSinceEpoch}',
            role: 'user',
            content: text,
          ),
        ];
      });
      _scrollToEnd();
    }

    try {
      final result = await repo.send(
        session,
        message: text.isEmpty ? 'OK' : text,
        sessionName: active,
        confirmed: confirmed,
        planConfirmed: planConfirmed,
        pendingTool: _pending?.pendingTool,
        pendingArgs: _pending?.pendingArgs,
        confirmationToken: _pending?.confirmationToken,
      );
      session.setActiveSession(result.session);
      _sessions = await repo.listSessions(session);
      _messages = await repo.history(session, result.session);
      _pending = repo.pendingConfirmation;
      if (!mounted) return;
      setState(() => _sending = false);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = formatChatError(e);
      });
    }
  }

  Future<void> _sessionAction(String action) async {
    final session = ref.read(chatAiSessionProvider);
    final repo = ref.read(chatAiRepoProvider);
    final active = session.activeSessionName;
    if (active == null) return;

    try {
      switch (action) {
        case 'rename':
          final controller = TextEditingController(
            text: _sessions
                .where((s) => s.name == active)
                .map((s) => s.title)
                .firstOrNull,
          );
          final title = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Rename chat'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Title'),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (title == null || title.isEmpty) return;
          await repo.rename(session, sessionName: active, title: title);
          break;
        case 'clear':
          await repo.clear(session, active);
          _messages = [];
          _pending = null;
          break;
        case 'archive':
          await repo.archive(session, active);
          session.setActiveSession(null);
          await _bootstrap();
          return;
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete chat?'),
              content: const Text('This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await repo.deleteSession(session, active);
          session.setActiveSession(null);
          await _bootstrap();
          return;
      }
      _sessions = await repo.listSessions(session);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatChatError(e));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String get _title {
    final active = ref.read(chatAiSessionProvider).activeSessionName;
    if (active == null) return 'Chat AI';
    for (final s in _sessions) {
      if (s.name == active) return s.title;
    }
    return 'Chat AI';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatUiTickProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = ref.watch(chatAiSessionProvider).activeSessionName;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: _loading || _sending ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          PopupMenuButton<String>(
            enabled: active != null && !_sending,
            onSelected: _sessionAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'clear', child: Text('Clear messages')),
              PopupMenuItem(value: 'archive', child: Text('Archive')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          const SignOutAction(),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: scheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sessions',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'New chat',
                      onPressed: () {
                        Navigator.pop(context);
                        _newChat();
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _sessions.length,
                  itemBuilder: (context, i) {
                    final s = _sessions[i];
                    final selected = s.name == active;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        selected: selected,
                        selectedTileColor: scheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        leading: Icon(
                          s.isPinned ? Icons.push_pin : Icons.chat_outlined,
                          size: 20,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          s.assistantMode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _selectSession(s.name);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Material(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _messages.isEmpty && !_loading
                ? _EmptyChat(
                    onSuggestion: (text) {
                      _composer.text = text;
                      _send(message: text);
                    },
                    suggestions: _suggestions,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_sending && i == _messages.length) {
                        return const _TypingRow();
                      }
                      return _MessageBubble(message: _messages[i]);
                    },
                  ),
          ),
          if (_pending != null)
            _ConfirmationBar(
              pending: _pending!,
              busy: _sending,
              onConfirm: () => _send(
                confirmed: _pending!.needsConfirmation ? 1 : 0,
                planConfirmed: _pending!.needsPlanApproval ? 1 : 0,
                message: 'OK',
              ),
              onCancel: () => setState(() => _pending = null),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sending ? null : _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: _sending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onSuggestion, required this.suggestions});

  final ValueChanged<String> onSuggestion;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: scheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Ask anything about your ERP',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a suggestion or type your own message.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in suggestions)
                  ActionChip(label: Text(s), onPressed: () => onSuggestion(s)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary.withValues(alpha: 0.15),
            child: Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Text(
            'Assistant is thinking…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fg = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    if (message.role == 'system' || message.role == 'tool') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(color: bg, borderRadius: radius),
                  child: SelectableText(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmationBar extends StatelessWidget {
  const _ConfirmationBar({
    required this.pending,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final SendResult pending;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = pending.needsPlanApproval
        ? (pending.confirmationMessage.isNotEmpty
              ? pending.confirmationMessage
              : 'Approve this plan?')
        : (pending.confirmationMessage.isNotEmpty
              ? pending.confirmationMessage
              : 'Confirm this action?');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: busy ? null : onConfirm,
                    child: Text(
                      pending.needsPlanApproval ? 'Approve' : 'Confirm',
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: busy ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
