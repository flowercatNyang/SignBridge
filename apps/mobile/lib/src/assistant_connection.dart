import 'dart:convert';
import 'assistant_transport.dart';

const assistantBaseUrl = 'http://34.158.204.134:8000';
const assistantAccessToken = '1q2w3e4r!';

bool isAssistantHealthy(int status, String body) {
  if (status != 200) return false;
  try {
    final data = jsonDecode(body);
    return data is Map && data['status'] == 'ok';
  } on FormatException {
    return false;
  }
}

Future<bool> checkAssistantConnection() async {
  try {
    final response = await getAssistantHealth(Uri.parse('$assistantBaseUrl/health'));
    return isAssistantHealthy(response['status'] as int, response['body'] as String);
  } catch (_) {
    return false;
  }
}
