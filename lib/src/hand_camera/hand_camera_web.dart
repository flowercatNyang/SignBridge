// This implementation is selected only on web by a conditional export.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class HandCamera extends StatefulWidget {
  const HandCamera({Key? key}) : super(key: key);
  @override
  State<HandCamera> createState() => _HandCameraState();
}

class _HandCameraState extends State<HandCamera> {
  static int _nextId = 0;
  late final String _viewType;
  late final html.IFrameElement _frame;
  @override
  void initState() {
    super.initState();
    _viewType = 'signbridge-hand-camera-${_nextId++}';
    _frame = html.IFrameElement()
      ..src = Uri.base.resolve('hand_camera.html').toString()
      ..allow = 'camera'
      ..title = '실시간 손 인식 카메라'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%';
    // Flutter 2.8 exposes the web platform view registry through dart:ui.
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int id) => _frame);
  }

  @override
  void dispose() {
    _frame.contentWindow?.postMessage('dispose', Uri.base.origin);
    _frame.src = 'about:blank';
    _frame.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
