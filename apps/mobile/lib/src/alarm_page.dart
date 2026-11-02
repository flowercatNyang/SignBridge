import 'dart:convert';
import 'package:flutter/material.dart';
import 'actions.dart';
import 'alarm_input.dart';
import 'assistant_client.dart';
import 'hand_camera/hand_camera.dart';
import 'sign_commands.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({Key? key, this.developerMode = false}) : super(key: key);
  final bool developerMode;
  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with WidgetsBindingObserver {
  final _input = AlarmInput();
  final _gate = RecognitionGate();
  final _actions = DeviceActions();
  String _stage = 'time', _status = '';
  bool _camera = false, _busy = false, _foreground = true;
  late bool _developer;

  @override
  void initState() {
    super.initState();
    _developer = widget.developerMode;
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
    if (!_foreground) setState(() { _camera = false; _gate.reset(); });
  }

  void _transition(String stage) {
    _stage = stage;
    _status = '';
    _gate.reset(requireRelease: true);
  }

  void _prediction(SignPrediction prediction) {
    if (!_camera || _busy || !_foreground || ModalRoute.of(context)?.isCurrent != true) return;
    final word = _gate.accept(prediction);
    if (word != null) _word(word);
  }

  void _word(String word) {
    if (_busy || !_foreground) return;
    if (_stage == 'confirm') {
      if (word == '그렇다') _execute();
      if (word == '틀리다') _restart();
      return;
    }
    setState(() {
      if (_stage == 'time' || _stage == 'date') {
        final digit = signDigit(word);
        if (digit != null) _input.add(digit);
      } else if (_stage == 'schedule' && word == '매일매일') {
        _input.days = [1, 2, 3, 4, 5, 6, 7];
        _transition('confirm');
      }
    });
  }

  void _next() {
    try {
      if (_stage == 'time') {
        _input.acceptTime();
        setState(() => _transition('schedule'));
      } else if (_stage == 'date') {
        _input.acceptDate(DateTime.now());
        setState(() => _transition('confirm'));
      }
    } on FormatException catch (error) {
      setState(() => _status = error.message);
    }
  }

  void _restart() => setState(() {
    _input.digits = '';
    _input.date = null;
    _input.days = [];
    _transition('time');
    _status = '이전 요청을 폐기했습니다. 시간을 다시 입력해 주세요.';
  });

  Future<void> _execute() async {
    if (_busy || _stage != 'confirm' || !_foreground) return;
    final action = AssistantAction.fromJson({'name': 'set_alarm', 'arguments': _input.arguments});
    if (_input.date != null && !_input.date!.isAfter(DateTime.now())) {
      setState(() => _status = '입력한 시각이 지났습니다. 다시 입력해 주세요.');
      return;
    }
    setState(() { _busy = true; _camera = false; _transition('done'); });
    try {
      final result = await _actions.execute(action.name, jsonEncode(action.arguments));
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) setState(() { _transition('confirm'); _status = '$error'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('수어로 알람 설정')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('시간 → 날짜·반복 선택 → 최종 확인 순서입니다. 숫자는 한 자리씩 입력합니다.'),
      SwitchListTile(title: const Text('개발자 모드'), value: _developer,
        onChanged: _busy ? null : (value) => setState(() {
          _developer = value; _camera = false; _gate.reset();
        })),
      if (_stage == 'time' || _stage == 'date') ...[
        Text(_stage == 'time' ? '시간 HHMM · 24시간제 (오후 1시 5분 = 1305)'
            : '날짜 MMDD (12월 5일 = 1205) · 다음 해당 날짜를 제안합니다.'),
        Text(_input.digits.padRight(4, '_'), key: const Key('alarm-digits'),
          style: const TextStyle(fontSize: 36, letterSpacing: 8)),
        // This is a manual keypad, independent of trained recognition classes.
        Wrap(spacing: 8, children: [
          for (var digit = 0; digit <= 9; digit++)
            OutlinedButton(key: Key('alarm-digit-$digit'),
              onPressed: _busy ? null : () => _word('$digit'), child: Text('$digit')),
        ]),
        TextButton(onPressed: _busy ? null : () => setState(_input.undo), child: const Text('한 자리 지우기')),
        ElevatedButton(key: const Key('alarm-next'),
          onPressed: _busy ? null : _next, child: const Text('입력 완료 · 다음')),
      ],
      if (_stage == 'schedule') ...[
        Text('입력 시각: ${_input.hour.toString().padLeft(2, '0')}:${_input.minute.toString().padLeft(2, '0')}'),
        const Text('언제 울리게 할까요?'),
        ElevatedButton(key: const Key('alarm-date'), onPressed: () => setState(() {
          _input.digits = ''; _transition('date');
        }), child: const Text('특정 날짜 지정')),
        OutlinedButton(onPressed: () => setState(() {
          _input.days = []; _transition('confirm');
        }), child: const Text('다음 해당 시각에 한 번')),
        OutlinedButton(onPressed: () => _word('매일매일'), child: const Text('매일 반복')),
        OutlinedButton(onPressed: () => setState(() {
          _input.days = [1, 2, 3, 4, 5]; _transition('confirm');
        }), child: const Text('평일 반복')),
      ],
      if (_stage == 'confirm') ...[
        Text(AssistantAction('set_alarm', _input.arguments).summary,
          key: const Key('alarm-summary'), style: const TextStyle(fontSize: 22)),
        const Text('연도와 날짜도 확인한 뒤 그렇다·틀리다 수어 또는 화면 버튼으로 확인해 주세요.'),
        ElevatedButton(key: const Key('alarm-confirm'), onPressed: _busy ? null : _execute,
          child: const Text('그렇다 · 실행')),
        OutlinedButton(onPressed: _busy ? null : _restart, child: const Text('틀리다 · 다시 입력')),
      ],
      if (_stage != 'done') ...[
        OutlinedButton(onPressed: _busy || _developer ? null : () => setState(() {
          _camera = !_camera; _gate.reset(requireRelease: _stage == 'confirm');
        }), child: Text(_camera ? '촬영 종료' : '수어 입력 시작')),
        if (_camera) ...[
          const Text('임시 모델의 숫자 수어는 8만 지원할 예정입니다. '
              '다른 숫자는 화면 키패드로 입력하세요. 수어마다 손을 0.8초 이상 내려 주세요.'),
          SizedBox(height: 300, child: HandCamera(onPrediction: _prediction)),
        ],
      ],
      if (_busy) const LinearProgressIndicator(),
      Text(_status, key: const Key('alarm-status')),
      if (_stage == 'done') TextButton(onPressed: _busy ? null : _restart, child: const Text('새 알람')),
      const Text('날짜 알람은 SignBridge의 소리·진동 알림으로 예약됩니다. 알림 및 정확한 알람 권한이 필요합니다. '
          '기본 시계 앱 알람처럼 중지할 때까지 계속 울리는 방식은 아닙니다.'),
    ]),
  );
}
