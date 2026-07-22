class ChatSession {
  const ChatSession({
    required this.name,
    required this.title,
    this.assistantMode = 'ERP Assistant',
    this.status = 'Active',
    this.isPinned = false,
    this.lastMessageAt,
    this.modified,
    this.language,
  });

  final String name;
  final String title;
  final String assistantMode;
  final String status;
  final bool isPinned;
  final String? lastMessageAt;
  final String? modified;
  final String? language;

  factory ChatSession.fromApi(Map<dynamic, dynamic> row) {
    return ChatSession(
      name: row['name']?.toString() ?? '',
      title: row['title']?.toString() ?? 'Chat',
      assistantMode: row['assistant_mode']?.toString() ?? 'ERP Assistant',
      status: row['status']?.toString() ?? 'Active',
      isPinned: row['is_pinned'] == 1 || row['is_pinned'] == true,
      lastMessageAt: row['last_message_at']?.toString(),
      modified: row['modified']?.toString(),
      language: row['language']?.toString(),
    );
  }

  ChatSession copyWith({
    String? title,
    String? assistantMode,
    String? status,
    bool? isPinned,
    String? language,
  }) {
    return ChatSession(
      name: name,
      title: title ?? this.title,
      assistantMode: assistantMode ?? this.assistantMode,
      status: status ?? this.status,
      isPinned: isPinned ?? this.isPinned,
      lastMessageAt: lastMessageAt,
      modified: modified,
      language: language ?? this.language,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.name,
    required this.role,
    required this.content,
    this.contentJson,
    this.creation,
    this.tokensIn,
    this.tokensOut,
  });

  final String name;
  final String role;
  final String content;
  final Map<String, dynamic>? contentJson;
  final String? creation;
  final int? tokensIn;
  final int? tokensOut;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory ChatMessage.fromApi(Map<dynamic, dynamic> row) {
    Map<String, dynamic>? cj;
    final raw = row['content_json'];
    if (raw is Map) {
      cj = Map<String, dynamic>.from(raw);
    }
    return ChatMessage(
      name: row['name']?.toString() ?? '',
      role: row['role']?.toString() ?? 'assistant',
      content: row['content']?.toString() ?? '',
      contentJson: cj,
      creation: row['creation']?.toString(),
      tokensIn: _asInt(row['tokens_in']),
      tokensOut: _asInt(row['tokens_out']),
    );
  }
}

class SendResult {
  const SendResult({
    required this.session,
    required this.content,
    this.messageName,
    this.assistantMode,
    this.needsConfirmation = false,
    this.confirmationMessage = '',
    this.pendingTool = '',
    this.pendingArgs = const {},
    this.needsPlanApproval = false,
    this.pendingPlan = const [],
    this.pendingAssumptions = const [],
    this.confirmationToken = '',
  });

  final String session;
  final String content;
  final String? messageName;
  final String? assistantMode;
  final bool needsConfirmation;
  final String confirmationMessage;
  final String pendingTool;
  final Map<String, dynamic> pendingArgs;
  final bool needsPlanApproval;
  final List<dynamic> pendingPlan;
  final List<dynamic> pendingAssumptions;
  final String confirmationToken;

  factory SendResult.fromApi(Map<dynamic, dynamic> data) {
    Map<String, dynamic> args = {};
    final rawArgs = data['pending_args'];
    if (rawArgs is Map) {
      args = Map<String, dynamic>.from(rawArgs);
    }
    return SendResult(
      session: data['session']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      messageName: data['message']?.toString(),
      assistantMode: data['assistant_mode']?.toString(),
      needsConfirmation:
          data['needs_confirmation'] == true || data['needs_confirmation'] == 1,
      confirmationMessage: data['confirmation_message']?.toString() ?? '',
      pendingTool: data['pending_tool']?.toString() ?? '',
      pendingArgs: args,
      needsPlanApproval:
          data['needs_plan_approval'] == true ||
          data['needs_plan_approval'] == 1,
      pendingPlan: data['pending_plan'] is List
          ? List<dynamic>.from(data['pending_plan'] as List)
          : const [],
      pendingAssumptions: data['pending_assumptions'] is List
          ? List<dynamic>.from(data['pending_assumptions'] as List)
          : const [],
      confirmationToken: data['confirmation_token']?.toString() ?? '',
    );
  }
}

class UiLocale {
  const UiLocale({required this.language, required this.languages});

  final String language;
  final List<UiLanguage> languages;

  factory UiLocale.fromApi(Map<dynamic, dynamic> data) {
    final langs = <UiLanguage>[];
    final raw = data['languages'];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) langs.add(UiLanguage.fromApi(row));
      }
    }
    return UiLocale(
      language: data['language']?.toString() ?? 'en',
      languages: langs,
    );
  }
}

class UiLanguage {
  const UiLanguage({
    required this.code,
    required this.label,
    this.native = '',
    this.dir = 'ltr',
  });

  final String code;
  final String label;
  final String native;
  final String dir;

  factory UiLanguage.fromApi(Map<dynamic, dynamic> row) {
    return UiLanguage(
      code: row['code']?.toString() ?? 'en',
      label: row['label']?.toString() ?? 'English',
      native: row['native']?.toString() ?? '',
      dir: row['dir']?.toString() ?? 'ltr',
    );
  }
}

const assistantModes = <String>[
  'Normal Chat',
  'ERP Assistant',
  'Document Assistant',
  'Analytics Assistant',
  'Developer Assistant',
  'Admin Assistant',
];

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}
