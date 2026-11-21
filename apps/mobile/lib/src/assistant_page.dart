import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'actions.dart';
import 'assistant_client.dart';
import 'assistant_connection.dart';
import 'design.dart';
import 'hand_camera/hand_camera.dart';
import 'sign_commands.dart';
import 'gloss_test_panel.dart';
import 'alarm_page.dart';
import 'translation.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage(
      {Key? key,
      this.request,
      this.initialGloss = '',
      this.developerMode = false,
      this.embedded = false,
      this.onBusyChanged,
      this.executeAction})
      : super(key: key);
  final AssistantRequester? request;
  final String initialGloss;
  final bool developerMode;
  final bool embedded;
  final ValueChanged<bool>? onBusyChanged;
  final AssistantActionExecutor? executeAction;
  @override
  State<AssistantPage> createState() => AssistantPageState();
}

class AssistantPageState extends State<AssistantPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin<AssistantPage> {
  @override
  bool get wantKeepAlive => widget.embedded;
  final _input = TextEditingController();
  final _connection = AssistantConnection.instance;
  final _server = TextEditingController();
  final _token = TextEditingController();
  final _history = <Map<String, String>>[];
  final _conversation = <String>[];
  final _gate = RecognitionGate();
  final _actions = DeviceActions();
  static const _background = MethodChannel('signbridge/background');
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  AssistantReply? _reply;
  String? _originalRequestText;
  String _inputType = 'text', _status = '';
  bool _busy = false, _camera = false, _foreground = true;
  bool _developerMode = false;
  bool _syncingConnection = false, _resumeCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    _developerMode = widget.developerMode;
    _syncConnection();
    _connection.addListener(_syncConnection);
    _server.addListener(_updateConnection);
    _token.addListener(_updateConnection);
    _loadConnection();
    _input.text = widget.initialGloss;
    if (widget.initialGloss.isNotEmpty) _inputType = 'gloss';
    if (_android && !widget.embedded) _stopBackground();
  }

  @override
  void didUpdateWidget(AssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.developerMode != widget.developerMode) {
      _developerMode = widget.developerMode;
      _gate.reset(requireRelease: true);
    }
  }

  void _syncConnection() {
    _syncingConnection = true;
    if (_server.text != _connection.baseUrl) {
      _server.text = _connection.baseUrl;
    }
    if (_token.text != _connection.accessToken) {
      _token.text = _connection.accessToken;
    }
    _syncingConnection = false;
  }

  void _updateConnection() {
    if (!_syncingConnection) _connection.update(_server.text, _token.text);
  }

  Future<void> _loadConnection() async {
    try {
      await _connection.load();
    } catch (_) {
      if (mounted) setState(() => _status = '저장된 연결 설정을 읽지 못했습니다. 다시 설정해 주세요.');
    }
  }

  Future<void> _saveConnection() async {
    try {
      await _connection.save();
      if (mounted) setState(() => _status = '서버 연결 설정을 저장했습니다.');
    } catch (_) {
      if (mounted) {
        setState(() => _status = '연결 설정을 저장하지 못했습니다. 주소와 토큰을 확인해 주세요.');
      }
    }
  }

  void _notifyBusy(bool value) => widget.onBusyChanged?.call(value);

  void _addConversation(String text) {
    _conversation.add(text);
    if (_conversation.length > 24) _conversation.removeAt(0);
  }

  /// Used by the existing camera on the same route; no second camera is opened.
  void acceptPrediction(SignPrediction prediction, {DateTime? timestamp}) {
    if (_busy || !_foreground || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final word = _gate.accept(prediction, timestamp: timestamp);
    if (word != null) acceptGloss(word);
  }

  /// Developer buttons and real recognition both use this exact state machine.
  void acceptGloss(String word) => _appendGloss(word);

  void importGloss(String text) {
    if (_busy || text.trim().isEmpty) return;
    _reset();
    setState(() {
      _input.text = text.trim();
      _inputType = 'gloss';
    });
  }

  void submit() => _interpret();

  Future<void> _stopBackground() async {
    try {
      await _background.invokeMethod('setEnabled', false);
    } on MissingPluginException {
      // Older installs have no background service.
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _status = error.message ?? '백그라운드 인식을 중지하지 못했습니다.');
      }
    }
  }

  Future<void> _takeBackgroundInput() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _camera = false;
    });
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
    _connection.removeListener(_syncConnection);
    _server.removeListener(_updateConnection);
    _token.removeListener(_updateConnection);
    _input.dispose();
    _server.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _camera) {
      _resumeCamera = true;
      setState(() {
        _camera = false;
        _status = '카메라를 껐습니다. 입력을 이어가려면 다시 시작해 주세요.';
      });
    } else if (_foreground) {
      _gate.reset(requireRelease: true);
      if (_resumeCamera) {
        _resumeCamera = false;
        setState(() => _camera = true);
      }
    }
  }

  void _prediction(SignPrediction prediction) {
    if (!_camera ||
        _busy ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true) return;
    acceptPrediction(prediction);
  }

  void _appendGloss(String word) {
    if (_busy || !_foreground) return;
    word = word.trim();
    if (word.isEmpty) return;
    if (word == '틀리다' || word == '아니다' || word == '아니오') {
      _reset();
      setState(() {
        _addConversation('요청을 취소했습니다. 수어로 다시 입력해 주세요.');
        _status = '아니다/틀리다로 요청을 폐기했습니다. 다시 입력해 주세요.';
      });
      return;
    }
    if (word == '그렇다') {
      if (_input.text.trim().isNotEmpty) {
        _interpret();
      } else if (_reply?.action != null) {
        _execute(confirmed: true);
      } else if (_reply?.question != null) {
        _interpret(confirmation: true);
      } else {
        setState(() => _status = '수어로 내용을 입력한 뒤 그렇다로 보내 주세요.');
      }
      return;
    }
    setState(() {
      if (_reply != null &&
          _reply!.question == null &&
          _reply!.action == null) {
        _history.clear();
        _originalRequestText = null;
        _reply = null;
      }
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
      _status = '단어를 모았습니다. 그렇다로 전송 · 아니다/틀리다로 취소';
    });
  }

  void _editGloss({bool clear = false}) {
    setState(() {
      final words = _input.text.trim().split(RegExp(r'\s+'));
      _input.text =
          clear || words.length <= 1 ? '' : (words..removeLast()).join(' ');
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      _inputType = 'gloss';
      if (_reply?.action != null) _reply = null;
    });
  }

  void _reset() {
    setState(() {
      _gate.reset(requireRelease: true);
      _history.clear();
      _originalRequestText = null;
      _reply = null;
      _input.clear();
      _inputType = 'text';
      _status = '';
    });
  }

  Future<void> _interpret({bool confirmation = false}) async {
    final text =
        (confirmation ? _originalRequestText ?? '' : _input.text).trim();
    if (_busy) return;
    if (confirmation && (_history.isEmpty || _reply?.question == null)) {
      setState(() => _status = '확인할 원래 요청이 없습니다. 내용을 다시 입력해 주세요.');
      return;
    }
    if (text.isEmpty) {
      setState(() => _status = '요청 또는 답변을 입력해 주세요.');
      return;
    }
    if (_history.length > 12) {
      setState(() => _status = '대화가 길어졌습니다. 아니다/틀리다로 새 요청을 시작해 주세요.');
      return;
    }
    final inputType = confirmation ? 'confirmation' : _inputType;
    final previousReply = _reply;
    setState(() {
      if (_history.isEmpty) _originalRequestText = text;
      _busy = true;
      _reply = null;
      _gate.reset(requireRelease: true);
      _addConversation(confirmation ? '나: 그렇다 · 직전 질문 확인' : '나: $text');
      _status = '요청을 해석하는 중…';
    });
    _notifyBusy(true);
    try {
      await _connection.save();
      final result = await (widget.request ?? requestAssistant)(
          baseUrl: _server.text,
          accessToken: _token.text,
          text: text,
          inputType: inputType,
          history: List<Map<String, String>>.from(_history));
      if (!mounted) return;
      setState(() {
        _reply = result;
        _gate.reset(requireRelease: true);
        _addConversation('LLM: ${result.translation}'
            '${result.question == null ? '' : '\n${result.question}'}');
        _history.add({
          'role': 'user',
          'content': confirmation
              ? '그렇다'
              : inputType == 'gloss'
                  ? '[수어 인식 라벨] $text'
                  : text
        });
        _history.add({
          'role': 'assistant',
          'content': '번역 후보: ${result.translation}'
              '${result.question == null ? '' : '\n추가 질문: ${result.question}'}'
        });
        _input.clear();
        // Keyboard answers remain text; each recognized word switches to gloss.
        _inputType = 'text';
        if (result.question != null) {
          _status = '수어로 답하고 그렇다로 보내 주세요. 아니다/틀리다는 요청 취소입니다.';
        } else {
          _status = result.action == null
              ? '번역 후보입니다. 실행할 기능은 없습니다.'
              : '실행 내용을 확인하고 손을 내린 뒤 그렇다로 승인해 주세요.';
        }
      });
    } catch (error) {
      if (mounted)
        setState(() {
          // A failed confirmation is retryable without replacing the original text.
          if (confirmation) _reply = previousReply;
          _status = '$error';
        });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _notifyBusy(false);
      }
    }
  }

  Future<void> _execute({bool confirmed = false}) async {
    final reply = _reply;
    final action = reply?.action;
    if (_busy || reply == null || action == null || !_foreground) return;
    setState(() => _busy = true);
    _notifyBusy(true);
    final approved = confirmed ||
        await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                        title: const Text('실행 내용 확인'),
                        content: SingleChildScrollView(
                            child: Text(
                                '${reply.translation}\n\n${action.summary}\n\n'
                                '${action.name == 'adjust_volume' ? '확인하면 미디어 볼륨을 한 단계 변경합니다.' : action.name == 'compose_message' ? '문자 앱에서 최종 전송합니다.' : action.arguments.containsKey('date') ? 'SignBridge 날짜 알림을 예약합니다.' : '시계 앱에서 실제 설정을 확인해 주세요.'}')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('확인하고 열기')),
                        ])) ==
            true;
    if (!mounted) return;
    if (!approved || !_foreground) {
      setState(() => _busy = false);
      _notifyBusy(false);
      return;
    }
    setState(() {
      _busy = true;
      // Consume this plan before opening another app; returning must not replay it.
      _reply = null;
      _history.clear();
      _originalRequestText = null;
      _input.clear();
      _gate.reset(requireRelease: true);
    });
    try {
      final message = await (widget.executeAction?.call(action) ??
          _actions.execute(action.name, jsonEncode(action.arguments)));
      if (mounted) {
        setState(() {
          _status = message;
          _addConversation('실행 결과: $message');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _notifyBusy(false);
      }
    }
  }

  void _example(String text) {
    _reset();
    setState(() => _input.text = text);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _inlineContent(context))
        : Scaffold(
            appBar: AppBar(title: const Text('LLM 비서')),
            body: SafeArea(
                child: Center(
                    child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: _content(context)),
            ))),
          );
  }

  List<Widget> _inlineContent(BuildContext context) {
    final remaining = _content(context);
    final leading = <Widget>[];
    // Keep the latest question/plan and current input beside the fixed camera.
    for (final name in [
      'assistant-status',
      'assistant-original-request',
      'assistant-reply',
      'assistant-input'
    ]) {
      final index = remaining.indexWhere((widget) => widget.key == Key(name));
      if (index >= 0) leading.add(remaining.removeAt(index));
    }
    return [...leading, ...remaining];
  }

  List<Widget> _content(BuildContext context) => [
        if (_originalRequestText != null)
          Text('원래 요청: $_originalRequestText',
              key: const Key('assistant-original-request'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        const Text('수어로 대화하기',
            key: Key('inline-conversation-title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Text('내용을 수어로 입력한 뒤 그렇다로 전송합니다. '
            'LLM 질문에도 수어로 답하고 그렇다로 보냅니다. '
            '아니다(현재 모델의 틀리다)는 요청을 취소합니다. '
            '단어와 확인 동작 사이에는 손을 0.8초 이상 내려 주세요.'),
        if (!widget.embedded)
          description('수어 인식 결과를 한국어 번역 후보로 정리하고 알람·문자 작성·볼륨 조절을 도와드립니다. '
              '의미가 다르거나 빠졌다면 수정해 주세요.'),
        const SizedBox(height: 12),
        if (_android && !widget.embedded)
          OutlinedButton(
              key: const Key('assistant-background-input'),
              onPressed: _busy ? null : _takeBackgroundInput,
              child: const Text('백그라운드 입력 가져오기')),
        if (!widget.embedded)
          TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _camera = false);
                      await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TranslationPage()));
                    },
              child: const Text('기존 입력 화면 · 회사 위치 등록')),
        if (!widget.embedded)
          ElevatedButton(
              key: const Key('assistant-alarm-wizard'),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _camera = false;
                        _gate.reset();
                      });
                      await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AlarmPage(developerMode: _developerMode)));
                    },
              child: const Text('알람 · 숫자로 시간·날짜 입력')),
        ExpansionTile(title: const Text('서버 연결 설정'), children: [
          TextField(
              key: const Key('assistant-server'),
              controller: _server,
              enabled: !_busy,
              onEditingComplete: _saveConnection,
              decoration: const InputDecoration(labelText: '백엔드 주소')),
          TextField(
              key: const Key('assistant-token'),
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              onEditingComplete: _saveConnection,
              decoration:
                  const InputDecoration(labelText: '서버 연결 토큰 (설정한 경우)')),
          const Text('NVIDIA API 키는 앱이 아니라 백엔드에 입력합니다.'),
          TextButton(
              key: const Key('assistant-save-connection'),
              onPressed: _busy ? null : _saveConnection,
              child: const Text('연결 설정 저장')),
        ]),
        gap,
        if (!widget.embedded)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('개발자 모드'),
              subtitle: const Text('단어 버튼으로 수어 인식 결과를 조합합니다'),
              value: _developerMode,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _developerMode = value;
                        _camera = false;
                        _gate.reset();
                      })),
        if (_developerMode) ...[
          GlossTestPanel(
              text: _inputType == 'gloss' ? _input.text.trim() : '',
              disabled: _busy || !_foreground,
              onWord: _appendGloss,
              onUndo: () => _editGloss(),
              onClear: () => _editGloss(clear: true)),
          const SizedBox(height: 12),
        ],
        if (_conversation.isNotEmpty)
          ExpansionTile(
              key: const Key('assistant-conversation'),
              title: const Text('이전 대화'),
              children: [
                Panel(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      for (final turn in _conversation)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(turn)),
                    ]))
              ]),
        if (!widget.embedded || _developerMode)
          Wrap(spacing: 8, children: [
            OutlinedButton(
                onPressed: _busy ? null : () => _example('오전 7시에 기상 알람 설정해줘'),
                child: const Text('알람 예시')),
            OutlinedButton(
                onPressed:
                    _busy ? null : () => _example('엄마에게 늦을 것 같다고 문자 작성해줘'),
                child: const Text('문자 예시')),
            TextButton(
                onPressed: _busy ? null : _reset, child: const Text('새 요청')),
          ]),
        if (!widget.embedded || _developerMode)
          DropdownButton<String>(
              value: _inputType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'text', child: Text('한국어 직접 입력')),
                DropdownMenuItem(value: 'gloss', child: Text('수어 인식 라벨 입력')),
              ],
              onChanged: _busy || _camera
                  ? null
                  : (value) => setState(() {
                        _inputType = value!;
                        if (_reply?.action != null) _reply = null;
                      })),
        TextField(
            key: const Key('assistant-input'),
            controller: _input,
            enabled: !_busy,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            onChanged: (_) => setState(() {
                  if (_reply?.action != null) _reply = null;
                }),
            decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '모은 수어 · 그렇다로 보내기',
                hintText: '인식된 수어가 여기에 모입니다.')),
        if (!widget.embedded)
          OutlinedButton.icon(
              icon: Icon(_camera ? Icons.stop : Icons.videocam),
              label: Text(_camera ? '촬영 종료' : '수어 입력 시작'),
              onPressed: _busy || _developerMode
                  ? null
                  : () => setState(() {
                        _camera = !_camera;
                        _gate.reset(requireRelease: _reply != null);
                        if (_camera) {
                          _inputType = 'gloss';
                        }
                      })),
        if (_camera && !widget.embedded) ...[
          const Text('배포된 모델에 포함된 단어만 인식합니다. 단어마다 손을 0.8초 이상 내려 주세요. '
              '현재 임시 목록은 두 종류의 위와 확인 수어를 포함한 13개 클래스입니다. 새 단어는 학습·모델 배포 후 사용할 수 있습니다.'),
          SizedBox(height: 300, child: HandCamera(onPrediction: _prediction)),
        ],
        const SizedBox(height: 12),
        if (!widget.embedded || _developerMode)
          ElevatedButton(
              key: const Key('assistant-submit'),
              onPressed: _busy ? null : _interpret,
              child: Text(_busy ? '처리 중…' : '입력 완료 · 해석하기')),
        if (_busy) const LinearProgressIndicator(),
        gap,
        if (_reply != null)
          Panel(
              key: const Key('assistant-reply'),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_reply!.mode == 'mock')
                      const Badge('모의 응답 · 실제 LLM 번역 아님', color: muted),
                    const Text('한국어 번역 후보',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_reply!.translation),
                    if (_reply!.question != null) ...[
                      gap,
                      Text(_reply!.question!,
                          style: const TextStyle(fontSize: 18, color: primary)),
                    ],
                    if (_reply!.action != null) ...[
                      gap,
                      Text(_reply!.action!.summary),
                      if (!widget.embedded || _developerMode)
                        ElevatedButton(
                            key: const Key('assistant-execute'),
                            onPressed: _busy ? null : () => _execute(),
                            child: const Text('확인 후 실행')),
                    ],
                    if (_reply!.action != null || _reply!.question != null) ...[
                      const Text('그렇다 = 전송/승인, 아니다 또는 틀리다 = 요청 폐기 후 재입력.'),
                      if (!widget.embedded || _developerMode)
                        TextButton(
                            onPressed: _busy ? null : () => _appendGloss('그렇다'),
                            child: const Text('그렇다')),
                      if (!widget.embedded || _developerMode)
                        TextButton(
                            onPressed: _busy ? null : () => _appendGloss('틀리다'),
                            child: const Text('틀리다')),
                    ],
                  ])),
        gap,
        Text(_status, key: const Key('assistant-status')),
        const SizedBox(height: 12),
        description('알람·문자 실행은 Android에서 지원합니다. '
            '날짜 알람은 앱 내부 알림으로 예약합니다. 병원 검색과 길 찾기 등 LLM 도구 확장은 별도 작업입니다.'),
      ];
}
