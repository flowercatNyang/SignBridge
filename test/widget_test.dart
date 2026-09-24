import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'package:flutter/services.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

Future<void> launch(WidgetTester tester,
    {Size size = const Size(390, 844), double scale = 1}) async {
  tester.binding.window.physicalSizeTestValue = size;
  tester.binding.window.devicePixelRatioTestValue = 1;
  tester.binding.window.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.window.clearPhysicalSizeTestValue();
    tester.binding.window.clearDevicePixelRatioTestValue();
    tester.binding.window.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(const SignBridgeApp());
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String label) async {
  final finder = ['번역', '기기', '기록', '설정'].contains(label)
      ? find.descendant(
          of: find.byType(BottomNavigationBar), matching: find.text(label))
      : find.text(label);
  for (int attempt = 0; finder.evaluate().isEmpty && attempt < 10; attempt++) {
    await tester.drag(
        find.byType(Scrollable).hitTestable().first, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  for (var number = 1; number <= 4; number++) {
    testWidgets('Shortcut $number invokes the correct platform action',
        (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('signbridge/actions');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'loadPhone') return '01012345678';
        calls.add(call);
        return '실행 요청 완료';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await launch(tester);
      await tapVisible(tester, '단축키 실행');
      await tapVisible(tester, '수화 번역 카메라 시작');
      final callback =
          tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
      for (var i = 0; i < 1; i++) {
        callback(SignPrediction('$number', .99));
      }
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tapVisible(tester, '실행');
      expect(calls.length, 1);
      expect(
          calls.single.method, ['dial', 'dial', 'call', 'baemin'][number - 1]);
      expect(calls.single.arguments['value'],
          ['112', '119', '01012345678', ''][number - 1]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
  testWidgets('Shortcut five translates the entered Korean text',
      (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return '영어 번역 페이지를 열었습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await launch(tester);
    await tapVisible(tester, '단축키 실행');
    await tapVisible(tester, '수화 번역 카메라 시작');
    final callback =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    for (var i = 0; i < 3; i++) {
      callback(const SignPrediction('5', .99));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, isEmpty);
    await tapVisible(tester, '실행');
    await tester.enterText(find.byType(TextField), '도움이 필요해요');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'translate');
    expect(calls.single.arguments['value'], '도움이 필요해요');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Platform failure is shown without reporting success',
      (tester) async {
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      throw PlatformException(
          code: 'permission_denied', message: '전화 권한이 거부되었습니다.');
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await launch(tester);
    await tapVisible(tester, '수화 번역 카메라 시작');
    final callback =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    for (var i = 0; i < 3; i++) {
      callback(const SignPrediction('전화 끊어줘', .99));
    }
    await tester.pumpAndSettle();
    await tapVisible(tester, '실행');
    expect(find.textContaining('전화 권한이 거부되었습니다.'), findsOneWidget);
    expect(find.text('통화를 종료했습니다.'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Camera page opens without automatically executing commands',
      (tester) async {
    await launch(tester);
    await tapVisible(tester, '수화 번역 카메라 시작');
    expect(find.text('실시간 손 인식'), findsOneWidget);
    expect(find.text('인식 대기 중'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.textContaining('Android 앱 또는 웹 브라우저'), findsOneWidget);
    await tapVisible(tester, '기록');
    expect(find.text('전화 끊어줘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Recognized call command executes once and can be rearmed',
      (tester) async {
    var calls = 0;
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expectSync(call.method, 'endCall');
      calls++;
      return '통화를 종료했습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await launch(tester);
    await tapVisible(tester, '수화 번역 카메라 시작');
    final callback =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    for (var i = 0; i < 10; i++) {
      callback(const SignPrediction('통화 종료해줘', .99));
    }
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tapVisible(tester, '실행');
    expect(calls, 1);
    expect(find.text('통화를 종료했습니다.'), findsOneWidget);
    await tapVisible(tester, '다시 인식하기');
    for (var i = 0; i < 3; i++) {
      callback(const SignPrediction('전화 끊어줘', .99));
    }
    await tester.pumpAndSettle();
    await tapVisible(tester, '실행');
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Reserved shortcut does not call the platform', (tester) async {
    await launch(tester);
    await tapVisible(tester, '단축키 실행');
    await tapVisible(tester, '수화 번역 카메라 시작');
    final callback =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    for (var i = 0; i < 3; i++) {
      callback(const SignPrediction('8', .99));
    }
    await tester.pumpAndSettle();
    await tapVisible(tester, '실행');
    expect(find.text('8번: 미정 · 아직 기능이 없습니다.'), findsOneWidget);
    await tapVisible(tester, '기록');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('명령 실행 완료'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Menu service guide opens details and returns through bottom navigation',
      (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapVisible(tester, '서비스 안내');
    expect(find.text('동작 가이드'), findsOneWidget);
    await tapVisible(tester, '상세 가이드');
    expect(find.text('동작 상세 가이드'), findsOneWidget);
    await tapVisible(tester, '영상 보기');
    await tapVisible(tester, '다음 동작');
    expect(find.text('2 / 3'), findsOneWidget);
    await tapVisible(tester, '닫기');
    await tapVisible(tester, '기기');
    expect(find.text('연결된 기기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Device toggle persists across tabs and history deletion supports cancel',
      (tester) async {
    await launch(tester);
    await tapVisible(tester, '기기');
    for (final device in ['내 스마트폰', '스마트링', '무선 이어폰', '스마트워치']) {
      expect(find.text(device), findsOneWidget);
    }
    for (final removed in ['거실 전등', '에어컨', '거실 TV']) {
      expect(find.text(removed), findsNothing);
    }
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
    await tapVisible(tester, '설정');
    await tapVisible(tester, '사용 기록 지우기');
    await tapVisible(tester, '취소');
    await tapVisible(tester, '기록');
    expect(find.text('전화 끊어줘'), findsOneWidget);
    await tapVisible(tester, '설정');
    await tapVisible(tester, '사용 기록 지우기');
    await tapVisible(tester, '삭제');
    await tapVisible(tester, '기록');
    expect(find.text('아직 사용 기록이 없어요'), findsOneWidget);
    await tapVisible(tester, '기기');
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Shortcut mode opens without executing a command',
      (tester) async {
    await launch(tester);
    await tapVisible(tester, '단축키 실행');
    await tapVisible(tester, '수화 번역 카메라 시작');
    expect(find.text('단축키 · 숫자 수어 1~9'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('기본 수어 모델로 숫자 1~9를 인식합니다. 현재 모델의 정확도는 개선 중입니다.'), 300);
    expect(find.textContaining('모델에 없는'), findsNothing);
    expect(find.text('인식 대기 중'), findsOneWidget);
    await tapVisible(tester, '기록');
    expect(find.text('도와주세요'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Small screens with enlarged text remain scrollable without overflow',
      (tester) async {
    await launch(tester, size: const Size(320, 640), scale: 1.4);
    for (final label in ['기기', '기록', '설정', '번역']) {
      await tapVisible(tester, label);
      expect(tester.takeException(), isNull);
    }
    await tapVisible(tester, '수화 번역 카메라 시작');
    expect(find.text('손 동작 인식'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
