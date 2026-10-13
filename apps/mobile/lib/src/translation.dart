import 'dart:convert';
import 'package:flutter/material.dart';
import 'actions.dart';
import 'design.dart';
import 'hand_camera/hand_camera.dart';
import 'sign_commands.dart';
import 'assistant_page.dart';
import 'gloss_test_panel.dart';

class TranslationPage extends StatefulWidget {
  const TranslationPage({Key? key}) : super(key: key);
  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage>
    with WidgetsBindingObserver {
  final _gate = CommandGate();
  final _actions = DeviceActions();
  final _developerGloss = <String>[];
  String _status = '인식 대기 중', _translation = '';
  bool _busy = false, _foreground = true, _developerMode = false, _assistantOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_busy) {
      _status =
          _foreground ? '자동 실행 대기 중 · 수어를 보여 주세요.' : '앱으로 돌아오면 자동 실행을 계속합니다.';
    }
    if (mounted) setState(() {});
  }

  void _prediction(SignPrediction prediction) {
    if (_assistantOpen || _developerMode ||
        _busy ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final command = _gate.accept(prediction);
    setState(() {
      _translation = prediction.text;
      // Keep the action result/error visible while the same sign is held.
      if (_gate.armed) {
        _status = prediction.text.isEmpty
            ? '자동 실행 대기 중 · 수어를 보여 주세요.'
            : prediction.confidence.isFinite
                ? '신뢰도 ${(prediction.confidence * 100).floor()}% · 75% 이상이면 자동 실행합니다.'
                : '인식 결과를 다시 확인하는 중입니다.';
      }
    });
    if (command != null) _execute(command);
  }

  void _testWord(String word) {
    if (!_developerMode ||
        _busy ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) return;
    _gate.reset();
    final command = _gate.accept(SignPrediction(word, 1));
    if (command == null) return;
    setState(() => _translation = word);
    _execute(command);
  }

  void _restartRecognition() {
    setState(() {
      _gate.reset();
      _translation = '';
      _status = _developerMode ? '테스트할 단어를 눌러 주세요.' : '새 동작을 보여 주세요.';
    });
  }

  Future<void> _openAssistant({bool fromDrawer = true, String initialGloss = '',
    bool developerMode = false}) async {
    if (_busy || _assistantOpen) return;
    if (fromDrawer) Navigator.pop(context);
    setState(() {
      _assistantOpen = true;
      _gate.reset();
    });
    await Navigator.push<void>(context,
        MaterialPageRoute(builder: (_) => AssistantPage(
            initialGloss: initialGloss, developerMode: developerMode)));
    if (mounted) setState(() => _assistantOpen = false);
  }

  Future<void> _execute(String command) async {
    setState(() {
      _busy = true;
      _status = '기능 실행 중…';
    });
    try {
      final result = await _actions.execute(command);
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerCompany() async {
    setState(() => _busy = true);
    try {
      final saved = await _actions.loadCompany();
      if (!mounted) return;
      final value = await showDialog<String>(
          context: context, builder: (_) => _CompanyDialog(initial: saved));
      if (value == null || !mounted) return;
      await _actions.saveCompany(value);
      if (mounted) {
        _gate.reset();
        setState(() => _status = '회사 위치를 저장했습니다.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('단축키 실행'), actions: [
          Builder(
              builder: (context) => IconButton(
                  tooltip: '메뉴',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openEndDrawer())),
        ]),
        endDrawer: Drawer(
            child: SafeArea(
                child: ListView(children: [
          ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('단축키 실행'),
              onTap: () => Navigator.pop(context)),
          ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('LLM 비서'),
              onTap: _busy ? null : () => _openAssistant()),
        ]))),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Badge('수어 번역 후 자동 실행', icon: Icons.translate),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('개발자 모드'),
              subtitle: const Text('단어 버튼으로 실제 기능을 테스트합니다'),
              value: _developerMode,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _developerMode = value;
                        _developerGloss.clear();
                        _gate.reset();
                        _translation = '';
                        _status = value ? '테스트할 단어를 눌러 주세요.' : '인식 대기 중';
                      }),
            ),
            if (_developerMode) ...[
              const Text('버튼을 누르면 전화·길찾기·볼륨 기능을 실제로 실행합니다. '
                  '개발자 모드에서는 카메라 자동 실행이 일시 중지됩니다.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ...shortcutCommands.keys.map((word) => OutlinedButton(
                      onPressed:
                          _busy || !_foreground ? null : () => _testWord(word),
                      child: Text('테스트: $word'),
                    )),
              ]),
              gap,
              GlossTestPanel(text: _developerGloss.join(' '),
                disabled: _busy || !_foreground,
                onWord: (word) => setState(() => _developerGloss.add(word)),
                onUndo: () => setState(() => _developerGloss.removeLast()),
                onClear: () => setState(() => _developerGloss.clear()),
                onSubmit: () => _openAssistant(fromDrawer: false,
                    initialGloss: _developerGloss.join(' '), developerMode: true)),
            ],
            gap,
            if (!_assistantOpen && !_developerMode)
              SizedBox(height: 300, child: HandCamera(onPrediction: _prediction)),
            gap,
            Text(_translation.isEmpty ? '수어를 보여 주세요.' : '번역: $_translation',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center),
            if (_busy) const Center(child: Text('처리 중…')),
            if (!_developerMode && !_gate.armed && !_busy) ...[
              gap,
              PrimaryButton('다시 인식하기', _restartRecognition)
            ],
            gap,
            Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                  Text('아프다 → 긴급신고 · 119 전화'),
                  SizedBox(height: 12),
                  Text('회사 → 등록한 회사로 네이버맵 길찾기'),
                  SizedBox(height: 12),
                  Text('엄마 → 전화번호부의 엄마에게 전화'),
                  SizedBox(height: 12),
                  Text('위 / 아래 → 미디어 볼륨 올리기 / 내리기'),
                ])),
            gap,
            OutlinedButton(
                onPressed: _busy ? null : _registerCompany,
                child: const Text('회사 위치 등록 / 변경')),
            gap,
            const Text(
                '신뢰도 75% 이상이면 바로 실행합니다. 다른 단어는 버튼 없이 계속 실행됩니다. 같은 단어를 다시 실행하려면 손을 잠시 내렸다가 다시 보여 주세요.'),
            const SizedBox(height: 12),
            const Text(
                '119는 전화 앱에서 통화 버튼을 눌러 발신합니다. 연락처 전화와 볼륨 조절은 Android 앱에서 지원합니다.',
                style: TextStyle(color: muted)),
          ]),
        ))),
      );
}

