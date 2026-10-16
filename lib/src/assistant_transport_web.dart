import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<Map<String, dynamic>> postAssistantJson(
    Uri uri, String token, Map<String, dynamic> payload) {
  final done = Completer<Map<String, dynamic>>();
  final request = html.HttpRequest();
  request.open('POST', uri.toString());
  request.timeout = 60000;
  request.setRequestHeader('Content-Type', 'application/json');
  if (token.isNotEmpty) request.setRequestHeader('Authorization', 'Bearer $token');
  request.onLoad.listen((_) {
    if (done.isCompleted) return;
    final body = request.responseText ?? '';
    if (body.length > 65536) {
      done.completeError(const FormatException('서버 응답이 너무 큽니다.'));
    } else {
      done.complete({'status': request.status, 'body': body});
    }
  });
  void fail() {
    if (!done.isCompleted) {
      done.completeError(Exception('서버 연결 실패. 주소·CORS·HTTPS 설정을 확인해 주세요.'));
    }
  }
  request.onError.listen((_) => fail());
  request.onTimeout.listen((_) => fail());
  request.onAbort.listen((_) => fail());
  request.send(jsonEncode(payload));
  return done.future;
}
