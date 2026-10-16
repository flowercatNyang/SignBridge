// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

class DeviceActions {
  Future<String> execute(String action, [String value = '']) async {
    if (action == 'set_alarm' || action == 'compose_message') {
      throw Exception('알람·문자 작성은 Android 앱에서 실행해 주세요. 웹에서는 번역과 요청 확인까지 가능합니다.');
    }
    if (action == 'emergency') {
      html.window.location.assign('tel:119');
      return '119 발신 화면 연결을 요청했습니다. 전화 앱에서 통화 버튼을 눌러 주세요.';
    }
    if (action == 'company') {
      final saved = await loadCompany();
      if (saved.isEmpty) throw Exception('먼저 회사 위치를 등록해 주세요.');
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final uri =
          Uri(scheme: 'nmap', host: 'route', path: '/public', queryParameters: {
        'dlat': '${data['lat']}',
        'dlng': '${data['lng']}',
        'dname': data['name'] as String,
        'appname': Uri.base.origin,
      });
      html.window.location.assign(uri.toString());
      return '네이버맵 길찾기 연결을 요청했습니다. 네이버맵 앱이 필요합니다.';
    }
    throw Exception('연락처 전화와 볼륨 조절은 Android 앱에서 지원합니다.');
  }

  Future<String> loadCompany() async =>
      html.window.localStorage['company'] ?? '';
  Future<void> saveCompany(String company) async {
    html.window.localStorage['company'] = company;
  }
}
