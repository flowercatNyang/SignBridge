import 'package:flutter_test/flutter_test.dart';

Future<void> openShortcuts(WidgetTester tester) async {
  await tester.tap(find.byTooltip('메뉴'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('단축키 실행').last);
  await tester.pumpAndSettle();
}
