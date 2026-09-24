/// Stable contract between recognition models and command routing.
class SignPrediction {
  const SignPrediction(this.text, this.confidence);
  final String text;
  final double confidence;
  static SignPrediction? fromDisplay(String value) {
    final match = RegExp(r'^(.*) · (\d+)%$').firstMatch(value);
    if (match == null) return null;
    return SignPrediction(match[1]!, int.parse(match[2]!) / 100);
  }
}

const shortcutLabels = <String>[
  '긴급 신고 (112)',
  '긴급 신고 (119)',
  '긴급 전화 (등록된 전화번호)',
  '배달의민족 앱 열기',
  '입력한 한국어를 영어로 번역',
  '메시지 보내기 (등록된 전화번호)',
  '타이머 설정',
  '미정 · 기능 준비 중',
  '미정 · 기능 준비 중',
];

String? resolveCommand(String text, {required bool shortcuts}) {
  final normalized = text.replaceAll(RegExp(r'[\s.!?。]'), '');
  if (shortcuts) {
    const numbers = ['일', '이', '삼', '사', '오', '육', '칠', '팔', '구'];
    const native = ['하나', '둘', '셋', '넷', '다섯', '여섯', '일곱', '여덟', '아홉'];
    for (var i = 1; i <= 9; i++) {
      if (['$i', '$i번', numbers[i - 1], native[i - 1]].contains(normalized)) {
        return 'shortcut$i';
      }
    }
    return null;
  }
  if (RegExp(r'^(전화|통화)(를)?(끊어|끊어줘|끊어주세요|끊기|종료|종료해|종료해줘|종료해주세요|종료하기)$')
      .hasMatch(normalized)) return 'endCall';
  return null;
}

/// One confident prediction; explicit rearming prevents duplicate execution.
class CommandGate {
  bool armed = true;
  void reset() {
    armed = true;
  }

  String? accept(SignPrediction prediction, bool shortcuts, DateTime now) {
    if (!armed) return null;
    final command = prediction.confidence.isFinite &&
            prediction.confidence >= .85 &&
            prediction.confidence <= 1
        ? resolveCommand(prediction.text, shortcuts: shortcuts)
        : null;
    if (command == null) return null;
    armed = false;
    return command;
  }
}
