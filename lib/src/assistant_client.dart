import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'assistant_transport.dart';

typedef AssistantRequester = Future<AssistantReply> Function({
  required String baseUrl,
  required String accessToken,
  required String text,
  required String inputType,
  required List<Map<String, String>> history,
});

String defaultAssistantUrl() {
  const configured = String.fromEnvironment('ASSISTANT_BASE_URL');
  if (configured.isNotEmpty) return configured;
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://127.0.0.1:8000';
}

class AssistantAction {
  AssistantAction(this.name, Map<String, dynamic> arguments)
      : arguments = Map.unmodifiable(arguments);
  final String name;
  final Map<String, dynamic> arguments;

  factory AssistantAction.fromJson(dynamic value) {
    if (value is! Map || value.length != 2 || value['arguments'] is! Map) {
      throw const FormatException('잘못된 실행 명령입니다.');
    }
    final name = value['name'];
    final args = Map<String, dynamic>.from(value['arguments'] as Map);
    if (name == 'set_alarm') {
      final hour = args['hour'], minute = args['minute'], days = args['days'];
      if (args.length != 4 || hour is! int || hour < 0 || hour > 23 ||
          minute is! int || minute < 0 || minute > 59 ||
          args['label'] is! String || (args['label'] as String).length > 120 ||
          days is! List || days.length > 7 ||
          days.any((dynamic day) => day is! int || day < 1 || day > 7) ||
          days.toSet().length != days.length) {
        throw const FormatException('알람 설정이 올바르지 않습니다.');
      }
    } else if (name == 'compose_message') {
      if (args.length != 2 || !_validText(args['recipient'], 80) ||
          !_validText(args['body'], 1000)) {
        throw const FormatException('문자 수신자와 내용을 확인해 주세요.');
      }
    } else {
      throw const FormatException('지원하지 않는 실행 기능입니다.');
    }
    return AssistantAction(name as String, args);
  }

  String get summary {
    if (name == 'set_alarm') {
      final hour = '${arguments['hour']}'.padLeft(2, '0');
      final minute = '${arguments['minute']}'.padLeft(2, '0');
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final days = arguments['days'] as List;
      final repeat = days.isEmpty
          ? '반복 없음 · 다음 해당 시각'
          : '${days.map((dynamic day) => weekdays[(day as int) - 1]).join(', ')} 반복';
      final label = arguments['label'] as String;
      return '알람 $hour:$minute\n$repeat${label.isEmpty ? '' : '\n이름: $label'}';
    }
    return '수신 연락처: ${arguments['recipient']}\n문자 내용: ${arguments['body']}';
  }
}

bool _validText(dynamic value, int maximum) => value is String &&
    value.trim().isNotEmpty && value.length <= maximum;

class AssistantReply {
  const AssistantReply({required this.translation, required this.question,
    required this.action, required this.mode});
  final String translation;
  final String? question;
  final AssistantAction? action;
  final String mode;

  factory AssistantReply.fromJson(Map<String, dynamic> data) {
    if (data.length != 4 ||
        !['translation', 'question', 'action', 'mode'].every(data.containsKey) ||
        !_validText(data['translation'], 2000) ||
        !['nvidia', 'mock'].contains(data['mode']) ||
        (data['question'] != null && !_validText(data['question'], 1000)) ||
        (data['question'] != null && data['action'] != null)) {
      throw const FormatException('서버의 번역 응답이 올바르지 않습니다.');
    }
    return AssistantReply(translation: data['translation'] as String,
        question: data['question'] as String?,
        action: data['action'] == null ? null : AssistantAction.fromJson(data['action']),
        mode: data['mode'] as String);
  }
}

Future<AssistantReply> requestAssistant({required String baseUrl,
    required String accessToken, required String text, required String inputType,
    required List<Map<String, String>> history}) async {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty ||
      uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('서버 주소는 http(s)://주소:포트 형식이어야 합니다.');
  }
  try {
    final response = await postAssistantJson(uri.resolve('/v1/interpret'),
        accessToken.trim(), {'text': text, 'input_type': inputType, 'history': history})
        .timeout(const Duration(seconds: 60));
    final decoded = jsonDecode(response['body'] as String);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('서버 응답을 읽지 못했습니다.');
    }
    if (response['status'] != 200) {
      throw Exception(decoded['error'] is String ? decoded['error'] : '서버 요청에 실패했습니다.');
    }
    return AssistantReply.fromJson(decoded);
  } on TimeoutException {
    throw Exception('서버 응답이 늦습니다. 연결을 확인하고 다시 시도해 주세요.');
  }
}
