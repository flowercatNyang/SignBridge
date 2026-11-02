import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/translation.dart';
import 'package:testsign/src/assistant_page.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  testWidgets('Legacy recognition forwards mom into assistant without calling', (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call); return '';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: TranslationPage()));
    final predict = tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    predict(const SignPrediction('엄마', .99));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('assistant-input'))).controller!.text, '엄마');
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Company registration remains available', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadCompany') return '';
      calls.add(call); return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: TranslationPage()));
    await tester.ensureVisible(find.text('회사 위치 등록 / 변경'));
    await tester.tap(find.text('회사 위치 등록 / 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.enterText(find.byType(TextField).at(0), '우리 회사');
    await tester.enterText(find.byType(TextField).at(1), '37.5665');
    await tester.enterText(find.byType(TextField).at(2), '126.978');
    await tester.tap(find.text('저장')); await tester.pumpAndSettle();
    expect(calls.single.method, 'saveCompany');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
