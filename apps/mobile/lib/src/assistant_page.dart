import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'actions.dart';
import 'assistant_client.dart';
import 'design.dart';
import 'hand_camera/hand_camera.dart';
import 'sign_commands.dart';
import 'gloss_test_panel.dart';
import 'alarm_page.dart';
import 'translation.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({Key? key, this.request, this.initialGloss = '',
    this.developerMode = false}) : super(key: key);
  final AssistantRequester? request;
  final String initialGloss;
  final bool developerMode;
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _server = TextEditingController(text: defaultAssistantUrl());
  final _token = TextEditingController(
      text: const String.fromEnvironment('ASSISTANT_ACCESS_TOKEN'));
  final _history = <Map<String, String>>[];
  final _gate = RecognitionGate();
  final _actions = DeviceActions();
  static const _background = MethodChannel('signbridge/background');
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  AssistantReply? _reply;
  String _inputType = 'text', _status = '';
  bool _busy = false, _camera = false, _foreground = true;
  bool _developerMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    _developerMode = widget.developerMode;
    _input.text = widget.initialGloss;
    if (widget.initialGloss.isNotEmpty) _inputType = 'gloss';
    if (_android) _stopBackground();
  }

  Future<void> _stopBackground() async {
    try {
      await _background.invokeMethod('setEnabled', false);
    } on MissingPluginException {
      // Older installs have no background service.
    } on PlatformException catch (error) {
      if (mounted) setState(() => _status = error.message ?? '백그라운드 인식을 중지하지 못했습니다.');
    }
  }

  Future<void> _takeBackgroundInput() async {
    if (_busy) return;
    setState(() { _busy = true; _camera = false; });
    try {
      final text = await _background.invokeMethod<String>('takeInput') ?? '';
      if (!mounted) return;
      if (text.isEmpty) {
        setState(() => _status = '가져올 백그라운드 입력이 없습니다.');
      } else {
        _reset();
        setState(() {
          _input.text = text;
          _inputType = 'gloss';
          _status = '백그라운드 입력을 가져왔습니다. 입력 완료를 눌러 해석해 주세요.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _status = error.message ?? '입력을 가져오지 못했습니다.');
    } on MissingPluginException {
      if (mounted) setState(() => _status = '백그라운드 입력은 Android 앱에서 지원합니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    _input.dispose();
    _server.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _camera) {
      setState(() {
        _camera = false;
        _status = '카메라를 껐습니다. 입력을 이어가려면 다시 시작해 주세요.';
      });
    }
  }

  void _prediction(SignPrediction prediction) {
    if (!_camera || _busy || !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) return;
    final word = _gate.accept(prediction);
    if (word != null) _appendGloss(word);
  }

  void _appendGloss(String word) {
    if (_busy || !_foreground) return;
    if (_reply == null && (word == '그렇다' || word == '틀리다')) {
      setState(() => _status = '확인할 요청이 없습니다. 내용을 먼저 입력해 주세요.');
      return;
    }
    if (_reply != null && (word == '그렇다' || word == '틀리다')) {
      if (word == '틀리다') {
        _reset();
        setState(() => _status = '이전 요청을 폐기했습니다. 다시 입력해 주세요.');
      } else if (_reply!.action != null) {
        _execute(confirmed: true);
      } else if (_reply!.question != null) {
        _input.text = '그렇다';
        _inputType = 'text';
        _interpret();
      }
      return;
    }
    setState(() {
      final previous = _inputType == 'gloss' ? _input.text.trim() : '';
      final combined = previous.isEmpty ? word : '$previous $word';
      if (combined.length > 2000) {
        _status = '입력이 너무 깁니다. 일부 단어를 삭제해 주세요.';
        return;
      }
      _input.text = combined;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      _inputType = 'gloss';
      if (_reply?.action != null) _reply = null;
      _status = '표현을 추가했습니다. 인식 내용을 확인하거나 수정해 주세요.';
    });
  }

  void _editGloss({bool clear = false}) {
    setState(() {
      final words = _input.text.trim().split(RegExp(r'\s+'));
      _input.text = clear || words.length <= 1 ? '' : (words..removeLast()).join(' ');
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      _inputType = 'gloss';
      if (_reply?.action != null) _reply = null;
    });
  }

  void _reset() {
    setState(() {
      _camera = false;
      _gate.reset();
      _history.clear();
      _reply = null;
      _input.clear();
      _inputType = 'text';
      _status = '';
    });
  }

  Future<void> _interpret() async {
    final text = _input.text.trim();
    if (_busy) return;
    if (text.isEmpty) {
      setState(() => _status = '요청 또는 답변을 입력해 주세요.');
      return;
    }
    final inputType = _inputType;
    setState(() {
      _camera = false;
      _busy = true;
      _reply = null;
      _status = '요청을 해석하는 중…';
    });
    try {
      final result = await (widget.request ?? requestAssistant)(
          baseUrl: _server.text, accessToken: _token.text, text: text,
          inputType: inputType, history: List<Map<String, String>>.from(_history));
      if (!mounted) return;
      setState(() {
        _reply = result;
        _gate.reset(requireRelease: true);
        if (result.question != null) {
          _history.add({'role': 'user',
            'content': inputType == 'gloss' ? '[수어 인식 라벨] $text' : text});
          _history.add({'role': 'assistant',
            'content': '번역 후보: ${result.translation}\n추가 질문: ${result.question!}'});
          _input.clear();
          _inputType = 'text';
          _status = '추가 질문에 답해 주세요. 수어 입력도 사용할 수 있습니다.';
        } else {
          _status = result.action == null
              ? '번역 후보입니다. 실행할 기능은 없습니다.'
              : '번역과 실행 내용을 확인한 뒤 실행해 주세요.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute({bool confirmed = false}) async {
    final reply = _reply;
    final action = reply?.action;
    if (_busy || reply == null || action == null || !_foreground) return;
    setState(() => _busy = true);
    final approved = confirmed || await showDialog<bool>(context: context, builder: (context) =>
        AlertDialog(title: const Text('실행 내용 확인'),
          content: SingleChildScrollView(child: Text(
              '${reply.translation}\n\n${action.summary}\n\n'
              '${action.name == 'adjust_volume' ? '확인하면 미디어 볼륨을 한 단계 변경합니다.' : action.name == 'compose_message' ? '문자 앱에서 최종 전송합니다.' : action.arguments.containsKey('date') ? 'SignBridge 날짜 알림을 예약합니다.' : '시계 앱에서 실제 설정을 확인해 주세요.'}')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('확인하고 열기')),
          ])) == true;
    if (!mounted) return;
    if (!approved || !_foreground) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _camera = false;
      // Consume this plan before opening another app; returning must not replay it.
      _reply = null;
      _history.clear();
    });
    try {
      final message = await _actions.execute(action.name, jsonEncode(action.arguments));
      if (mounted) setState(() => _status = message);
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _example(String text) {
    _reset();
    setState(() => _input.text = text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LLM 비서')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        description('수어 인식 결과를 한국어 번역 후보로 정리하고 알람·문자 작성·볼륨 조절을 도와드립니다. '
            '의미가 다르거나 빠졌다면 수정해 주세요.'),
        const SizedBox(height: 12),
        if (_android) OutlinedButton(key: const Key('assistant-background-input'),
          onPressed: _busy ? null : _takeBackgroundInput,
          child: const Text('백그라운드 입력 가져오기')),
        TextButton(onPressed: _busy ? null : () async {
          setState(() => _camera = false);
          await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const TranslationPage()));
        }, child: const Text('기존 입력 화면 · 회사 위치 등록')),
        ElevatedButton(key: const Key('assistant-alarm-wizard'),
          onPressed: _busy ? null : () async {
            setState(() { _camera = false; _gate.reset(); });
            await Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
                AlarmPage(developerMode: _developerMode)));
          }, child: const Text('알람 · 숫자로 시간·날짜 입력')),
        ExpansionTile(title: const Text('서버 연결 설정'), children: [
          TextField(key: const Key('assistant-server'), controller: _server,
            enabled: !_busy, decoration: const InputDecoration(labelText: '백엔드 주소')),
          TextField(key: const Key('assistant-token'), controller: _token,
            enabled: !_busy, obscureText: true,
            decoration: const InputDecoration(labelText: '서버 연결 토큰 (설정한 경우)')),
          const Text('NVIDIA API 키는 앱이 아니라 백엔드에 입력합니다.'),
        ]),
        gap,
        SwitchListTile(contentPadding: EdgeInsets.zero,
          title: const Text('개발자 모드'),
          subtitle: const Text('단어 버튼으로 수어 인식 결과를 조합합니다'),
          value: _developerMode,
          onChanged: _busy ? null : (value) => setState(() {
            _developerMode = value;
            _camera = false;
            _gate.reset();
          })),
        if (_developerMode) ...[
          GlossTestPanel(text: _inputType == 'gloss' ? _input.text.trim() : '',
            disabled: _busy || !_foreground,
            onWord: _appendGloss,
            onUndo: () => _editGloss(), onClear: () => _editGloss(clear: true)),
          const SizedBox(height: 12),
        ],
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : () => _example('오전 7시에 기상 알람 설정해줘'),
              child: const Text('알람 예시')),
          OutlinedButton(onPressed: _busy ? null : () => _example('엄마에게 늦을 것 같다고 문자 작성해줘'),
              child: const Text('문자 예시')),
          TextButton(onPressed: _busy ? null : _reset, child: const Text('새 요청')),
        ]),
        DropdownButton<String>(value: _inputType, isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'text', child: Text('한국어 직접 입력')),
            DropdownMenuItem(value: 'gloss', child: Text('수어 인식 라벨 입력')),
          ],
          onChanged: _busy || _camera ? null : (value) => setState(() {
            _inputType = value!;
            if (_reply?.action != null) _reply = null;
          })),
        TextField(key: const Key('assistant-input'), controller: _input,
          enabled: !_busy, maxLength: 2000, minLines: 2, maxLines: 5,
          onChanged: (_) => setState(() {
            if (_reply?.action != null) _reply = null;
          }),
          decoration: const InputDecoration(border: OutlineInputBorder(),
              labelText: '요청 또는 추가 질문의 답변', hintText: '인식 결과를 확인하거나 직접 입력하세요.')),
        OutlinedButton.icon(icon: Icon(_camera ? Icons.stop : Icons.videocam),
          label: Text(_camera ? '촬영 종료' : '수어 입력 시작'),
          onPressed: _busy || _developerMode ? null : () => setState(() {
            _camera = !_camera;
            _gate.reset(requireRelease: _reply != null);
            if (_camera) {
              _inputType = 'gloss';
            }
          })),
        if (_camera) ...[
          const Text('배포된 모델에 포함된 단어만 인식합니다. 단어마다 손을 0.8초 이상 내려 주세요. '
              '현재 임시 목록은 두 종류의 위와 확인 수어를 포함한 13개 클래스입니다. 새 단어는 학습·모델 배포 후 사용할 수 있습니다.'),
          SizedBox(height: 300, child: HandCamera(onPrediction: _prediction)),
        ],
        const SizedBox(height: 12),
        ElevatedButton(key: const Key('assistant-submit'), onPressed: _busy ? null : _interpret,
          child: Text(_busy ? '처리 중…' : '입력 완료 · 해석하기')),
        if (_busy) const LinearProgressIndicator(),
        gap,
        if (_reply != null) Panel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_reply!.mode == 'mock') const Badge('모의 응답 · 실제 LLM 번역 아님', color: muted),
            const Text('한국어 번역 후보', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_reply!.translation),
            if (_reply!.question != null) ...[
              gap,
              Text(_reply!.question!, style: const TextStyle(fontSize: 18, color: primary)),
            ],
            if (_reply!.action != null) ...[
              gap,
              Text(_reply!.action!.summary),
              ElevatedButton(key: const Key('assistant-execute'),
                onPressed: _busy ? null : () => _execute(), child: const Text('확인 후 실행')),
            ],
            if (_reply!.action != null || _reply!.question != null) ...[
              const Text('확인 화면에서 그렇다 = 승인, 틀리다 = 요청 폐기 후 재입력. 화면 버튼도 사용할 수 있습니다.'),
              TextButton(onPressed: _busy ? null : () => _appendGloss('그렇다'),
                child: const Text('그렇다')),
              TextButton(onPressed: _busy ? null : () => _appendGloss('틀리다'),
                child: const Text('틀리다')),
            ],
          ])),
        gap,
        Text(_status, key: const Key('assistant-status')),
        const SizedBox(height: 12),
        description('알람·문자 실행은 Android에서 지원합니다. '
            '날짜 알람은 앱 내부 알림으로 예약합니다. 병원 검색과 길 찾기 등 LLM 도구 확장은 별도 작업입니다.'),
      ]),
    ))),
  );
}
