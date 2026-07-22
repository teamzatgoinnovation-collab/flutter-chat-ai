import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../../data/chat_ai_repo.dart';
import '../../models/chat_models.dart';
import '../../services/session.dart';
import '../../widgets/sign_out_action.dart';

const _chatMaxWidth = 780.0;
const _typeDelay = Duration(milliseconds: 14);

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
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  bool _loading = false;
  bool _sending = false;
  bool _typingOut = false;
  String? _error;
  List<ChatSession> _sessions = [];
  List<ChatMessage> _messages = [];
  SendResult? _pending;

  /// Local streaming assistant bubble (not yet in history).
  String? _streamText;
  int _typeGen = 0;

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
    _typeGen++;
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _cancelTypewriter() {
    _typeGen++;
    _streamText = null;
    _typingOut = false;
  }

  Future<void> _bootstrap() async {
    final session = ref.read(chatAiSessionProvider);
    if (!session.connected) return;
    _cancelTypewriter();
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
      session.setContentReady(true);
      setState(() => _loading = false);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      session.setContentReady(false);
      setState(() {
        _loading = false;
        _error = formatChatError(e);
      });
    }
  }

  Future<void> _selectSession(String name) async {
    final session = ref.read(chatAiSessionProvider);
    final repo = ref.read(chatAiRepoProvider);
    _cancelTypewriter();
    session.setActiveSession(name);
    setState(() {
      _loading = true;
      _error = null;
      _pending = null;
      _streamText = null;
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
    _cancelTypewriter();
    setState(() {
      _loading = true;
      _error = null;
      _streamText = null;
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

  Future<void> _typeOut(String full) async {
    final gen = ++_typeGen;
    setState(() {
      _typingOut = true;
      _sending = false;
      _streamText = '';
    });
    _scrollToEnd();

    for (var i = 1; i <= full.length; i++) {
      if (!mounted || gen != _typeGen) return;
      setState(() => _streamText = full.substring(0, i));
      if (i % 3 == 0 || i == full.length) _scrollToEnd();
      await Future.delayed(_typeDelay);
    }

    if (!mounted || gen != _typeGen) return;
    setState(() {
      _typingOut = false;
      _streamText = null;
    });
  }

  Future<void> _send({
    int confirmed = 0,
    int planConfirmed = 0,
    String message = '',
  }) async {
    final text = message.isNotEmpty ? message : _composer.text.trim();
    if (text.isEmpty && confirmed == 0 && planConfirmed == 0) return;
    if (_sending || _typingOut) return;

    final session = ref.read(chatAiSessionProvider);
    final repo = ref.read(chatAiRepoProvider);
    final active = session.activeSessionName;
    setState(() {
      _sending = true;
      _error = null;
      _streamText = null;
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
      final history = await repo.history(session, result.session);
      _pending = repo.pendingConfirmation;
      if (!mounted) return;

      final reply = result.content.trim().isNotEmpty
          ? result.content
          : (history.isNotEmpty && history.last.isAssistant
                ? history.last.content
                : '');

      // Hold off showing the final assistant turn until typewriter finishes.
      if (history.isNotEmpty && history.last.isAssistant && reply.isNotEmpty) {
        _messages = history.sublist(0, history.length - 1);
      } else {
        _messages = history;
      }

      if (reply.isEmpty ||
          result.needsConfirmation ||
          result.needsPlanApproval) {
        _messages = history;
        setState(() => _sending = false);
        _scrollToEnd();
        return;
      }

      await _typeOut(reply);
      if (!mounted) return;
      _messages = history;
      setState(() {});
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _typingOut = false;
        _streamText = null;
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
          _cancelTypewriter();
          await repo.clear(session, active);
          _messages = [];
          _pending = null;
          break;
        case 'archive':
          _cancelTypewriter();
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
          _cancelTypewriter();
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
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    final shift =
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isAltPressed;
    if (shift) return KeyEventResult.ignored; // allow newline
    if (!_sending && !_typingOut) _send();
    return KeyEventResult.handled;
  }

  String get _title {
    final active = ref.read(chatAiSessionProvider).activeSessionName;
    if (active == null) return 'Chat AI';
    for (final s in _sessions) {
      if (s.name == active) return s.title;
    }
    return 'Chat AI';
  }

  Widget _centered(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _chatMaxWidth),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatUiTickProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = ref.watch(chatAiSessionProvider).activeSessionName;
    final busy = _sending || _typingOut;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: _loading || busy ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          PopupMenuButton<String>(
            enabled: active != null && !busy,
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
              child: _centered(
                Padding(
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
            ),
          Expanded(
            child: _messages.isEmpty && !_loading && _streamText == null
                ? _EmptyChat(
                    onSuggestion: (text) {
                      _composer.text = text;
                      _send(message: text);
                    },
                    suggestions: _suggestions,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    itemCount:
                        _messages.length +
                        (_sending ? 1 : 0) +
                        (_streamText != null ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i < _messages.length) {
                        return _centered(_MessageBubble(message: _messages[i]));
                      }
                      var idx = i - _messages.length;
                      if (_sending && idx == 0) {
                        return _centered(const _TypingRow());
                      }
                      if (_sending) idx -= 1;
                      if (_streamText != null && idx == 0) {
                        return _centered(
                          _MessageBubble(
                            message: ChatMessage(
                              name: 'streaming',
                              role: 'assistant',
                              content: _streamText!,
                            ),
                            displayText: _streamText,
                            isStreaming: _typingOut,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
          if (_pending != null)
            _centered(
              _ConfirmationBar(
                pending: _pending!,
                busy: busy,
                onConfirm: () => _send(
                  confirmed: _pending!.needsConfirmation ? 1 : 0,
                  planConfirmed: _pending!.needsPlanApproval ? 1 : 0,
                  message: 'OK',
                ),
                onCancel: () => setState(() => _pending = null),
              ),
            ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          SafeArea(
            top: false,
            child: _centered(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onComposerKey,
                        child: TextField(
                          controller: _composer,
                          focusNode: _composerFocus,
                          minLines: 1,
                          maxLines: 6,
                          enabled: !busy,
                          textInputAction: TextInputAction.send,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: 'Message…',
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: scheme.primary,
                                width: 1.4,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (!busy) _send();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: busy ? null : () => _send(),
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
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _chatMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 40,
                color: scheme.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 18),
              Text(
                'How can I help?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask about your ERP — or pick a suggestion.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => onSuggestion(s),
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

class _TypingRow extends StatefulWidget {
  const _TypingRow();

  @override
  State<_TypingRow> createState() => _TypingRowState();
}

class _TypingRowState extends State<_TypingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Row(
                children: List.generate(3, (i) {
                  final phase = (_c.value + i * 0.22) % 1.0;
                  final t = (phase < 0.5 ? phase : 1 - phase) * 2;
                  return Container(
                    margin: const EdgeInsets.only(right: 5),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.onSurfaceVariant.withValues(
                        alpha: 0.35 + 0.55 * t,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.displayText,
    this.isStreaming = false,
  });

  final ChatMessage message;
  final String? displayText;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.isUser;
    final text = displayText ?? message.content;

    if (message.role == 'system' || message.role == 'tool') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimary,
                height: 1.45,
              ),
            ),
          ),
        ),
      );
    }

    // ChatGPT-style assistant: avatar + plain text (no filled bubble).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: isStreaming
                ? _StreamingText(text: text, style: theme.textTheme.bodyLarge)
                : SelectableText(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StreamingText extends StatefulWidget {
  const _StreamingText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        return Text.rich(
          TextSpan(
            style: widget.style?.copyWith(height: 1.5),
            children: [
              TextSpan(text: widget.text),
              TextSpan(
                text: '|',
                style: TextStyle(
                  color: scheme.primary.withValues(
                    alpha: 0.2 + 0.8 * _blink.value,
                  ),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
