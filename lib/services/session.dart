import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zatgo_dart_sdk/zatgo_dart_sdk.dart';

class ChatAiSession extends ChangeNotifier {
  ChatAiSession() {
    final base = const String.fromEnvironment(
      'FRAPPE_BASE_URL',
      defaultValue: 'https://demo.zatgo.online',
    );
    baseUrl = base.replaceAll(RegExp(r'/$'), '');
  }

  final ErpnextSessionStore store = ErpnextSessionStore();

  String baseUrl = 'https://demo.zatgo.online';
  String? user;
  String? fullName;
  String? lastError;

  /// Active chat session name on the server (AI Chat Session).
  String? activeSessionName;

  bool get connected => store.connected;
  bool get canEnterApp => connected;

  void updateBaseUrl(String value) {
    baseUrl = value.replaceAll(RegExp(r'/$'), '');
    notifyListeners();
  }

  void setActiveSession(String? name) {
    activeSessionName = name;
    notifyListeners();
  }

  Future<ErpnextLoginResult> login({
    required String usr,
    required String pwd,
  }) async {
    final result = await store.login(baseUrl: baseUrl, usr: usr, pwd: pwd);
    if (result is ErpnextLoginOk) {
      user = result.session.user;
      fullName = result.session.fullName;
      baseUrl = result.session.baseUrl;
      lastError = null;
    } else if (result is ErpnextLoginFail) {
      user = null;
      fullName = null;
      lastError = result.message;
    }
    notifyListeners();
    return result;
  }

  Future<void> logout() async {
    await store.logout();
    user = null;
    fullName = null;
    lastError = null;
    activeSessionName = null;
    notifyListeners();
  }

  Future<ErpnextPingResult> ping() => erpnextPing(baseUrl);
}

final chatAiSessionProvider = ChangeNotifierProvider<ChatAiSession>((ref) {
  return ChatAiSession();
});
