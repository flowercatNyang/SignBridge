import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/assistant_client.dart';
import 'package:testsign/src/assistant_page.dart';
import 'package:testsign/src/alarm_page.dart';

Future<void> largeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('Background input is imported as gloss and never executed on arrival', (tester) async {
    await largeSurface(tester);
    final calls = <MethodCall>[];
    final requests = <String>[];
    const background = MethodChannel('signbridge/background');
    const actions = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(background, (call) async {
      if (call.method == 'takeInput') return '엄마 나 아프다';
      return {'enabled': false};
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(actions, (call) async {
      calls.add(call); return '';
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(background, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(actions, null);
    });
    await tester.pumpWidget(MaterialApp(home: AssistantPage(request: ({
      required String baseUrl, required String accessToken, required String text,
      required String inputType, required List<Map<String, String>> history,
    }) async {
      requests.add('$inputType:$text');
      return const AssistantReply(translation: '나 아파', question: '엄마에게 문자로 전달할까요?', action: null, mode: 'mock');
    })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assistant-background-input')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty); expect(requests, isEmpty);
    expect(tester.widget<TextField>(find.byKey(const Key('assistant-input'))).controller!.text, '엄마 나 아프다');
    await tester.tap(find.byKey(const Key('assistant-submit')));
    await tester.pumpAndSettle();
    expect(requests, ['gloss:엄마 나 아프다']);
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Direction up needs approval and changes volume exactly once', (tester) async {
    await largeSurface(tester);
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call); return '미디어 볼륨을 올렸습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: AssistantPage(developerMode: true, request: ({
      required String baseUrl, required String accessToken, required String text,
      required String inputType, required List<Map<String, String>> history,
    }) async {
      expect(text, '위(방향)');
      return AssistantReply(translation: '미디어 볼륨을 올려 주세요.', question: null, mode: 'mock',
        action: AssistantAction.fromJson({'name': 'adjust_volume', 'arguments': {'direction': 'up'}}));
    })));
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
    }
    await tap(find.byKey(const Key('gloss-word-위(방향)')));
    expect(calls, isEmpty);
    await tap(find.byKey(const Key('assistant-submit')));
    expect(calls, isEmpty);
    await tap(find.byKey(const Key('gloss-word-그렇다')));
    expect(calls.single.method, 'adjust_volume');
    expect(jsonDecode(calls.single.arguments['value'] as String), {'direction': 'up'});
    await tap(find.byKey(const Key('gloss-word-그렇다')));
    expect(calls.length, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('Dated action validates calendar dates and repeat exclusivity', () {
    Map<String, dynamic> args(String date) => {
      'hour': 13, 'minute': 5, 'days': <int>[], 'label': '', 'date': date,
    };
    AssistantAction action(Map<String, dynamic> value) =>
        AssistantAction.fromJson({'name': 'set_alarm', 'arguments': value});
    expect(action(args('2028-02-29')).summary, contains('2028-02-29'));
    for (final invalid in ['2027-02-29', '2026-02-30', '2026-13-01', '2026-2-01']) {
      expect(() => action(args(invalid)), throwsFormatException);
    }
    expect(() => action(args('2028-02-29')..['days'] = [1]), throwsFormatException);
    expect(() => AssistantAction.fromJson({'name': 'shell', 'arguments': {}}), throwsFormatException);
  });

  testWidgets('Mom tokens never execute and rejection discards the plan', (tester) async {
    await largeSurface(tester);
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call); return '작성 화면을 열었습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: AssistantPage(developerMode: true, request: ({
      required String baseUrl, required String accessToken, required String text,
      required String inputType, required List<Map<String, String>> history,
    }) async {
      expect(text, '엄마 나 아프다');
      return AssistantReply(translation: '엄마에게 나 아프다는 문자 작성', question: null,
        mode: 'mock', action: AssistantAction('compose_message', {'recipient': '엄마', 'body': '나 아파'}));
    })));
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
    }
    Future<void> request() async {
      for (final word in ['엄마', '나', '아프다']) await tap(find.byKey(Key('gloss-word-$word')));
      expect(calls, isEmpty);
      await tap(find.byKey(const Key('assistant-submit')));
      expect(calls, isEmpty);
    }
    await request();
    await tap(find.byKey(const Key('gloss-word-틀리다')));
    expect(find.byKey(const Key('assistant-execute')), findsNothing);
    expect(calls, isEmpty);
    await request();
    await tap(find.byKey(const Key('gloss-word-그렇다')));
    expect(calls.single.method, 'compose_message');
    expect(jsonDecode(calls.single.arguments['value'] as String)['recipient'], '엄마');
    expect(find.byKey(const Key('assistant-execute')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Alarm wizard keeps digits separate and executes once after confirmation', (tester) async {
    await largeSurface(tester);
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call); return '날짜 알림을 예약했습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: AlarmPage(developerMode: true)));
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
    }
    for (final digit in ['1', '3', '0', '5']) await tap(find.byKey(Key('alarm-digit-$digit')));
    await tap(find.byKey(const Key('alarm-next')));
    await tap(find.byKey(const Key('alarm-date')));
    for (final digit in ['1', '2', '0', '5']) await tap(find.byKey(Key('alarm-digit-$digit')));
    await tap(find.byKey(const Key('alarm-next')));
    expect(calls, isEmpty);
    expect(find.byKey(const Key('alarm-summary')), findsOneWidget);
    await tap(find.text('틀리다 · 다시 입력'));
    expect(calls, isEmpty);
    for (final digit in ['0', '8', '0', '0']) await tap(find.byKey(Key('alarm-digit-$digit')));
    await tap(find.byKey(const Key('alarm-next')));
    await tap(find.text('매일 반복'));
    await tap(find.byKey(const Key('alarm-confirm')));
    expect(calls.length, 1);
    final args = jsonDecode(calls.single.arguments['value'] as String);
    expect(args['hour'], 8); expect(args['minute'], 0);
    expect(args['days'], [1, 2, 3, 4, 5, 6, 7]);
    expect(find.byKey(const Key('alarm-confirm')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Dated scheduling failure retains the plan for an explicit retry', (tester) async {
    await largeSurface(tester);
    var calls = 0;
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      throw PlatformException(code: 'alarm_permission', message: '정확한 알람 권한을 허용해 주세요.');
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: AlarmPage(developerMode: true)));
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
    }
    for (final digit in ['1', '3', '0', '5']) await tap(find.byKey(Key('alarm-digit-$digit')));
    await tap(find.byKey(const Key('alarm-next')));
    await tap(find.byKey(const Key('alarm-date')));
    for (final digit in ['1', '2', '0', '5']) await tap(find.byKey(Key('alarm-digit-$digit')));
    await tap(find.byKey(const Key('alarm-next')));
    await tap(find.byKey(const Key('alarm-confirm')));
    expect(calls, 1);
    expect(find.textContaining('정확한 알람 권한'), findsOneWidget);
    expect(find.byKey(const Key('alarm-confirm')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
