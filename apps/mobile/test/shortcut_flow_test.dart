import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  testWidgets('Temporary permission dialog does not disable automatic actions',
      (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return '미디어 볼륨을 올렸습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const SignBridgeApp());
    final predict =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    predict(const SignPrediction('위', .99));
    expect(calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    predict(SignPrediction.fromDisplay('위 · 75%')!);
    await tester.pumpAndSettle();
    expect(calls.single.method, 'volumeUp');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('미디어 볼륨을 올렸습니다.'), findsOneWidget);
    predict(const SignPrediction('위', .99));
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    expect(find.text('번역: 위'), findsOneWidget);
    expect(find.text('미디어 볼륨을 올렸습니다.'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  testWidgets('Company registration validates and persists coordinates',
      (tester) async {
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
    await tester.pumpWidget(const SignBridgeApp());
    await tester.scrollUntilVisible(find.text('회사 위치 등록 / 변경'), 200);
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
    expect(calls.single.arguments['value'], contains('우리 회사'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  testWidgets('Permission errors appear and recognition pauses in background',
      (tester) async {
    var calls = 0;
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls++;
      throw PlatformException(
          code: 'permission_denied', message: '연락처 권한이 거부되었습니다.');
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const SignBridgeApp());
    final predict =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    predict(const SignPrediction('엄마', .99));
    expect(calls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    predict(const SignPrediction('엄마', .99));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('연락처 권한이 거부'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
