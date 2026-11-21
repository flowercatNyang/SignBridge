import 'package:flutter/material.dart';
import 'design.dart';

// Simulated recognition labels only; adding a button does not train the camera model.
const assistantTestWords = [
  '엄마', '나', '아프다', '회사', '위(방향)', '아래', '위(내장)', '가깝다',
  '매일매일', '일어나다', '8', '그렇다', '틀리다', '아니다',
  // Temporarily excluded recognition classes (screen controls still work).
  // '걷다', '귀',
  // '0', '1', '2', '3', '4', '5', '6', '7', '9',
];

class GlossTestPanel extends StatelessWidget {
  const GlossTestPanel({Key? key, required this.text, required this.onWord,
    required this.onUndo, required this.onClear, this.onSubmit, this.disabled = false})
      : super(key: key);
  final String text;
  final ValueChanged<String> onWord;
  final VoidCallback onUndo, onClear;
  final VoidCallback? onSubmit;
  final bool disabled;

  @override
  Widget build(BuildContext context) => Panel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('LLM 수어 조합 테스트', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('버튼은 실제 수어 인식과 같은 경로를 테스트합니다. '
          '그렇다는 입력 전송 또는 실행 승인, 아니다/틀리다는 취소입니다. '
          '아니다 버튼은 틀리다의 제어 별칭이며 새 인식 클래스를 학습한 것은 아닙니다.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final word in assistantTestWords)
          OutlinedButton(key: Key('gloss-word-$word'),
            onPressed: disabled ? null : () => onWord(word), child: Text(word)),
      ]),
      const SizedBox(height: 12),
      Text(text.isEmpty ? '버튼을 눌러 수어 라벨을 조합하세요.' : '조합: $text',
          key: const Key('gloss-test-sequence')),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: disabled || text.isEmpty ? null : onUndo,
            child: const Text('마지막 단어 삭제')),
        TextButton(onPressed: disabled || text.isEmpty ? null : onClear,
            child: const Text('조합 비우기')),
        if (onSubmit != null)
          ElevatedButton(key: const Key('gloss-test-open-assistant'),
            onPressed: disabled || text.isEmpty ? null : onSubmit,
            child: const Text('조합을 LLM 비서로 보내기')),
      ]),
    ],
  ));
}