class _CompanyDialog extends StatefulWidget {
  const _CompanyDialog({required this.initial});
  final String initial;
  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  final _name = TextEditingController(),
      _lat = TextEditingController(),
      _lng = TextEditingController();
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      final data = jsonDecode(widget.initial) as Map<String, dynamic>;
      _name.text = data['name'] as String;
      _lat.text = '${data['lat']}';
      _lng.text = '${data['lng']}';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _save() {
    final lat = double.tryParse(_lat.text.trim()),
        lng = double.tryParse(_lng.text.trim());
    if (_name.text.trim().isEmpty ||
        lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < 31.43 ||
        lat > 44.35 ||
        lng < 122.37 ||
        lng > 132) {
      setState(() => _error = '회사 이름과 유효한 국내 위치 좌표를 입력해 주세요.');
      return;
    }
    Navigator.pop(context,
        jsonEncode({'name': _name.text.trim(), 'lat': lat, 'lng': lng}));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('회사 위치 등록'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('네이버맵 길찾기에 사용할 회사 위치 좌표를 입력해 주세요.'),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '회사 이름')),
            TextField(
                controller: _lat,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '위도', hintText: '예: 37.5665')),
            TextField(
                controller: _lng,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '경도', hintText: '예: 126.9780')),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: danger)),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소')),
            TextButton(onPressed: _save, child: const Text('저장')),
          ]);
}
