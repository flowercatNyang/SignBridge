import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';

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
  testWidgets('Camera page opens without automatically executing commands',
      (tester) async {
    await launch(tester);
    await tapVisible(tester, '수화 번역 카메라 시작');
    expect(find.text('실시간 손 인식'), findsOneWidget);
    expect(find.text('명령 실행'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.textContaining('Android 앱 또는 웹 브라우저'), findsOneWidget);
    await tapVisible(tester, '기록');
    expect(find.text('전화 끊어줘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Manual execution shows processing then completion and returns to camera',
      (tester) async {
    await launch(tester);
    await tapVisible(tester, '수화 번역 카메라 시작');
    await tester.ensureVisible(find.text('명령 실행'));
    await tester.tap(find.text('명령 실행'));
    await tester.pump();
    expect(find.text('명령 실행 중...'), findsOneWidget);
    expect(find.text('명령 실행 완료'), findsNothing);
    expect(find.textContaining('Android 앱 또는 웹 브라우저'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('명령 실행 완료'), findsOneWidget);
    await tapVisible(tester, '다시 인식하기');
    expect(find.text('실시간 손 인식'), findsOneWidget);
    await tester.ensureVisible(find.text('명령 실행'));
    await tester.tap(find.text('명령 실행'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tapVisible(tester, '확인');
    await tapVisible(tester, '기록');
    expect(find.text('전화 끊어줘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Leaving during processing cancels completion', (tester) async {
    await launch(tester);
    await tapVisible(tester, '긴급 상황 SOS');
    await tapVisible(tester, '수화 번역 카메라 시작');
    await tester.ensureVisible(find.text('명령 실행'));
    await tester.tap(find.text('명령 실행'));
    await tester.pump();
    expect(find.text('“도와주세요”'), findsOneWidget);
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

  testWidgets('SOS opens tracking only and adds no history', (tester) async {
    await launch(tester);
    await tapVisible(tester, '긴급 상황 SOS');
    await tapVisible(tester, '수화 번역 카메라 시작');
    expect(find.text('SOS · 손 인식 데모'), findsOneWidget);
    expect(find.text('명령 실행'), findsOneWidget);
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
