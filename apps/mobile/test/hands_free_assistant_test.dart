import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/assistant_client.dart';
import 'package:testsign/src/assistant_connection.dart';
import 'package:testsign/src/assistant_page.dart';
import 'package:testsign/src/hand_camera/hand_camera.dart';
import 'package:testsign/src/sign_commands.dart';
import 'package:testsign/src/translation.dart';

class RouteCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void release(WidgetTester tester) {
  final page = tester.state<AssistantPageState>(find.byType(AssistantPage));
  final now = DateTime.now();
  page.acceptPrediction(const SignPrediction('', 0, handsAbsent: true),
      timestamp: now);
  page.acceptPrediction(const SignPrediction('', 0, handsAbsent: true),
      timestamp: now.add(const Duration(milliseconds: 900)));
}

Future<void> sign(WidgetTester tester, String word,
    {bool lowerHands = true}) async {
  if (lowerHands) release(tester);
  final predict =
      tester.widget<HandCamera>(find.byType(HandCamera)).onPrediction!;
  for (var i = 0; i < 3; i++) {
    predict(SignPrediction(word, .99));
  }
  await tester.pump();
}

Future<void> surface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUp(() => AssistantConnection.instance.resetForTesting());
  tearDown(() => AssistantConnection.instance.resetForTesting());

  testWidgets(
      'A new request after a completed translation gets a new original text',
      (tester) async {
    await surface(tester);
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: TranslationPage(assistantRequest:
        (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
      requests.add({'text': text, 'type': inputType, 'history': history});
      return AssistantReply(
          translation: text,
          question: requests.length == 2 ? null : '맞나요?',
          action: null,
          mode: 'mock');
    })));
    await tester.pumpAndSettle();
    await sign(tester, '엄마');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await sign(tester, '회사');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests.last['text'], '회사');
    expect(requests.last['type'], 'gloss');
    expect(requests.last['history'], isEmpty);
    expect(find.text('원래 요청: 회사'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Transport confirmation sends the full mother request, never yes alone',
      (tester) async {
    await surface(tester);
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: TranslationPage(assistantRequest:
        (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
      requests.add({'text': text, 'type': inputType, 'history': history});
      return AssistantReply(
          translation: '엄마, 나 아파요.',
          question: requests.length == 1 ? 'LLM에 전달하시겠습니까?' : '엄마에게 문자로 알릴까요?',
          action: null,
          mode: 'mock');
    })));
    await tester.pumpAndSettle();
    for (final word in ['엄마', '나', '아프다']) {
      await sign(tester, word);
    }
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests.single['text'], '엄마 나 아프다');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests.length, 2);
    expect(requests.last['text'], '엄마 나 아프다');
    expect(requests.last['type'], 'confirmation');
    expect((requests.last['history'] as List).first['content'],
        contains('엄마 나 아프다'));
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        isEmpty);
    expect(find.text('원래 요청: 엄마 나 아프다'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'A failed confirmation retains the original request and can be retried',
      (tester) async {
    await surface(tester);
    final requests = <String>[];
    await tester.pumpWidget(MaterialApp(home: TranslationPage(assistantRequest:
        (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
      requests.add('$inputType:$text');
      if (requests.length == 2) throw Exception('LLM JSON 형식 오류');
      return const AssistantReply(
          translation: '엄마, 나 아파요.',
          question: '맞나요?',
          action: null,
          mode: 'mock');
    })));
    await tester.pumpAndSettle();
    await sign(tester, '엄마');
    await sign(tester, '아프다');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-reply')), findsOneWidget);
    expect(find.text('원래 요청: 엄마 아프다'), findsOneWidget);
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests,
        ['gloss:엄마 아프다', 'confirmation:엄마 아프다', 'confirmation:엄마 아프다']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Compact camera layout preserves the conversation and its camera',
      (tester) async {
    await surface(tester);
    final requests = <String>[];
    await tester.pumpWidget(MaterialApp(home: TranslationPage(assistantRequest:
        (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
      requests.add(text);
      return const AssistantReply(
          translation: '엄마', question: '맞나요?', action: null, mode: 'mock');
    })));
    await tester.pumpAndSettle();
    final camera = tester.state(find.byType(HandCamera));
    final conversation = tester.state(find.byType(AssistantPage));
    await sign(tester, '엄마');
    Future<void> pip(bool active) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'signbridge/pip',
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('changed', active)),
          (_) {});
      await tester.pumpAndSettle();
    }

    await pip(true);
    expect(find.byType(HandCamera, skipOffstage: false), findsOneWidget);
    expect(tester.state(find.byType(HandCamera)), same(camera));
    await pip(false);
    expect(tester.state(find.byType(AssistantPage)), same(conversation));
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        '엄마');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests, ['엄마']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('A changed signed request invalidates the old execution plan',
      (tester) async {
    await surface(tester);
    var requests = 0, executions = 0;
    await tester.pumpWidget(MaterialApp(
        home: TranslationPage(
      assistantExecuteAction: (_) async {
        executions++;
        return '완료';
      },
      assistantRequest: (
          {required String baseUrl,
          required String accessToken,
          required String text,
          required String inputType,
          required List<Map<String, String>> history}) async {
        requests++;
        return AssistantReply(
            translation: text,
            question: null,
            action: AssistantAction('adjust_volume', {'direction': 'up'}),
            mode: 'mock');
      },
    )));
    await tester.pumpAndSettle();
    await sign(tester, '위(방향)');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await sign(tester, '아래');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(executions, 0);
    await sign(tester, '틀리다');
    expect(find.byKey(const Key('assistant-reply')), findsNothing);
    expect(executions, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Real camera labels submit, confirm translation and execute on one route',
      (tester) async {
    await surface(tester);
    final routes = RouteCounter();
    final requests = <Map<String, dynamic>>[];
    final actions = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      actions.add(call);
      return '문자 작성 화면을 열었습니다.';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [routes],
        home: TranslationPage(assistantExecuteAction: (action) async {
          actions.add(
              MethodCall(action.name, {'value': jsonEncode(action.arguments)}));
          return '실행 완료';
        }, assistantRequest: (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
          requests.add({'text': text, 'type': inputType, 'history': history});
          if (requests.length == 1) {
            return const AssistantReply(
                translation: '엄마에게 아프다고 전달할까요?',
                question: '이 뜻이 맞나요?',
                action: null,
                mode: 'mock');
          }
          return AssistantReply(
              translation: '엄마에게 아프다고 문자 작성',
              question: null,
              action: AssistantAction(
                  'compose_message', {'recipient': '엄마', 'body': '나 아파'}),
              mode: 'mock');
        })));
    await tester.pumpAndSettle();
    final cameraState = tester.state(find.byType(HandCamera));
    await sign(tester, '엄마');
    await sign(tester, '아프다');
    expect(requests, isEmpty);
    expect(actions, isEmpty);
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests.single['text'], '엄마 아프다');
    expect(requests.single['type'], 'gloss');
    expect(routes.pushes, 1);
    expect(tester.state(find.byType(HandCamera)), same(cameraState));
    expect(find.byKey(const Key('assistant-submit')), findsNothing);
    // Holding the submission sign must not approve the newly returned question.
    await sign(tester, '그렇다', lowerHands: false);
    expect(requests.length, 1);
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests.length, 2);
    expect(requests.last['text'], '엄마 아프다');
    expect(requests.last['type'], 'confirmation');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        isEmpty);
    expect(find.text('원래 요청: 엄마 아프다'), findsOneWidget);
    expect((requests.last['history'] as List).length, 2);
    expect(actions, isEmpty);
    await sign(tester, '그렇다', lowerHands: false);
    expect(actions, isEmpty);
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(actions.single.method, 'compose_message');
    expect(jsonDecode(actions.single.arguments['value'] as String)['body'],
        '나 아파');
    await sign(tester, '그렇다', lowerHands: false);
    await sign(tester, '그렇다');
    expect(actions.length, 1);
    expect(requests.length, 2);
    expect(routes.pushes, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Signed clarification is sent instead of replacing it with yes',
      (tester) async {
    await surface(tester);
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: TranslationPage(assistantRequest:
        (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
      requests.add({'text': text, 'history': history, 'type': inputType});
      return const AssistantReply(
          translation: '기상 알람 요청',
          question: '몇 시인가요?',
          action: null,
          mode: 'mock');
    })));
    await tester.pumpAndSettle();
    await sign(tester, '일어나다');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await sign(tester, '8');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(requests.length, 2);
    expect(requests.last['text'], '8');
    expect(requests.last['type'], 'gloss');
    expect(
        (requests.last['history'] as List).first['content'], contains('일어나다'));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('No cancels without executing and next request has fresh history',
      (tester) async {
    await surface(tester);
    final histories = <List<Map<String, String>>>[];
    final actions = <MethodCall>[];
    const channel = MethodChannel('signbridge/actions');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      actions.add(call);
      return '';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: TranslationPage(assistantExecuteAction: (action) async {
      actions.add(
          MethodCall(action.name, {'value': jsonEncode(action.arguments)}));
      return '실행 완료';
    }, assistantRequest: (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) async {
      histories.add(history);
      return AssistantReply(
          translation: '볼륨 올리기',
          question: null,
          action: AssistantAction('adjust_volume', {'direction': 'up'}),
          mode: 'mock');
    })));
    await tester.pumpAndSettle();
    await sign(tester, '위(방향)');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await sign(tester, '아니다');
    expect(actions, isEmpty);
    expect(find.byKey(const Key('assistant-reply')), findsNothing);
    await sign(tester, '아래');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(histories.length, 2);
    expect(histories.last, isEmpty);
    expect(actions, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Recognition during an outstanding request cannot queue another call',
      (tester) async {
    await surface(tester);
    final response = Completer<AssistantReply>();
    var requests = 0;
    await tester.pumpWidget(MaterialApp(home: TranslationPage(assistantRequest:
        (
            {required String baseUrl,
            required String accessToken,
            required String text,
            required String inputType,
            required List<Map<String, String>> history}) {
      requests++;
      return response.future;
    })));
    await tester.pumpAndSettle();
    await sign(tester, '엄마');
    await sign(tester, '그렇다');
    await sign(tester, '아프다');
    await sign(tester, '그렇다');
    expect(requests, 1);
    response.complete(const AssistantReply(
        translation: '엄마', question: '맞나요?', action: null, mode: 'mock'));
    await tester.pumpAndSettle();
    expect(find.byType(HandCamera), findsOneWidget);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
      'Connection survives a page recreation and is used by sign requests',
      (tester) async {
    await surface(tester);
    AssistantConnection.instance
        .update('http://192.168.0.12:8000', 'test-access-token');
    final connections = <String>[];
    Future<AssistantReply> request(
        {required String baseUrl,
        required String accessToken,
        required String text,
        required String inputType,
        required List<Map<String, String>> history}) async {
      connections.add('$baseUrl|$accessToken');
      return const AssistantReply(
          translation: '엄마', question: null, action: null, mode: 'mock');
    }

    await tester.pumpWidget(MaterialApp(
        key: const Key('first'),
        home: TranslationPage(assistantRequest: request)));
    await tester.pumpAndSettle();
    await sign(tester, '엄마');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
        key: const Key('second'),
        home: TranslationPage(assistantRequest: request)));
    await tester.pumpAndSettle();
    await sign(tester, '엄마');
    await sign(tester, '그렇다');
    await tester.pumpAndSettle();
    expect(connections,
        List.filled(2, 'http://192.168.0.12:8000|test-access-token'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
