import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'package:testsign/src/assistant_page.dart';
import 'package:testsign/src/alarm_page.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'home_test_helpers.dart';

void main() {
  testWidgets('Home opens assistant and digit alarms without starting the camera', (tester) async {
    await tester.pumpWidget(const SignBridgeApp());
    expect(find.byType(DemoHome), findsOneWidget);
    expect(find.byType(HandCamera), findsNothing);
    await openAssistant(tester);
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(find.byType(HandCamera), findsNothing);
    final button = find.byKey(const Key('assistant-alarm-wizard'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AlarmPage), findsOneWidget);
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
  });
}
