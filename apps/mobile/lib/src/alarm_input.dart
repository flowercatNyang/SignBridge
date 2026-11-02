// Calendar/time parsing is deterministic; the LLM must not guess digit meanings.
class AlarmInput {
  String digits = '';
  int? hour, minute;
  DateTime? date;
  List<int> days = [];

  void add(String digit) {
    if (!RegExp(r'^[0-9]$').hasMatch(digit) || digits.length >= 4) return;
    digits += digit;
  }

  void undo() {
    if (digits.isNotEmpty) digits = digits.substring(0, digits.length - 1);
  }

  void acceptTime() {
    if (!RegExp(r'^[0-9]{4}$').hasMatch(digits)) {
      throw const FormatException('시간을 네 자리 HHMM으로 입력해 주세요.');
    }
    final h = int.parse(digits.substring(0, 2));
    final m = int.parse(digits.substring(2));
    if (h > 23 || m > 59) throw const FormatException('시간은 00:00~23:59입니다.');
    hour = h;
    minute = m;
    date = null;
    days = [];
    digits = '';
  }

  void acceptDate(DateTime now) {
    if (hour == null || !RegExp(r'^[0-9]{4}$').hasMatch(digits)) {
      throw const FormatException('시간을 먼저 정하고 날짜를 MMDD 네 자리로 입력해 주세요.');
    }
    final month = int.parse(digits.substring(0, 2));
    final day = int.parse(digits.substring(2));
    // Include the next leap year; DateTime silently normalizes invalid dates.
    for (var year = now.year; year <= now.year + 4; year++) {
      final candidate = DateTime(year, month, day, hour!, minute!);
      if (candidate.month == month && candidate.day == day && candidate.isAfter(now)) {
        date = candidate;
        days = [];
        digits = '';
        return;
      }
    }
    throw const FormatException('존재하는 날짜를 입력해 주세요. 예: 12월 5일 = 1205');
  }

  Map<String, dynamic> get arguments => {
    'hour': hour!, 'minute': minute!, 'label': 'SignBridge', 'days': days,
    if (date != null) 'date': '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}',
  };
}

const digitLabels = {
  '영': '0', '일': '1', '이': '2', '삼': '3', '사': '4',
  '오': '5', '육': '6', '칠': '7', '팔': '8', '구': '9',
};

String? signDigit(String word) => RegExp(r'^[0-9]$').hasMatch(word)
    ? word : digitLabels[word];
