import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> postAssistantJson(
    Uri uri, String token, Map<String, dynamic> payload) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (token.isNotEmpty) request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(const Duration(seconds: 50));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 65536) throw const FormatException('서버 응답이 너무 큽니다.');
    }
    return {'status': response.statusCode, 'body': utf8.decode(bytes)};
  } finally {
    client.close(force: true);
  }
}
