import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/translation.dart';
import 'package:testsign/src/assistant_page.dart';
import 'package:testsign/src/assistant_client.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  testWidgets(
      'Recognition submits on yes and keeps the assistant beside the camera',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final requests = <String>[];
    await tester
        .pumpWidget(MaterialApp(home: TranslationPage(assistantRequest: ({
      required String baseUrl,
      required String accessToken,
      required String text,
      required String inputType,
      required List<Map<String, String>> history,
    }) async {
      requests.add(text);
      return const AssistantReply(
          translation: '엄마', question: '어떤 요청인가요?', action: null, mode: 'mock');
    })));
    await tester.pumpAndSettle();
    final cameraState = tester.state(find.byType(HandCamera));
    final predict =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    for (var i = 0; i < 3; i++) {
      predict(const SignPrediction('엄마', .99));
    }
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    final assistant =
        tester.state<AssistantPageState>(find.byType(AssistantPage));
    final now = DateTime.now();
    assistant.acceptPrediction(const SignPrediction('', 0, handsAbsent: true),
        timestamp: now);
    assistant.acceptPrediction(const SignPrediction('', 0, handsAbsent: true),
        timestamp: now.add(const Duration(milliseconds: 900)));
    for (var i = 0; i < 3; i++) {
      predict(const SignPrediction('그렇다', .99));
    }
    await tester.pumpAndSettle();
    expect(requests, ['엄마']);
    expect(tester.widget<AssistantPage>(find.byType(AssistantPage)).embedded,
        isTrue);
    expect(tester.state(find.byType(HandCamera)), same(cameraState));
    expect(find.byKey(const Key('recognition-submit')), findsNothing);
    expect(find.byKey(const Key('assistant-submit')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Company registration remains available', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'loadCompany') return '';
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: TranslationPage()));
    await tester.ensureVisible(find.text('회사 위치 등록 / 변경'));
    await tester.tap(find.text('회사 위치 등록 / 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.enterText(find.byType(TextField).at(0), '우리 회사');
    await tester.enterText(find.byType(TextField).at(1), '37.5665');
    await tester.enterText(find.byType(TextField).at(2), '126.978');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'saveCompany');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
