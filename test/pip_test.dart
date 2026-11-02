import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'home_test_helpers.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  const pip = MethodChannel('signbridge/pip');
  const actions = MethodChannel('signbridge/actions');
  const background = MethodChannel('signbridge/background');

  Future<void> changePip(WidgetTester tester, bool active) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        pip.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('changed', active)),
        (_) {});
    await tester.pumpAndSettle();
  }

  void mockViews(WidgetTester tester) {
    var enabled = false, pipEnabled = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(background,
        (call) async {
      if (call.method == 'setEnabled') enabled = call.arguments == true;
      if (call.method == 'setPip') pipEnabled = call.arguments == true;
      if (call.method == 'hide') return true;
      return {'enabled': enabled, 'pipEnabled': pipEnabled};
    });
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method == 'create') return 1;
      if (call.method == 'resize') {
        return {
          'width': call.arguments['width'],
          'height': call.arguments['height']
        };
      }
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pip, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(background, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(actions, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
  }

  testWidgets(
      'PiP preserves the camera and leaves background actions to native service',
      (tester) async {
    mockViews(tester);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pip, (call) async => true);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(actions,
        (call) async {
      calls.add(call.method);
      return '완료';
    });
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    await tester.pumpAndSettle();
    final cameraState = tester.state(find.byType(HandCamera));
    final initialPredict =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    initialPredict(const SignPrediction('아래', .99));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('백그라운드 실행'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(tester.state(find.byType(HandCamera)), same(cameraState));
    await changePip(tester, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final predict =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    predict(const SignPrediction('위', .99));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    predict(const SignPrediction('아래', .99));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await changePip(tester, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('백그라운드 실행'), findsOneWidget);
    expect(tester.state(find.byType(HandCamera)), same(cameraState));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Developer mode disables PiP entry', (tester) async {
    mockViews(tester);
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    await tester.pumpAndSettle();
    final developer = find.widgetWithText(SwitchListTile, '개발자 모드');
    await tester.ensureVisible(developer);
    await tester.tap(developer);
    await tester.pumpAndSettle();
    expect(find.byType(HandCamera), findsNothing);
    await tester.scrollUntilVisible(find.text('백그라운드 실행'), -200);
    final button = find.ancestor(
        of: find.text('백그라운드 실행'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'PiP off starts the service and hides the app without entering PiP',
      (tester) async {
    mockViews(tester);
    var enabled = false, pipEnabled = true;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(background,
        (call) async {
      calls.add(call.method);
      if (call.method == 'setEnabled') enabled = call.arguments == true;
      if (call.method == 'setPip') pipEnabled = call.arguments == true;
      if (call.method == 'hide') return true;
      return {'enabled': enabled, 'pipEnabled': pipEnabled};
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pip,
        (call) async {
      calls.add('pip:${call.method}');
      return true;
    });
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '백그라운드에서 PiP 표시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('백그라운드 실행'));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(pipEnabled, isFalse);
    expect(calls, containsAllInOrder(['setPip', 'setEnabled', 'hide']));
    expect(calls, isNot(contains('pip:enter')));
    expect(find.byType(AppBar), findsOneWidget);

    // The notification stop button updates the switch through the service event.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        background.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall(
            'changed', {'enabled': false, 'pipEnabled': false})),
        (_) {});
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '백그라운드 인식'))
            .value,
        isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'Service start failure keeps background off and does not enter PiP',
      (tester) async {
    mockViews(tester);
    var pipCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(background,
        (call) async {
      if (call.method == 'setEnabled') {
        throw PlatformException(
            code: 'camera_unavailable', message: '카메라 준비 필요');
      }
      return {'enabled': false, 'pipEnabled': true};
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pip,
        (call) async {
      pipCalls++;
      return true;
    });
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    await tester.tap(find.text('백그라운드 실행'));
    await tester.pumpAndSettle();
    expect(pipCalls, 0);
    expect(find.text('카메라 준비 필요'), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '백그라운드 인식'))
            .value,
        isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'Returning from background does not repeat the service last command',
      (tester) async {
    mockViews(tester);
    final calls = <String>[];
    String? lastCommand;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        background,
        (call) async =>
            {'enabled': true, 'pipEnabled': false, 'lastCommand': lastCommand});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(actions,
        (call) async {
      calls.add(call.method);
      return '완료';
    });
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    lastCommand = 'volumeUp';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final predict =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    predict(const SignPrediction('위', .99));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    predict(const SignPrediction('아래', .99));
    await tester.pumpAndSettle();
    expect(calls, ['volumeDown']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final failure in [false, true]) {
    testWidgets('PiP rejection restores shortcut screen (exception: $failure)',
        (tester) async {
      mockViews(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pip,
          (call) async {
        if (failure) {
          throw PlatformException(code: 'unsupported', message: 'PiP 미지원');
        }
        return false;
      });
      await tester.pumpWidget(const SignBridgeApp());
      await openShortcuts(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('백그라운드 실행'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(HandCamera), findsOneWidget);
      expect(
          find.text(failure
              ? 'PiP 미지원'
              : 'PiP를 열 수 없습니다. 앱 설정에서 화면 속 화면 권한을 확인해 주세요.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
