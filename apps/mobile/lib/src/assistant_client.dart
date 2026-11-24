import 'dart:async';
import 'dart:convert';
import 'assistant_transport.dart';

typedef AssistantRequester = Future<AssistantReply> Function({
  required String baseUrl,
  required String accessToken,
  required String text,
  required String inputType,
  required List<Map<String, String>> history,
});

typedef AssistantActionExecutor = Future<String> Function(AssistantAction action);

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
      final date = args['date'];
      final parsedDate = date is String ? DateTime.tryParse(date) : null;
      if (args.keys.any((key) => !['hour', 'minute', 'label', 'days', 'date'].contains(key)) ||
          hour is! int || hour < 0 || hour > 23 ||
          minute is! int || minute < 0 || minute > 59 ||
          args['label'] is! String || (args['label'] as String).length > 120 ||
          days is! List || days.length > 7 ||
          days.any((dynamic day) => day is! int || day < 1 || day > 7) ||
          days.toSet().length != days.length ||
          (args.containsKey('date') && (date is! String ||
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
              parsedDate == null || parsedDate.toIso8601String().substring(0, 10) != date ||
              days.isNotEmpty))) {
        throw const FormatException('알람 설정이 올바르지 않습니다.');
      }
    } else if (name == 'compose_message') {
      if (args.length != 2 || !_validText(args['recipient'], 80) ||
          !_validText(args['body'], 1000)) {
        throw const FormatException('문자 수신자와 내용을 확인해 주세요.');
      }
    } else if (['emergency', 'company', 'mother'].contains(name)) {
      if (args.isNotEmpty) throw const FormatException('잘못된 실행 인자입니다.');
    } else if (name == 'nearby_hospital') {
      if (args.length != 1 || !['병원', '내과'].contains(args['department'])) {
        throw const FormatException('병원 검색어를 확인해 주세요.');
      }
    } else if (name == 'adjust_volume') {
      if (args.length != 1 || !['up', 'down'].contains(args['direction'])) {
        throw const FormatException('볼륨 방향을 확인해 주세요.');
      }
    } else {
      throw const FormatException('지원하지 않는 실행 기능입니다.');
    }
    return AssistantAction(name as String, args);
  }

  String get summary {
    if (name == 'emergency') return '119 발신 화면 열기 · 전화 앱에서 통화 버튼을 눌러 주세요.';
    if (name == 'company') return '네이버 지도에서 회사 길찾기';
    if (name == 'mother') return '등록된 엄마 연락처로 전화';
    if (name == 'nearby_hospital') return '네이버 지도에서 ${arguments["department"]} 검색';
    if (name == 'adjust_volume') {
      return arguments['direction'] == 'up' ? '미디어 볼륨 한 단계 높이기' : '미디어 볼륨 한 단계 낮추기';
    }
    if (name == 'set_alarm') {
      final hour = '${arguments['hour']}'.padLeft(2, '0');
      final minute = '${arguments['minute']}'.padLeft(2, '0');
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final days = arguments['days'] as List;
      final repeat = days.isEmpty
          ? '반복 없음 · 다음 해당 시각'
          : '${days.map((dynamic day) => weekdays[(day as int) - 1]).join(', ')} 반복';
      final label = arguments['label'] as String;
      final date = arguments['date'];
      final schedule = date == null ? repeat : '$date · 한 번 · 기기 현지 시간';
      return '알람 $hour:$minute\n$schedule${label.isEmpty ? '' : '\n이름: $label'}';
    }
    return '받는 사람　${arguments['recipient']}\n보낼 문자　${arguments['body']}';
  }
}

bool _validText(dynamic value, int maximum) => value is String &&
    value.trim().isNotEmpty && value.length <= maximum;

class AssistantReply {
  const AssistantReply({required this.translation, required this.question,
    required this.action, required this.mode, this.step});
  final String translation;
  final String? question;
  final AssistantAction? action;
  final String mode;
  final String? step;

  factory AssistantReply.fromJson(Map<String, dynamic> data) {
    if (data.length != (data.containsKey('step') ? 5 : 4) ||
        (data.containsKey('step') && !_validText(data['step'], 40)) ||
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
        mode: data['mode'] as String, step: data['step'] as String?);
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
    final payload = {'text': text, 'input_type': inputType, 'history': history};
    Future<Map<String, dynamic>> send(Map<String, dynamic> body) =>
        postAssistantJson(uri.resolve('/v1/interpret'), accessToken.trim(), body)
            .timeout(const Duration(seconds: 60));
    var response = await send({'guided': true, ...payload});
    var decoded = jsonDecode(response['body'] as String);
    // Older servers reject the guided field before interpreting the request.
    if (response['status'] == 400 && decoded is Map &&
        decoded['error'] == '잘못된 요청 형식입니다.' &&
        inputType != 'rejection' && history.every((turn) => !turn.containsKey('step'))) {
      response = await send(payload);
      decoded = jsonDecode(response['body'] as String);
    }
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
