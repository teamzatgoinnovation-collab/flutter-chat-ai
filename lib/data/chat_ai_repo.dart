import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

import '../models/chat_models.dart';
import '../services/session.dart';

class ChatAiRepo {
  List<ChatSession> sessions = [];
  List<ChatMessage> messages = [];
  UiLocale? locale;
  SendResult? pendingConfirmation;

  Future<List<ChatSession>> listSessions(ChatAiSession session) async {
    final env = await session.store.callMethod(
      ZatGoApiMethods.chatAiListSessions,
      args: {'status': 'Active'},
    );
    final rows = env.data is List ? env.data as List : const [];
    sessions = [
      for (final row in rows)
        if (row is Map) ChatSession.fromApi(row),
    ];
    return sessions;
  }

  Future<String> newSession(
    ChatAiSession session, {
    String? title,
    String? assistantMode,
    String? language,
  }) async {
    final env = await session.store.callMethod(
      ZatGoApiMethods.chatAiNewSession,
      args: {
        'title': ?title,
        'assistant_mode': ?assistantMode,
        'language': ?language,
      },
    );
    final data = env.data is Map ? env.data as Map : const {};
    final name = data['name']?.toString() ?? '';
    if (name.isEmpty) {
      throw ZatGoApiError(code: 'NO_SESSION', message: 'No session created');
    }
    await listSessions(session);
    return name;
  }

  Future<List<ChatMessage>> history(
    ChatAiSession session,
    String sessionName, {
    int limit = 50,
  }) async {
    final env = await session.store.callMethod(
      ZatGoApiMethods.chatAiHistory,
      args: {'session': sessionName, 'limit': limit},
    );
    final rows = env.data is List ? env.data as List : const [];
    messages = [
      for (final row in rows)
        if (row is Map) ChatMessage.fromApi(row),
    ];
    return messages;
  }

  Future<SendResult> send(
    ChatAiSession session, {
    required String message,
    String? sessionName,
    int confirmed = 0,
    int planConfirmed = 0,
    String? pendingTool,
    Map<String, dynamic>? pendingArgs,
    String? confirmationToken,
  }) async {
    final env = await session.store.callMethod(
      ZatGoApiMethods.chatAiSend,
      args: {
        if (sessionName != null && sessionName.isNotEmpty) 'session': sessionName,
        'message': message,
        'confirmed': confirmed,
        'plan_confirmed': planConfirmed,
        if (pendingTool != null && pendingTool.isNotEmpty)
          'pending_tool': pendingTool,
        'pending_args': ?pendingArgs,
        if (confirmationToken != null && confirmationToken.isNotEmpty)
          'confirmation_token': confirmationToken,
      },
    );
    final data = env.data is Map ? env.data as Map : <dynamic, dynamic>{};
    final result = SendResult.fromApi(data);
    if (result.needsConfirmation || result.needsPlanApproval) {
      pendingConfirmation = result;
    } else {
      pendingConfirmation = null;
    }
    return result;
  }

  Future<UiLocale> getUiLocale(ChatAiSession session) async {
    final env = await session.store.callMethod(
      ZatGoApiMethods.chatAiGetUiLocale,
    );
    final data = env.data is Map ? env.data as Map : <dynamic, dynamic>{};
    locale = UiLocale.fromApi(data);
    return locale!;
  }

  Future<void> setLanguage(
    ChatAiSession session, {
    required String sessionName,
    required String language,
  }) async {
    await session.store.callMethod(
      ZatGoApiMethods.chatAiSetLanguage,
      args: {'session': sessionName, 'language': language},
    );
  }

  Future<void> setMode(
    ChatAiSession session, {
    required String sessionName,
    required String assistantMode,
  }) async {
    await session.store.callMethod(
      ZatGoApiMethods.chatAiSetMode,
      args: {'session': sessionName, 'assistant_mode': assistantMode},
    );
    final i = sessions.indexWhere((s) => s.name == sessionName);
    if (i >= 0) {
      sessions[i] = sessions[i].copyWith(assistantMode: assistantMode);
    }
  }

  Future<void> rename(
    ChatAiSession session, {
    required String sessionName,
    required String title,
  }) async {
    await session.store.callMethod(
      ZatGoApiMethods.chatAiRename,
      args: {'session': sessionName, 'title': title},
    );
    await listSessions(session);
  }

  Future<void> archive(ChatAiSession session, String sessionName) async {
    await session.store.callMethod(
      ZatGoApiMethods.chatAiArchive,
      args: {'session': sessionName},
    );
    await listSessions(session);
  }

  Future<void> deleteSession(ChatAiSession session, String sessionName) async {
    await session.store.callMethod(
      ZatGoApiMethods.chatAiDeleteSession,
      args: {'session': sessionName},
    );
    await listSessions(session);
  }

  Future<void> clear(ChatAiSession session, String sessionName) async {
    await session.store.callMethod(
      ZatGoApiMethods.chatAiClear,
      args: {'session': sessionName},
    );
    messages = [];
  }
}

final chatAiRepoProvider = Provider<ChatAiRepo>((ref) => ChatAiRepo());

/// Bumps when chat UI should reload lists / transcript.
final chatUiTickProvider = StateProvider<int>((ref) => 0);

void bumpChatUi(WidgetRef ref) {
  ref.read(chatUiTickProvider.notifier).state++;
}
