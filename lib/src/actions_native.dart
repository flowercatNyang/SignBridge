import 'package:flutter/services.dart';

class DeviceActions {
  static const channel = MethodChannel('signbridge/actions');
  Future<String> execute(String action, [String value = '']) async {
    try {
      return await channel.invokeMethod<String>(action, {'value': value}) ??
          '실행 결과가 없습니다.';
    } on MissingPluginException {
      throw Exception('이 기능은 Android 앱에서 지원합니다.');
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '기능을 실행하지 못했습니다.');
    }
  }

  Future<String> loadPhone() async {
    try {
      return await channel.invokeMethod<String>('loadPhone') ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<void> savePhone(String phone) =>
      channel.invokeMethod<void>('savePhone', {'value': phone});
}
