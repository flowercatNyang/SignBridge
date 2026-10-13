import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/demo_app.dart';

void main() {
  for (final resume in [false, true]) {
    testWidgets('Camera channel auto-executes new words (resume=$resume)',
        (tester) async {
      int? viewId;
      final actions = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      const actionChannel = MethodChannel('signbridge/actions');
      messenger.setMockMethodCallHandler(SystemChannels.platform_views,
          (call) async {
        if (call.method == 'create') {
          viewId = call.arguments['id'] as int;
          return 0;
        }
        if (call.method == 'resize') {
          return {
            'width': call.arguments['width'],
            'height': call.arguments['height'],
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(actionChannel, (call) async {
        actions.add(call.method);
        return '실행 완료';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        messenger.setMockMethodCallHandler(actionChannel, null);
      });
      await tester.pumpWidget(const SignBridgeApp());
      await tester.pumpAndSettle();
      expect(viewId, isNotNull);
      Future<void> send(String display) async {
        final done = Completer<void>();
        const codec = StandardMethodCodec();
        messenger.handlePlatformMessage(
            'signbridge/predictions/$viewId',
            codec.encodeMethodCall(MethodCall('prediction', {
              'display': display,
              'handsAbsent': false,
            })), (reply) {
          if (reply != null) codec.decodeEnvelope(reply);
          done.complete();
        });
        await tester.pump();
        await done.future;
        await tester.pumpAndSettle();
      }

      if (resume) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await send('위 · 99%');
        expect(actions, isEmpty);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
      }
      await send('위 · 74%');
      expect(actions, isEmpty);
      await send('위 · 75%');
      expect(actions, ['volumeUp']);
      await send('위 · 99%');
      expect(actions, ['volumeUp']);
      await send('아래 · 95%');
      expect(actions, ['volumeUp', 'volumeDown']);
      await send('회사 · 95%');
      await send('엄마 · 95%');
      await send('아프다 · 95%');
      expect(actions,
          ['volumeUp', 'volumeDown', 'company', 'mother', 'emergency']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
