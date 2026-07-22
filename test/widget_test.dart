import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chat_ai/app.dart';

void main() {
  testWidgets('Chat AI app builds', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChatAiApp()));
    expect(find.text('Chat AI'), findsOneWidget);
  });
}
