import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  test('Only requested translated words trigger actions', () {
    expect(shortcutCommands, {
      '아프다': 'emergency',
      '위': 'volumeUp',
      '아래': 'volumeDown',
      '회사': 'company',
      '엄마': 'mother',
    });
    for (final entry in shortcutCommands.entries) {
      expect(resolveCommand(entry.key), entry.value);
      expect(resolveCommand(' ${entry.key}! '), entry.value);
    }
    for (final text in [
      '구급차',
      '의사',
      '1',
      '119',
      '전화 끊어줘',
      '아프다 아님',
      '회사에 가지 마',
      '위로',
      ''
    ]) {
      expect(resolveCommand(text), isNull);
    }
  });
  test('Confidence and rearming prevent duplicate execution', () {
    final gate = CommandGate();
    for (final confidence in [
      .1,
      .749,
      .749999,
      double.nan,
      double.infinity,
      1.1
    ]) {
      expect(gate.accept(SignPrediction('아프다', confidence)), isNull);
    }
    expect(gate.accept(const SignPrediction('아프다', .75)), 'emergency');
    expect(gate.accept(const SignPrediction('아프다', .99)), isNull);
    gate.reset();
    expect(gate.accept(const SignPrediction('아프다', .99)), 'emergency');
  });
  test('Camera display yields the translated word', () {
    expect(SignPrediction.fromDisplay('회사 · 95%')!.text, '회사');
  });
  test('New words execute without manually rearming', () {
    final gate = CommandGate();
    expect(gate.accept(const SignPrediction('위', .75)), 'volumeUp');
    expect(gate.accept(const SignPrediction('위', .99)), isNull);
    expect(gate.accept(const SignPrediction('아래', .75)), 'volumeDown');
    expect(gate.accept(const SignPrediction('회사', .99)), 'company');
    expect(gate.accept(const SignPrediction('엄마', .99)), 'mother');
  });
  test('Only sustained hand absence rearms a held word', () {
    final gate = CommandGate();
    final start = DateTime(2026);
    expect(gate.accept(const SignPrediction('위', .75)), 'volumeUp');
    // Loading messages or low confidence must not repeat an action.
    gate.accept(const SignPrediction('', 0), timestamp: start);
    gate.accept(const SignPrediction('', 0),
        timestamp: start.add(const Duration(seconds: 2)));
    expect(gate.accept(const SignPrediction('위', .99)), isNull);
    final absent = SignPrediction.fromMessage({
      'display': '양손과 어깨가 보이도록 동작해 주세요',
      'handsAbsent': true,
    })!;
    gate.accept(absent, timestamp: start);
    gate.accept(absent,
        timestamp: start.add(const Duration(milliseconds: 799)));
    expect(gate.accept(const SignPrediction('위', .99)), isNull);
    gate.accept(absent, timestamp: start);
    gate.accept(absent,
        timestamp: start.add(const Duration(milliseconds: 800)));
    expect(gate.accept(const SignPrediction('위', .75)), 'volumeUp');
    expect(gate.accept(const SignPrediction('위', .99)), isNull);
  });
  test('Native prediction messages preserve threshold and word', () {
    final result = SignPrediction.fromMessage({
      'display': '아래 · 75%',
      'handsAbsent': false,
    })!;
    expect(result.text, '아래');
    expect(result.confidence, .75);
    expect(SignPrediction.fromMessage({'display': 42}), isNull);
  });
}
