import 'package:flutter_test/flutter_test.dart';
import 'package:testsign/src/alarm_input.dart';
import 'package:testsign/src/sign_commands.dart';

void main() {
  AlarmInput time(String digits) {
    final input = AlarmInput()..digits = digits;
    input.acceptTime();
    return input;
  }

  test('24-hour HHMM preserves leading/repeated zeroes', () {
    expect(time('0105').hour, 1);
    expect(time('1305').hour, 13);
    expect(time('0800').minute, 0);
    for (final invalid in ['105', '2400', '1260', 'abcd']) {
      expect(() => time(invalid), throwsFormatException);
    }
  });

  test('Dates validate leap days and show the next occurrence with year', () {
    final input = time('1305')..digits = '1205';
    input.acceptDate(DateTime(2026, 11, 3));
    expect(input.arguments['date'], '2026-12-05');
    input.digits = '1205';
    input.acceptDate(DateTime(2026, 12, 5, 14));
    expect(input.arguments['date'], '2027-12-05');
    input.digits = '0229';
    input.acceptDate(DateTime(2026, 11, 3));
    expect(input.arguments['date'], '2028-02-29');
    for (final invalid in ['0230', '1301', '0000', '123']) {
      input.digits = invalid;
      expect(() => input.acceptDate(DateTime(2026)), throwsFormatException);
    }
  });

  test('Stable predictions and hand release separate digits and approvals', () {
    final gate = RecognitionGate();
    final start = DateTime(2026);
    const digit = SignPrediction('0', .99);
    expect(gate.accept(digit), isNull);
    expect(gate.accept(digit), isNull);
    expect(gate.accept(digit), '0');
    for (var i = 0; i < 10; i++) expect(gate.accept(digit), isNull);
    const absent = SignPrediction('', 0, handsAbsent: true);
    gate.accept(absent, timestamp: start);
    gate.accept(absent, timestamp: start.add(const Duration(milliseconds: 800)));
    gate.accept(digit); gate.accept(digit);
    expect(gate.accept(digit), '0');
    gate.reset(requireRelease: true);
    for (var i = 0; i < 10; i++) {
      expect(gate.accept(const SignPrediction('그렇다', .99)), isNull);
    }
    gate.accept(absent, timestamp: start);
    gate.accept(absent, timestamp: start.add(const Duration(milliseconds: 800)));
    gate.accept(const SignPrediction('그렇다', .99));
    gate.accept(const SignPrediction('그렇다', .99));
    expect(gate.accept(const SignPrediction('그렇다', .99)), '그렇다');
  });
}
