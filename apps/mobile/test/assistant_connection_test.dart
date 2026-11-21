import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/assistant_connection.dart';

void main() {
  test('Saved settings can be loaded by a fresh connection', () async {
    Map<String, String>? saved;
    final first = AssistantConnection(saveSettings: (url, token) async {
      saved = {'baseUrl': url, 'accessToken': token};
    });
    first.update('http://192.168.0.12:8000', 'test-token');
    await first.save();
    final next = AssistantConnection(loadSettings: () async => saved);
    await next.load();
    expect(next.baseUrl, first.baseUrl);
    expect(next.accessToken, first.accessToken);
    first.dispose();
    next.dispose();
  });

  test('A slow settings read cannot overwrite a new edit', () async {
    final result = Completer<Map<String, String>>();
    final connection = AssistantConnection(loadSettings: () => result.future);
    final loading = connection.load();
    connection.update('http://192.168.0.22:8000', 'new-token');
    result.complete(
        {'baseUrl': 'http://192.168.0.11:8000', 'accessToken': 'old-token'});
    await loading;
    expect(connection.baseUrl, 'http://192.168.0.22:8000');
    expect(connection.accessToken, 'new-token');
    connection.dispose();
  });

  test('Settings reject credential-bearing and non-server URLs before saving',
      () async {
    var calls = 0;
    final connection = AssistantConnection(saveSettings: (_, __) async {
      calls++;
    });
    for (final url in [
      'file:///tmp/settings',
      'http://user:password@example.com',
      'http://localhost:8000/path',
      'http://localhost:8000?token=test'
    ]) {
      connection.update(url, 'test-token');
      await expectLater(connection.save(), throwsFormatException);
    }
    expect(calls, 0);
    connection.dispose();
  });
}
