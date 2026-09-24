import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  test('Routes all shortcut numbers only in shortcut mode', () {
    for (var i = 1; i <= 9; i++) {
      expect(resolveCommand('$i', shortcuts: true), 'shortcut$i');
      expect(resolveCommand('$i번', shortcuts: true), 'shortcut$i');
      expect(resolveCommand('$i', shortcuts: false), isNull);
    }
    expect(resolveCommand('아홉', shortcuts: true), 'shortcut9');
    expect(resolveCommand('119', shortcuts: true), isNull);
    expect(resolveCommand('10', shortcuts: true), isNull);
    expect(resolveCommand('팔 (신체)', shortcuts: true), isNull);
  });
  test('Matches equivalent call commands but rejects negation and other modes',
      () {
    for (final phrase in ['전화 끊어줘', '통화 종료해줘', '전화를 끊어주세요!']) {
      expect(resolveCommand(phrase, shortcuts: false), 'endCall');
      expect(resolveCommand(phrase, shortcuts: true), isNull);
    }
    expect(resolveCommand('전화 끊지 마', shortcuts: false), isNull);
    expect(resolveCommand('전화 끊어줘 라고 말했어', shortcuts: false), isNull);
  });
  test('One confident prediction triggers once until explicit rearming', () {
    final gate = CommandGate();
    final now = DateTime(2026);
    const good = SignPrediction('1', .95);
    expect(gate.accept(const SignPrediction('1', .1), true, now), isNull);
    expect(
        gate.accept(const SignPrediction('1', double.nan), true, now), isNull);
    expect(gate.accept(const SignPrediction('1', 1.1), true, now), isNull);
    expect(gate.accept(good, true, now), 'shortcut1');
    for (var i = 0; i < 10; i++) {
      expect(gate.accept(good, true, now), isNull);
    }
    gate.reset();
    expect(gate.accept(good, true, now.add(const Duration(seconds: 3))),
        'shortcut1');
  });
}
