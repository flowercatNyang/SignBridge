// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

class DeviceActions {
  Future<String> execute(String action, [String value = '']) async {
    if (action == 'message') {
      final message = jsonDecode(value) as Map<String, dynamic>;
      html.window.location.assign(Uri(
          scheme: 'sms',
          path: message['phone'] as String,
          queryParameters: {'body': message['body'] as String}).toString());
      return '메시지 앱 연결을 요청했습니다. 메시지 앱에서 전송을 눌러 주세요.';
    }
    if (action == 'translate') {
      html.window.location.assign(Uri.https('translate.google.com', '/', {
        'sl': 'ko',
        'tl': 'en',
        'text': value,
        'op': 'translate'
      }).toString());
      return '영어 번역 페이지를 열었습니다.';
    }
    if (action == 'dial' || action == 'call') {
      html.window.location.assign('tel:$value');
      return '전화 앱에 연결을 요청했습니다. 발신 화면에서 확인해 주세요.';
    }
    throw Exception('이 기능은 Android 앱에서 지원합니다.');
  }

  Future<String> loadPhone() async =>
      html.window.localStorage['emergencyPhone'] ?? '';
  Future<void> savePhone(String phone) async {
    html.window.localStorage['emergencyPhone'] = phone;
  }
}
