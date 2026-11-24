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
    final body = utf8.encode(jsonEncode(payload));
    // The backend requires a fixed byte length rather than chunked transfer.
    request.contentLength = body.length;
    request.add(body);
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

Future<Map<String, dynamic>> getAssistantHealth(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<Map<String, dynamic>> fetch() async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 65536) throw const FormatException();
      bytes.addAll(chunk);
    }
    return {'status': response.statusCode, 'body': utf8.decode(bytes)};
  }
  try {
    return await fetch().timeout(const Duration(seconds: 5));
  } finally {
    client.close(force: true);
  }
}
