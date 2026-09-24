import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../sign_commands.dart';

class HandCamera extends StatefulWidget {
  const HandCamera({Key? key, this.onPrediction}) : super(key: key);
  final ValueChanged<SignPrediction>? onPrediction;
  @override
  State<HandCamera> createState() => _HandCameraState();
}

class _HandCameraState extends State<HandCamera> {
  MethodChannel? _channel;
  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
          viewType: 'signbridge/hand-camera',
          onPlatformViewCreated: (id) {
            _channel = MethodChannel('signbridge/predictions/$id');
            _channel!.setMethodCallHandler((call) async {
              if (mounted && call.method == 'prediction') {
                final prediction =
                    SignPrediction.fromDisplay(call.arguments as String);
                widget.onPrediction
                    ?.call(prediction ?? const SignPrediction('', 0));
              }
            });
          });
    }
    return const Center(
        child: Text('손 인식 카메라는 Android 앱 또는 웹 브라우저에서 사용할 수 있습니다.',
            textAlign: TextAlign.center));
  }
}
