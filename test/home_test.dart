import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/translation.dart';
import 'package:testsign/src/assistant_page.dart';

void main() {
  testWidgets('Launch shows home; only starting recognition opens camera',
      (tester) async {
    await tester.pumpWidget(const SignBridgeApp());
    await tester.pumpAndSettle();
    expect(find.text('안녕하세요, 서연님 👋'), findsOneWidget);
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
    expect(find.byType(TranslationPage, skipOffstage: false), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    await tester.scrollUntilVisible(find.text('수화 번역 카메라 시작'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('수화 번역 카메라 시작'));
    await tester.pumpAndSettle();
    expect(find.byType(HandCamera), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DemoHome), findsOneWidget);
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Home tabs restore devices, history and settings without camera',
      (tester) async {
    await tester.pumpWidget(const SignBridgeApp());
    for (final entry
        in {'기기': '연결된 기기', '기록': '사용 기록', '설정': '알림 표시'}.entries) {
      await tester.tap(find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(entry.key)));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsWidgets);
      expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home menu opens assistant without starting shortcut camera',
      (tester) async {
    await tester.pumpWidget(const SignBridgeApp());
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(Drawer), matching: find.text('LLM 비서')));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DemoHome), findsOneWidget);
  });
}
