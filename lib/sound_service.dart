import 'package:flutter/services.dart';

class ChernogramSound {
  static const MethodChannel _channel = MethodChannel('chernogram/sound');

  static Future<void> playMessage() async {
    try {
      await _channel.invokeMethod<void>('playMessage');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> startIncomingCall({required bool video}) async {
    try {
      await _channel.invokeMethod<void>(
        'startIncomingCall',
        <String, dynamic>{'video': video},
      );
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> stopIncomingCall() async {
    try {
      await _channel.invokeMethod<void>('stopIncomingCall');
    } catch (_) {}
  }
}
