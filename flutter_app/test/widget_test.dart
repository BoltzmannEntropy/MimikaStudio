import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimika_studio/main.dart';

void main() {
  testWidgets('app bootstraps and shows backend status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MimikaStudioApp());

    // Initial bootstrap state.
    expect(find.text('Connecting to backend...'), findsOneWidget);

    // Health check resolves to disconnected in test env.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Backend not connected'), findsOneWidget);

    // Dispose tree and allow pending polling timer to drain.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
