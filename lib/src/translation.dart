import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'hand_camera/hand_camera.dart';

class TranslationPage extends StatefulWidget {
  const TranslationPage({Key? key, required this.sos, required this.onTab})
      : super(key: key);
  final bool sos;
  final ValueChanged<int> onTab;

  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

enum _Stage { camera, processing, complete }

class _TranslationPageState extends State<TranslationPage> {
  _Stage _stage = _Stage.camera;
  Timer? _timer;
  String get _command => widget.sos ? '도와주세요' : '전화 끊어줘';

  void _execute() {
    if (_stage != _Stage.camera) return;
    setState(() => _stage = _Stage.processing);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _stage = _Stage.complete);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(_stage == _Stage.camera ? '손 동작 인식' : 'SignBridge'),
            centerTitle: true),
        bottomNavigationBar: DemoNavigation(onTap: widget.onTab),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                  key: ValueKey(_stage),
                  padding: const EdgeInsets.all(20),
                  children: _stage == _Stage.camera
                      ? _camera()
                      : _stage == _Stage.processing
                          ? _processing()
                          : _complete()),
            ),
          ),
        ),
      );

  List<Widget> _camera() => [
        Badge(widget.sos ? 'SOS · 손 인식 데모' : '실시간 손 인식',
            icon: Icons.pan_tool_outlined),
        const SizedBox(height: 16),
        const SizedBox(height: 420, child: HandCamera()),
        gap,
        PrimaryButton('명령 실행', _execute, icon: Icons.send),
        const SizedBox(height: 8),
        const Text('예시 명령으로 실행 화면을 체험합니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted)),
        gap,
        const Panel(
          child: Text(
            '양손과 어깨가 카메라에 보이도록 수화를 해 주세요. 동작을 모아 카메라 위에 인식한 단어와 신뢰도를 표시합니다.\n\n'
            '학습된 112개 수화 클래스를 인식합니다. 테스트를 위해 신뢰도가 낮아도 가장 높은 점수의 단어를 표시합니다. 명령 실행은 예시 화면을 체험하는 기능입니다.',
            style: TextStyle(height: 1.6, color: muted),
          ),
        ),
        gap,
        const Text('영상은 기기에서 처리하며 저장하거나 전송하지 않습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted)),
      ];

  List<Widget> _processing() => [
        const SizedBox(height: 32),
        const Icon(Icons.flash_on, size: 64, color: primary),
        gap,
        Center(child: heading('명령 실행 중...')),
        const SizedBox(height: 8),
        Center(child: description('SignBridge가 요청을 처리하고 있어요')),
        const SizedBox(height: 40),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 40),
        Panel(
            child: Column(children: [
          Icon(widget.sos ? Icons.notification_important : Icons.call_end,
              color: primary, size: 40),
          gap,
          const Badge('예시 명령 · 데모'),
          const SizedBox(height: 12),
          heading('“$_command”'),
        ])),
        gap,
        const Text('잠시 후 실행 완료 화면으로 이동합니다.',
            textAlign: TextAlign.center, style: TextStyle(color: muted)),
      ];

  List<Widget> _complete() => [
        const SizedBox(height: 28),
        const Center(
            child: CircleAvatar(
                radius: 52,
                backgroundColor: Color(0xFFE3F0EC),
                child: Icon(Icons.check_circle, color: green, size: 64))),
        const SizedBox(height: 28),
        Center(child: heading('명령 실행 완료')),
        const SizedBox(height: 12),
        Text("'$_command' 예시 명령의\n실행 데모가 완료되었습니다.",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, height: 1.7, color: muted)),
        gap,
        const Center(child: Badge('시뮬레이션 결과', color: green)),
        gap,
        Panel(
            child: Row(children: [
          Icon(widget.sos ? Icons.notification_important : Icons.call_end,
              color: primary, size: 32),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description('예시 명령'), heading(_command)])),
        ])),
        gap,
        const Text('실제 기기 제어나 긴급 신고는 수행하지 않습니다.',
            textAlign: TextAlign.center, style: TextStyle(color: muted)),
        const SizedBox(height: 28),
        PrimaryButton('확인', () => Navigator.pop(context), icon: Icons.done),
        TextButton(
            onPressed: () => setState(() => _stage = _Stage.camera),
            child: const Text('다시 인식하기')),
      ];
}
