import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'assistant_client.dart';

/// Shared across pages; Android also persists the token encrypted with KeyStore.
class AssistantConnection extends ChangeNotifier {
  AssistantConnection(
      {Future<dynamic> Function()? loadSettings,
      Future<void> Function(String, String)? saveSettings})
      : _loadSettings = loadSettings,
        _saveSettings = saveSettings;
  static final instance = AssistantConnection();
  static const _channel = MethodChannel('signbridge/assistant-settings');
  String baseUrl = defaultAssistantUrl();
  String accessToken = const String.fromEnvironment('ASSISTANT_ACCESS_TOKEN');
  int _revision = 0;
  Future<void>? _loading;
  final Future<dynamic> Function()? _loadSettings;
  final Future<void> Function(String, String)? _saveSettings;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void update(String url, String token) {
    if (baseUrl == url && accessToken == token) return;
    baseUrl = url;
    accessToken = token;
    _revision++;
    notifyListeners();
  }

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    if (!_android && _loadSettings == null) return;
    final revision = _revision;
    try {
      final stored = await (_loadSettings?.call() ??
          _channel.invokeMethod<dynamic>('loadAssistantConnection'));
      // A late disk read must not overwrite settings the user just edited.
      if (revision != _revision || stored is! Map) return;
      final url = stored['baseUrl'];
      final token = stored['accessToken'];
      update(url is String && url.isNotEmpty ? url : baseUrl,
          token is String ? token : accessToken);
    } on MissingPluginException {
      // Old APKs and non-Android previews keep the shared in-memory settings.
    }
  }

  Future<void> save() async {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('서버 주소는 http(s)://주소:포트 형식이어야 합니다.');
    }
    if (!_android && _saveSettings == null) return;
    try {
      if (_saveSettings != null) {
        await _saveSettings!(baseUrl.trim(), accessToken.trim());
      } else {
        await _channel.invokeMethod<void>('saveAssistantConnection', {
          'baseUrl': baseUrl.trim(),
          'accessToken': accessToken.trim(),
        });
      }
      _loading = Future<void>.value();
    } on MissingPluginException {
      // Connection settings remain available for this app session.
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _loading = null;
    update(defaultAssistantUrl(),
        const String.fromEnvironment('ASSISTANT_ACCESS_TOKEN'));
  }
}
