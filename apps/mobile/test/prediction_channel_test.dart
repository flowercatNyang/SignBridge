import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';

void main() {
  testWidgets('Native channel accumulates mom without making a phone call', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? viewId;
    final actions = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const actionChannel = MethodChannel('signbridge/actions');
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method == 'create') { viewId = call.arguments['id'] as int; return 0; }
      if (call.method == 'resize') return {
        'width': call.arguments['width'], 'height': call.arguments['height'],
      };
      return null;
    });
    messenger.setMockMethodCallHandler(actionChannel, (call) async {
      actions.add(call.method); return '';
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      messenger.setMockMethodCallHandler(actionChannel, null);
    });
    await tester.pumpWidget(const SignBridgeApp());
    expect(find.byType(HandCamera), findsNothing);
    await tester.ensureVisible(find.text('수어 입력 시작'));
    await tester.tap(find.text('수어 입력 시작'));
    await tester.pumpAndSettle();
    expect(viewId, isNotNull);
    for (var i = 0; i < 10; i++) {
      final done = Completer<void>();
      const codec = StandardMethodCodec();
      messenger.handlePlatformMessage('signbridge/predictions/$viewId',
        codec.encodeMethodCall(const MethodCall('prediction', {
          'display': '엄마 · 99%', 'handsAbsent': false,
        })), (reply) { if (reply != null) codec.decodeEnvelope(reply); done.complete(); });
      await tester.pump(); await done.future;
    }
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('assistant-input'))).controller!.text, '엄마');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.byType(HandCamera), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(HandCamera), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
