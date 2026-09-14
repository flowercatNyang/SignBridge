import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HandCamera extends StatelessWidget {
  const HandCamera({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidView(viewType: 'signbridge/hand-camera');
    }
    return const Center(
        child: Text('손 인식 카메라는 Android 앱 또는 웹 브라우저에서 사용할 수 있습니다.',
            textAlign: TextAlign.center));
  }
}
