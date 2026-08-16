import 'package:ai_agent/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows AI Agent home', (tester) async {
    await tester.pumpWidget(const AiAgentApp());
    expect(find.text('AI Agent'), findsOneWidget);
    expect(find.text('Your Android coding agent'), findsOneWidget);
  });
}
