import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';
import 'widget_test.dart' show launch, tapVisible;

void main() {
  final calls = <MethodCall>[];
  const channel = MethodChannel('signbridge/actions');
  final binding = TestWidgetsFlutterBinding.ensureInitialized()
      as TestWidgetsFlutterBinding;
  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'loadPhone') return '01012345678';
      calls.add(call);
      return '실행 요청 완료';
    });
  });
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  Future<ValueChanged<SignPrediction>> open(WidgetTester tester) async {
    await launch(tester);
    await tapVisible(tester, '단축키 실행');
    await tapVisible(tester, '수화 번역 카메라 시작');
    return tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
  }

  testWidgets(
      'Cancel does not execute or immediately repeat the same prediction',
      (tester) async {
    final predict = await open(tester);
    predict(const SignPrediction('1', .99));
    await tester.pumpAndSettle();
    expect(find.text('이 명령이 맞을까요?'), findsOneWidget);
    expect(calls, isEmpty);
    await tapVisible(tester, '취소');
    predict(const SignPrediction('1', .99));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('이 명령이 맞을까요?'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Developer switch enables real shortcut buttons and disables them again',
      (tester) async {
    await launch(tester);
    await tapVisible(tester, '설정');
    await tapVisible(tester, '개발자 모드');
    await tapVisible(tester, '번역');
    await tapVisible(tester, '단축키 실행');
    await tapVisible(tester, '수화 번역 카메라 시작');
    await tapVisible(tester, '배달의민족 앱 열기');
    await tapVisible(tester, '실행');
    expect(calls.single.method, 'baemin');
    await tapVisible(tester, '설정');
    await tapVisible(tester, '개발자 모드');
    await tapVisible(tester, '번역');
    await tapVisible(tester, '수화 번역 카메라 시작');
    await tapVisible(tester, '배달의민족 앱 열기');
    expect(find.text('이 명령이 맞을까요?'), findsNothing);
    expect(calls.length, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Message passes saved recipient and entered body to the platform',
      (tester) async {
    final predict = await open(tester);
    predict(const SignPrediction('6', .99));
    await tester.pumpAndSettle();
    await tapVisible(tester, '실행');
    await tester.enterText(find.byType(TextField), '곧 도착해요 & 안녕하세요');
    await tapVisible(tester, '확인');
    expect(calls.single.method, 'message');
    expect(jsonDecode(calls.single.arguments['value'] as String),
        {'phone': '01012345678', 'body': '곧 도착해요 & 안녕하세요'});
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Message without a saved number shows a useful error',
      (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'loadPhone') return '';
      calls.add(call);
      return '';
    });
    final predict = await open(tester);
    predict(const SignPrediction('6', .99));
    await tester.pumpAndSettle();
    await tapVisible(tester, '실행');
    expect(find.textContaining('먼저 전화·메시지 번호를 등록'), findsOneWidget);
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  for (final cancel in [false, true]) {
    testWidgets('Timer digits produce 12 minutes 34 seconds; cancel=$cancel',
        (tester) async {
      final predict = await open(tester);
      predict(const SignPrediction('7', .99));
      await tester.pumpAndSettle();
      await tapVisible(tester, '실행');
      for (final digit in [1, 2, 3, 4]) {
        // Previous held signs cannot fill the next position automatically.
        predict(SignPrediction('$digit', .99));
        await tester.pumpAndSettle();
        expect(find.text('이 숫자가 맞을까요?'), findsNothing);
        await tapVisible(tester, '다음 숫자 인식');
        predict(SignPrediction('$digit', .99));
        await tester.pumpAndSettle();
        await tapVisible(tester, '입력');
      }
      expect(find.text('12분 34초'), findsOneWidget);
      expect(calls, isEmpty);
      await tapVisible(tester, cancel ? '취소' : '실행');
      if (cancel) {
        expect(calls, isEmpty);
      } else {
        expect(calls.single.method, 'timer');
        expect(calls.single.arguments['value'], '754');
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets(
      'Timer accepts zero button, rejects invalid seconds and zero duration',
      (tester) async {
    final predict = await open(tester);
    predict(const SignPrediction('7', .99));
    await tester.pumpAndSettle();
    await tapVisible(tester, '실행');
    for (var i = 0; i < 4; i++) {
      await tapVisible(tester, '다음 숫자 인식');
      if (i == 2) {
        predict(const SignPrediction('6', .99));
        await tester.pumpAndSettle();
        await tester.drag(
            find.byType(Scrollable).hitTestable().first, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(find.text('초의 십의 자리는 0~5만 입력할 수 있습니다.'), findsOneWidget);
      }
      await tapVisible(tester, '0 입력');
      await tapVisible(tester, '입력');
    }
    await tester.drag(
        find.byType(Scrollable).hitTestable().first, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('1초 이상 입력해 주세요.'), findsOneWidget);
    expect(calls, isEmpty);
    await tapVisible(tester, '타이머 취소');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
