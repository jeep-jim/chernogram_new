import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class ChernogramSound {
  static const MethodChannel _channel = MethodChannel('chernogram/sound');
  static AudioPlayer? _incomingPlayer;

  static Future<void> playMessage() async {
    try {
      await _channel.invokeMethod<void>('playMessage');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> startIncomingCall({required bool video}) async {
    await stopIncomingCall();
    var customStarted = false;
    try {
      final player = AudioPlayer();
      _incomingPlayer = player;
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1.0);
      await player.setAsset('assets/audio/chernogram_incoming.mp3');
      unawaited(player.play());
      customStarted = true;
    } catch (_) {
      await _incomingPlayer?.dispose();
      _incomingPlayer = null;
    }
    try {
      await _channel.invokeMethod<void>('startIncomingCall', <String, dynamic>{
        'video': video,
        'customSound': customStarted,
      });
    } catch (_) {
      if (!customStarted) await SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> stopIncomingCall() async {
    final player = _incomingPlayer;
    _incomingPlayer = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      await player.dispose();
    }
    try {
      await _channel.invokeMethod<void>('stopIncomingCall');
    } catch (_) {}
  }
}
