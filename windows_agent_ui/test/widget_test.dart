import 'package:flutter_test/flutter_test.dart';
import 'package:windows_agent_ui/main.dart';

void main() {
  testWidgets('App should render without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const DriveSyncApp());
    expect(find.text('AGENT AUTHENTICATION'), findsOneWidget);
  });
}
