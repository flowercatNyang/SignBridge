import 'dart:convert';
import 'package:flutter/material.dart';
import 'actions.dart';
import 'design.dart';
import 'hand_camera/hand_camera.dart';
import 'sign_commands.dart';

class TranslationPage extends StatefulWidget {
  const TranslationPage(
      {Key? key,
      required this.sos,
      required this.onTab,
      this.developerMode = false})
      : super(key: key);
  final bool sos;
  final bool developerMode;
  final ValueChanged<int> onTab;
  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage>
    with WidgetsBindingObserver {
  final _gate = CommandGate();
  final _actions = DeviceActions();
  String _status = '인식 대기 중';
  bool _busy = false;
  bool _foreground = true;
  final List<int> _timerDigits = [];
  bool _settingTimer = false;
  bool _digitArmed = true;
  static const _digitNames = ['분의 십의 자리', '분의 일의 자리', '초의 십의 자리', '초의 일의 자리'];
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
    if (!_foreground) {
      _digitArmed = false;
      _gate.reset();
      _gate.armed = false;
    }
    if (mounted) setState(() {});
  }

  void _prediction(SignPrediction prediction) {
    if (_busy || !_foreground || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (_settingTimer) {
      if (!_digitArmed ||
          !prediction.confidence.isFinite ||
          prediction.confidence < .85 ||
          prediction.confidence > 1) return;
      final command = resolveCommand(prediction.text, shortcuts: true);
      if (command != null) _timerDigit(int.parse(command.substring(8)));
      return;
    }
    final command = _gate.accept(prediction, widget.sos, DateTime.now());
    if (command != null) _confirmCommand(command);
  }

  Future<bool> _confirm(String title, String body, {String yes = '실행'}) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(title),
                content: Text(body),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(yes)),
                ],
              )) ==
      true;

  Future<void> _confirmCommand(String command) async {
    if (_busy || !_foreground) return;
    setState(() {
      _busy = true;
      _gate.armed = false;
    });
    final label = command == 'endCall'
        ? '통화 종료'
        : shortcutLabels[int.parse(command.substring(8)) - 1];
    final accepted = await _confirm('이 명령이 맞을까요?', label);
    if (!mounted) return;
    setState(() => _busy = false);
    if (accepted && _foreground) {
      await _execute(command);
    } else {
      setState(() => _status = '명령을 취소했습니다.');
    }
  }

  Future<void> _timerDigit(int digit) async {
    if (_busy || !_foreground || !_digitArmed || _timerDigits.length >= 4) {
      return;
    }
    if (_timerDigits.length == 2 && digit > 5) {
      setState(() => _status = '초의 십의 자리는 0~5만 입력할 수 있습니다.');
      return;
    }
    setState(() {
      _busy = true;
      _digitArmed = false;
    });
    final accepted = await _confirm(
        '이 숫자가 맞을까요?', '${_digitNames[_timerDigits.length]}: $digit',
        yes: '입력');
    if (!mounted) return;
    if (accepted && _foreground) _timerDigits.add(digit);
    setState(() {
      _busy = false;
      _status = '다음 숫자 인식을 눌러 계속해 주세요.';
    });
    if (_timerDigits.length != 4) return;
    final minutes = _timerDigits[0] * 10 + _timerDigits[1];
    final seconds = _timerDigits[2] * 10 + _timerDigits[3];
    if (minutes == 0 && seconds == 0) {
      setState(() {
        _timerDigits.clear();
        _status = '1초 이상 입력해 주세요.';
      });
      return;
    }
    setState(() => _busy = true);
    final start = await _confirm('타이머를 시작할까요?', '$minutes분 $seconds초');
    if (!mounted) return;
    try {
      final result = start && _foreground
          ? await _actions.execute('timer', '${minutes * 60 + seconds}')
          : '타이머 설정을 취소했습니다.';
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _settingTimer = false;
          _busy = false;
        });
      }
    }
  }

  Future<String?> _input(String title, String hint,
      {String initial = '', bool phone = false}) async {
    return showDialog<String>(
        context: context,
        builder: (_) => _InputDialog(
            title: title, hint: hint, initial: initial, phone: phone));
  }

  Future<void> _register() async {
    try {
      final saved = await _actions.loadPhone();
      if (!mounted) return;
      final value = await _input('전화·메시지 번호 등록', '예: 01012345678',
          initial: saved, phone: true);
      if (!mounted || value == null) return;
      final phone = value.replaceAll(RegExp(r'[\s()-]'), '');
      if (!RegExp(r'^\+?[0-9]{3,15}$').hasMatch(phone)) {
        throw Exception('올바른 전화번호를 입력해 주세요.');
      }
      await _actions.savePhone(phone);
      if (mounted) setState(() => _status = '전화·메시지 번호를 저장했습니다.');
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    }
  }

  Future<void> _execute(String command) async {
    setState(() {
      _busy = true;
      _status = '명령 실행 중…';
    });
    try {
      String result;
      if (command == 'endCall') {
        result = await _actions.execute('endCall');
      } else {
        final number = int.parse(command.substring(8));
        if (number == 7) {
          _timerDigits.clear();
          _settingTimer = true;
          _digitArmed = false;
          result = '분과 초를 숫자 수어로 한 자리씩 입력해 주세요.';
        } else if (number == 6) {
          final phone = await _actions.loadPhone();
          if (!mounted) return;
          if (phone.isEmpty) throw Exception('먼저 전화·메시지 번호를 등록해 주세요.');
          final body = await _input('메시지 보내기', '메시지 내용을 입력하세요');
          if (!mounted) return;
          result = body == null || body.isEmpty
              ? '메시지 작성을 취소했습니다.'
              : await _actions.execute(
                  'message', jsonEncode({'phone': phone, 'body': body}));
        } else if (number >= 8) {
          result = '$number번: 미정 · 아직 기능이 없습니다.';
        } else if (number <= 3) {
          final phone = number == 1
              ? '112'
              : number == 2
                  ? '119'
                  : await _actions.loadPhone();
          if (!mounted) return;
          if (phone.isEmpty) throw Exception('먼저 긴급 전화번호를 등록해 주세요.');
          result = await _actions.execute(number == 3 ? 'call' : 'dial', phone);
        } else if (number == 4) {
          result = await _actions.execute('baemin');
        } else {
          final korean = await _input('한국어 → 영어', '번역할 한국어를 입력하세요');
          if (!mounted) return;
          result = korean == null || korean.isEmpty
              ? '번역을 취소했습니다.'
              : await _actions.execute('translate', korean);
        }
      }
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.sos ? '단축키 실행' : '손 동작 인식'), centerTitle: true),
        bottomNavigationBar: DemoNavigation(onTap: widget.onTab),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Badge(widget.sos ? '단축키 · 숫자 수어 1~9' : '실시간 손 인식',
                icon: Icons.pan_tool_outlined),
            gap,
            SizedBox(
                height: widget.sos ? 280 : 420,
                child: HandCamera(onPrediction: _prediction)),
            gap,
            Text(_status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17)),
            if (_busy) const Text('명령 확인 및 처리 중…', textAlign: TextAlign.center),
            if (_settingTimer) ...[
              Text(
                  '타이머 ${_timerDigits.take(2).join().padRight(2, "_")}분 ${_timerDigits.skip(2).join().padRight(2, "_")}초',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24)),
              if (_timerDigits.length < 4)
                Text(
                    '${_digitNames[_timerDigits.length]} 입력 (0~${_timerDigits.length == 2 ? 5 : 9})'),
              const Text('숫자 1~9는 수어로 입력합니다. 0은 아래 버튼을 눌러 주세요.'),
              if (!_digitArmed && !_busy)
                PrimaryButton(
                    '다음 숫자 인식',
                    () => setState(() {
                          _digitArmed = true;
                          _status = '숫자 수어를 보여 주세요.';
                        })),
              OutlinedButton(
                  onPressed:
                      !_busy && _digitArmed ? () => _timerDigit(0) : null,
                  child: const Text('0 입력')),
              if (widget.developerMode)
                Wrap(
                    spacing: 8,
                    children: List.generate(
                        9,
                        (i) => OutlinedButton(
                            onPressed: !_busy && _digitArmed
                                ? () => _timerDigit(i + 1)
                                : null,
                            child: Text('숫자 ${i + 1}')))),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _settingTimer = false;
                            _status = '타이머 설정을 취소했습니다.';
                          }),
                  child: const Text('타이머 취소')),
            ],
            if (!_gate.armed && !_busy && !_settingTimer)
              PrimaryButton(
                  '다시 인식하기',
                  () => setState(() {
                        _gate.reset();
                        _status = '인식 대기 중';
                      })),
            gap,
            const Text(
                '0.5초 간격으로 예측합니다. 신뢰도 85% 이상으로 한 번 인식하면 명령을 확인하고 실행합니다. 실행 후에는 다시 인식하기를 눌러 주세요.'),
            gap,
            if (widget.sos) ...[
              if (widget.developerMode)
                const Text('개발자 모드 · 번호를 누르면 실제 기능 실행을 요청합니다.'),
              ...shortcutLabels.asMap().entries.map((e) => ListTile(
                  leading: CircleAvatar(child: Text('${e.key + 1}')),
                  title: Text(e.value),
                  trailing: widget.developerMode
                      ? const Icon(Icons.play_arrow)
                      : null,
                  onTap: widget.developerMode && !_busy && !_settingTimer
                      ? () => _confirmCommand('shortcut${e.key + 1}')
                      : null)),
              OutlinedButton(
                  onPressed: _busy || _settingTimer ? null : _register,
                  child: const Text('전화·메시지 번호 등록 / 변경')),
              const Text(
                  '112·119는 전화 앱에서 발신합니다. 5번은 Google 번역, 6번은 메시지 앱의 전송 화면, 7번은 Android 시계 앱으로 연결합니다.'),
            ] else
              const Text(
                  '지원 명령: 전화 끊어줘, 통화 종료해줘, 전화 끊어주세요 등. Android 통화 제어 권한이 필요합니다.'),
            gap,
            Text(
                widget.sos
                    ? '기본 수어 모델로 숫자 1~9를 인식합니다. 현재 모델의 정확도는 개선 중입니다.'
                    : '현재 기본 수어 모델을 사용합니다. 통화 종료 문장 인식은 개선 모델 연결 후 지원됩니다.',
                style: const TextStyle(color: muted)),
          ]),
        ))),
      );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog(
      {required this.title,
      required this.hint,
      required this.initial,
      required this.phone});
  final String title, hint, initial;
  final bool phone;
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
            controller: _controller,
            autofocus: true,
            keyboardType:
                widget.phone ? TextInputType.phone : TextInputType.multiline,
            maxLines: widget.phone ? 1 : 4,
            decoration: InputDecoration(hintText: widget.hint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: const Text('확인')),
        ],
      );
}
