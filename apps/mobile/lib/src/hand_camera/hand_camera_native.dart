import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../sign_commands.dart';

class HandCamera extends StatefulWidget {
  const HandCamera({Key? key, this.onPrediction, this.compact = false})
      : super(key: key);
  final bool compact;
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
      return Column(children: [
        Expanded(
            child: AndroidView(
                viewType: 'signbridge/hand-camera',
                onPlatformViewCreated: (id) {
                  if (!mounted) return;
                  setState(() =>
                      _channel = MethodChannel('signbridge/predictions/$id'));
                  _channel!.setMethodCallHandler((call) async {
                    if (mounted && call.method == 'prediction') {
                      // Native owns background actions even if Flutter's lifecycle message is delayed.
                      if (call.arguments is Map &&
                          call.arguments['handledByService'] == true) return;
                      final prediction =
                          SignPrediction.fromMessage(call.arguments);
                      widget.onPrediction
                          ?.call(prediction ?? const SignPrediction('', 0));
                    }
                  });
                })),
        if (!widget.compact)
          TextButton.icon(
            icon: const Icon(Icons.switch_camera),
            label: const Text('카메라 전환'),
            onPressed: _channel == null
                ? null
                : () => _channel!.invokeMethod<void>('flipCamera'),
          ),
      ]);
    }
    return const Center(
        child: Text('손 인식 카메라는 Android 앱 또는 웹 브라우저에서 사용할 수 있습니다.',
            textAlign: TextAlign.center));
  }
}
