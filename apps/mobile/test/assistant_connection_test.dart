import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/assistant_connection.dart';

void main() {
  test('health requires a successful SignBridge status response', () {
    expect(isAssistantHealthy(200, '{"status":"ok"}'), isTrue);
    expect(isAssistantHealthy(503, '{"status":"ok"}'), isFalse);
    expect(isAssistantHealthy(200, '<html>'), isFalse);
    expect(isAssistantHealthy(200, '{}'), isFalse);
  });
}
