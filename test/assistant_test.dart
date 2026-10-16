import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/assistant_client.dart';
import 'package:testsign/src/assistant_page.dart';
import 'package:testsign/src/demo_app.dart';
import 'home_test_helpers.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';

Map<String, dynamic> alarmJson() => {
      'translation': '오전 7시에 알람을 설정해 주세요.',
      'question': null,
      'mode': 'mock',
      'action': {
        'name': 'set_alarm',
        'arguments': {
          'hour': 7,
          'minute': 0,
          'label': '',
          'days': <int>[],
        }
      },
    };

void main() {
  for (final words in [
    ['엄마', '나', '늦다', '보내다'],
    ['오전', '8', '시', '일어나다', '알람', '설정'],
  ]) {
    testWidgets(
        'Developer tokens use the recognition-to-LLM path: ${words.join(' ')}',
        (tester) async {
      final requests = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: AssistantPage(
              developerMode: true,
              request: ({
                required String baseUrl,
                required String accessToken,
                required String text,
                required String inputType,
                required List<Map<String, String>> history,
              }) async {
                requests.add('$inputType:$text');
                return const AssistantReply(
                    translation: '테스트 번역 후보',
                    question: '이 뜻이 맞나요?',
                    action: null,
                    mode: 'mock');
              })));
      expect(find.byType(HandCamera), findsNothing);
      for (final word in words) {
        final button = find.byKey(Key('gloss-word-$word'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(requests, isEmpty);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('assistant-input')))
              .controller!
              .text,
          words.join(' '));
      await tester.ensureVisible(find.byKey(const Key('assistant-submit')));
      await tester.tap(find.byKey(const Key('assistant-submit')));
      await tester.pumpAndSettle();
      expect(requests, ['gloss:${words.join(' ')}']);
      expect(find.byType(HandCamera), findsNothing);
      expect(find.byKey(const Key('assistant-execute')), findsNothing);
      expect(find.text('이 뜻이 맞나요?'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('Developer repeats, undo and clear update the same input',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: AssistantPage(developerMode: true)));
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    String input() => tester
        .widget<TextField>(find.byKey(const Key('assistant-input')))
        .controller!
        .text;
    await tap(find.byKey(const Key('gloss-word-8')));
    await tap(find.byKey(const Key('gloss-word-8')));
    expect(input(), '8 8');
    await tap(find.text('마지막 단어 삭제'));
    expect(input(), '8');
    await tap(find.text('조합 비우기'));
    expect(input(), '');
    expect(find.byType(HandCamera), findsNothing);
  });

  testWidgets(
      'Shortcut developer panel passes tokens into assistant without execution',
      (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return '실행하지 않아야 합니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(HandCamera), findsNothing);
    for (final word in ['엄마', '늦다', '보내다']) {
      final finder = find.byKey(Key('gloss-word-$word'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    await tester
        .ensureVisible(find.byKey(const Key('gloss-test-open-assistant')));
    await tester.tap(find.byKey(const Key('gloss-test-open-assistant')));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        '엄마 늦다 보내다');
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('Unapproved actions and invalid times are rejected before execution',
      () {
    for (final action in [
      {
        'name': 'shell',
        'arguments': {'command': 'anything'}
      },
      {
        'name': 'set_alarm',
        'arguments': {'hour': 24, 'minute': 0, 'label': '', 'days': []}
      },
      {
        'name': 'set_alarm',
        'arguments': {
          'hour': 7,
          'minute': 0,
          'label': '',
          'days': [1, 1]
        }
      },
      {
        'name': 'compose_message',
        'arguments': {'recipient': '엄마', 'body': ''}
      },
    ]) {
      expect(() => AssistantAction.fromJson(action), throwsFormatException);
    }
  });

  test('Question cannot carry an executable plan', () {
    final data = alarmJson()..['question'] = '몇 시?';
    expect(() => AssistantReply.fromJson(data), throwsFormatException);
  });

  testWidgets(
      'Camera input stops before interpretation and action needs confirmation',
      (tester) async {
    final calls = <MethodCall>[];
    final requests = <String>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return '시계 앱에 전달했습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: AssistantPage(request: ({
      required String baseUrl,
      required String accessToken,
      required String text,
      required String inputType,
      required List<Map<String, String>> history,
    }) async {
      requests.add('$inputType:$text');
      return AssistantReply.fromJson(alarmJson());
    })));
    expect(find.byType(HandCamera), findsNothing);
    await tester.ensureVisible(find.text('수어 입력 시작'));
    await tester.tap(find.text('수어 입력 시작'));
    await tester.pumpAndSettle();
    final prediction =
        tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
    prediction(const SignPrediction('엄마', .99));
    await tester.pumpAndSettle();
    prediction(const SignPrediction('엄마', .99));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('assistant-submit')));
    await tester.tap(find.byKey(const Key('assistant-submit')));
    await tester.pumpAndSettle();
    expect(requests, ['gloss:엄마']);
    expect(find.byType(HandCamera), findsNothing);
    expect(calls, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('assistant-execute')));
    await tester.tap(find.byKey(const Key('assistant-execute')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const Key('assistant-execute')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인하고 열기'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'set_alarm');
    expect(jsonDecode(calls.single.arguments['value'] as String)['hour'], 7);
    expect(find.byKey(const Key('assistant-execute')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Clarification retains history and editing invalidates an action',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(home: AssistantPage(request: ({
      required String baseUrl,
      required String accessToken,
      required String text,
      required String inputType,
      required List<Map<String, String>> history,
    }) async {
      count++;
      if (count == 1) {
        expect(history, isEmpty);
        return const AssistantReply(
            translation: '알람을 설정해 주세요.',
            question: '몇 시로 설정할까요?',
            action: null,
            mode: 'mock');
      }
      expect(history.map((turn) => turn['role']), ['user', 'assistant']);
      expect(history.first['content'], '알람 설정해줘');
      expect(history.last['content'], contains('번역 후보: 알람을 설정해 주세요.'));
      expect(history.last['content'], contains('추가 질문: 몇 시로 설정할까요?'));
      expect(text, '오전 7시');
      return AssistantReply.fromJson(alarmJson());
    })));
    await tester.enterText(find.byKey(const Key('assistant-input')), '알람 설정해줘');
    await tester.ensureVisible(find.byKey(const Key('assistant-submit')));
    await tester.tap(find.byKey(const Key('assistant-submit')));
    await tester.pumpAndSettle();
    expect(find.text('몇 시로 설정할까요?'), findsOneWidget);
    expect(find.byKey(const Key('assistant-execute')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('assistant-input')));
    await tester.enterText(find.byKey(const Key('assistant-input')), '오전 7시');
    await tester.ensureVisible(find.byKey(const Key('assistant-submit')));
    await tester.tap(find.byKey(const Key('assistant-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-execute')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('assistant-input')));
    await tester.enterText(find.byKey(const Key('assistant-input')), '오후 8시');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-execute')), findsNothing);
  });

  testWidgets('Entering assistant disposes the underlying shortcut camera',
      (tester) async {
    await tester.pumpWidget(const SignBridgeApp());
    await openShortcuts(tester);
    expect(find.byType(HandCamera), findsOneWidget);
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LLM 비서'));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(find.byType(HandCamera, skipOffstage: false), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
