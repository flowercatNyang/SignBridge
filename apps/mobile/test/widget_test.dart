import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  for (final entry in shortcutCommands.entries) {
    testWidgets('Developer button ${entry.key} invokes ${entry.value}',
        (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('signbridge/actions');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call);
        return '테스트 실행 완료';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(const SignBridgeApp());
      expect(find.text('테스트: ${entry.key}'), findsNothing);
      final predict =
          tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byType(HandCamera), findsNothing);
      predict(SignPrediction(entry.key, .99));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.ensureVisible(find.text('테스트: ${entry.key}'));
      await tester.tap(find.text('테스트: ${entry.key}'));
      await tester.pumpAndSettle();
      expect(calls.single.method, entry.value);
      // Each button press can repeat a test without camera rearming.
      await tester.tap(find.text('테스트: ${entry.key}'));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      await tester.scrollUntilVisible(find.byType(Switch), -200);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('테스트: ${entry.key}'), findsNothing);
      predict(SignPrediction(entry.key, .99));
      await tester.pumpAndSettle();
      expect(calls.length, 3);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
  for (final entry in shortcutCommands.entries) {
    testWidgets('${entry.key} automatically runs ${entry.value} once',
        (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('signbridge/actions');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call);
        return '실행 요청 완료';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(const SignBridgeApp());
      await tester.pumpAndSettle();
      final predict =
          tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
      predict(SignPrediction(entry.key, .749));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      for (var i = 0; i < 10; i++) {
        predict(SignPrediction(entry.key, .75));
      }
      await tester.pumpAndSettle();
      expect(calls.single.method, entry.value);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.text('다시 인식하기'));
      await tester.tap(find.text('다시 인식하기'));
      await tester.pumpAndSettle();
      predict(SignPrediction(entry.key, .99));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
  testWidgets('Menu contains shortcuts and the LLM assistant', (tester) async {
    await tester.pumpWidget(const SignBridgeApp());
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(Drawer), matching: find.byType(ListTile)),
        findsNWidgets(2));
    expect(find.text('LLM 비서'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    for (final text in ['기기', '기록', '설정', '서비스 안내']) {
      expect(find.text(text), findsNothing);
    }
  });
}
