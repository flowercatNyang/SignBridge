import 'package:flutter/material.dart';
import 'design.dart';

class GestureGuide {
  const GestureGuide(this.title, this.action, this.icon, this.steps);
  final String title;
  final String action;
  final IconData icon;
  final List<String> steps;
}

const guides = [
  GestureGuide('두 손가락을 맞대기', '번역 시작', Icons.touch_app, [
    '가슴 높이에서 양손을 가볍게 듭니다. 카메라 렌즈와 정면이 되도록 위치를 잡습니다.',
    '양손의 집게손가락(검지)만 곧게 펴고, 나머지 손가락은 가볍게 쥡니다.',
    '펼친 두 집게손가락의 끝을 서로 가볍게 맞댑니다. 약 2초간 유지합니다.'
  ]),
  GestureGuide('주먹 쥐고 올리기', '그만하기', Icons.pan_tool, [
    '카메라를 향해 한 손을 가슴 높이로 올립니다.',
    '손가락을 접어 주먹을 가볍게 쥡니다.',
    '주먹을 천천히 올리고 잠시 유지합니다.'
  ]),
  GestureGuide('손바닥을 앞으로 밀기', '명령 실행', Icons.pan_tool_outlined, [
    '카메라를 향해 손을 가슴 높이로 올립니다.',
    '손가락을 펴서 손바닥을 보여줍니다.',
    '손바닥을 앞으로 천천히 밀고 잠시 유지합니다.'
  ]),
  GestureGuide('양손을 벌리기', '다시 하기', Icons.open_with,
      ['양손을 가슴 앞에 편하게 모읍니다.', '손바닥을 카메라를 향해 펼칩니다.', '양손을 좌우로 천천히 벌립니다.']),
];

class GuidePage extends StatelessWidget {
  const GuidePage({Key? key, required this.onTab}) : super(key: key);
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('SignBridge'), centerTitle: true),
      bottomNavigationBar: DemoNavigation(onTap: onTab),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    heading('동작 가이드'),
                    const SizedBox(height: 8),
                    description('향후 사용할 동작 예시를 확인하세요. 현재는 손 관절점만 추적합니다.'),
                    gap,
                    ...guides.map((guide) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Panel(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                        color: pale,
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    child: Icon(guide.icon,
                                        size: 32, color: primary)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      description('동작'),
                                      Text(guide.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 19)),
                                      const SizedBox(height: 6),
                                      Badge(guide.action, icon: Icons.bolt)
                                    ]))
                              ]),
                              const SizedBox(height: 10),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                      onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                              builder: (_) => GuideDetail(
                                                  guide: guide, onTab: onTab))),
                                      icon: const Icon(Icons.arrow_forward,
                                          size: 18),
                                      label: const Text('상세 가이드'))),
                            ])))),
                    description('시안에 정의된 앱 전용 제스처 안내입니다. 실제 수화 인식은 추후 지원됩니다.'),
                  ])))));
}

class GuideDetail extends StatelessWidget {
  const GuideDetail({Key? key, required this.guide, required this.onTab})
      : super(key: key);
  final GestureGuide guide;
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('동작 상세 가이드'), centerTitle: true),
      bottomNavigationBar: DemoNavigation(onTap: onTab),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    const Divider(thickness: 2),
                    gap,
                    heading(guide.title),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => GesturePreview(guide: guide)),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('영상 보기'))),
                    gap,
                    Panel(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('ⓘ  기능 설명',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          description(
                              '향후 ${guide.action} 기능에 사용할 동작 예시입니다. 현재 카메라에서는 손 관절점만 표시하며 이 동작을 명령으로 실행하지 않습니다.')
                        ])),
                    gap,
                    Panel(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('☷  동작 방법',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                          gap,
                          ...List.generate(
                              guide.steps.length,
                              (i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                            radius: 16,
                                            backgroundColor: primary,
                                            child: Text('${i + 1}',
                                                style: const TextStyle(
                                                    color: Colors.white))),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(
                                                  i == 0
                                                      ? '준비 자세'
                                                      : i == 1
                                                          ? '손 모양 만들기'
                                                          : guide.title,
                                                  style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              description(guide.steps[i])
                                            ]))
                                      ])))
                        ])),
                  ])))));
}

class GesturePreview extends StatefulWidget {
  const GesturePreview({Key? key, required this.guide}) : super(key: key);
  final GestureGuide guide;
  @override
  State<GesturePreview> createState() => _GesturePreviewState();
}

class _GesturePreviewState extends State<GesturePreview> {
  int step = 0;
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.guide.title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Badge('영상 대신 단계별 데모', icon: Icons.play_circle_outline),
            gap,
            AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(widget.guide.icon,
                    key: ValueKey(step),
                    color: primary,
                    size: 80 + step * 10.0)),
            gap,
            Text('${step + 1} / 3',
                style: const TextStyle(
                    color: primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            description(widget.guide.steps[step])
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기')),
            TextButton(
                onPressed: () => setState(() => step = (step + 1) % 3),
                child: Text(step == 2 ? '다시 보기' : '다음 동작'))
          ]);
}
