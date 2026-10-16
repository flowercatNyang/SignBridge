import 'package:flutter/material.dart';
import 'design.dart';

// Simulated recognition labels only; adding a button does not train the camera model.
const assistantTestWords = [
  '엄마', '나', '보내다', '늦다', '일어나다', '알람', '설정', '오전', '오후', '8', '시',
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
      const Text('버튼은 수어를 인식한 뒤의 단어 라벨을 대신 입력합니다. '
          '누른 순서대로 모으며, 버튼만으로 기능을 실행하지 않습니다.'),
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
