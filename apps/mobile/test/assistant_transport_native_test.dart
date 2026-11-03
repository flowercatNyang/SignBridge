import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/assistant_transport_native.dart';

void main() {
  test('Native requests send the UTF-8 byte length without chunked encoding', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = {'text': '엄마 나 아프다', 'input_type': 'gloss', 'history': []};
    final response = postAssistantJson(
        Uri.parse('http://127.0.0.1:${server.port}/v1/interpret'), 'test-token', payload);
    final request = await server.first.timeout(const Duration(seconds: 5));
    final transferEncoding = request.headers.value(HttpHeaders.transferEncodingHeader);
    final length = request.headers.contentLength;
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    final bytes = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"status":"ok"}');
    await request.response.close();
    final result = await response;

    expect(transferEncoding, isNull);
    expect(length, utf8.encode(jsonEncode(payload)).length);
    expect(authorization, 'Bearer test-token');
    expect(jsonDecode(utf8.decode(bytes)), payload);
    expect(result['status'], 200);
  });
}
