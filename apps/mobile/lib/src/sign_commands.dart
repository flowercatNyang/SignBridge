class SignPrediction {
  const SignPrediction(this.text, this.confidence, {this.handsAbsent = false});
  final String text;
  final double confidence;
  final bool handsAbsent;

  static SignPrediction? fromMessage(dynamic value) {
    if (value is String) return fromDisplay(value);
    if (value is! Map) return null;
    if (value['handsAbsent'] == true) {
      return const SignPrediction('', 0, handsAbsent: true);
    }
    final display = value['display'];
    return display is String ? fromDisplay(display) : null;
  }

  static SignPrediction? fromDisplay(String value) {
    final match = RegExp(r'^(.*) · (\d+)%$').firstMatch(value);
    if (match == null) return null;
    return SignPrediction(match[1]!, int.parse(match[2]!) / 100);
  }
}

const shortcutCommands = <String, String>{
  '아프다': 'emergency',
  '회사': 'company',
  '엄마': 'mother',
  '위(방향)': 'volumeUp',
  '상부': 'volumeUp',
  '아래': 'volumeDown',
};
String? resolveCommand(String text) =>
    shortcutCommands[text.trim().replaceAll(RegExp(r'[.!?。]+$'), '')];

/// Legacy labels are forwarded to the assistant, never executed by this gate.
class CommandGate {
  String? _lastCommand;
  DateTime? _absentSince;
  bool get armed => _lastCommand == null;

  void reset() {
    _lastCommand = null;
    _absentSince = null;
  }

  String? accept(SignPrediction prediction, {DateTime? timestamp}) {
    if (!prediction.confidence.isFinite ||
        prediction.confidence < 0 ||
        prediction.confidence > 1) return null;
    if (prediction.handsAbsent) {
      final now = timestamp ?? DateTime.now();
      _absentSince ??= now;
      if (now.difference(_absentSince!) >= const Duration(milliseconds: 800)) {
        reset();
      }
      return null;
    }
    _absentSince = null;
    if (prediction.confidence < .75) return null;
    final command = resolveCommand(prediction.text);
    if (command == _lastCommand) return null;
    if (command != null) _lastCommand = command;
    return command;
  }
}

/// All model labels are input tokens, not shortcut commands. Require a release
/// between tokens so a held sign cannot fill several digits or approve a plan.
class RecognitionGate {
  bool _latched = false;
  String _candidate = '';
  int _count = 0;
  DateTime? _absentSince;

  void reset({bool requireRelease = false}) {
    _latched = requireRelease;
    _candidate = '';
    _count = 0;
    _absentSince = null;
  }

  String? accept(SignPrediction prediction, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    if (prediction.handsAbsent) {
      _candidate = ''; _count = 0;
      _absentSince ??= now;
      if (now.difference(_absentSince!) >= const Duration(milliseconds: 800)) reset();
      return null;
    }
    _absentSince = null;
    if (_latched) return null;
    if (!prediction.confidence.isFinite || prediction.confidence < .85 ||
        prediction.confidence > 1 || prediction.text.trim().isEmpty) {
      _candidate = ''; _count = 0;
      return null;
    }
    if (_candidate != prediction.text) { _candidate = prediction.text; _count = 0; }
    if (++_count < 3) return null;
    _latched = true;
    return _candidate;
  }
}
