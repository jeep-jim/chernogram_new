import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

/// Возвращает стабильный идентификатор установки, не раскрывая исходный
/// системный идентификатор в интерфейсе или сетевом обмене.
class CgDeviceIdentity {
  static const MethodChannel _channel = MethodChannel('chernogram/device');
  static const String _salt = 'chernogram-device-profile-v1';

  static Future<String> rawBinding() async {
    if (Platform.isAndroid) {
      try {
        final value = await _channel.invokeMethod<String>('getBindingId');
        if (value != null && value.trim().isNotEmpty) return value.trim();
      } catch (_) {}
    }
    if (Platform.isWindows) {
      final computer = Platform.environment['COMPUTERNAME'] ?? Platform.localHostname;
      final user = Platform.environment['USERNAME'] ?? '';
      return 'windows|$computer|$user';
    }
    return '${Platform.operatingSystem}|${Platform.localHostname}';
  }

  static Future<List<int>> _digest() async {
    final raw = await rawBinding();
    final hash = await Sha256().hash(utf8.encode('$_salt|$raw'));
    return hash.bytes;
  }

  static Future<String> stableProfileId() async {
    final bytes = await _digest();
    return 'cg_${base64UrlEncode(bytes.take(10).toList()).replaceAll('=', '')}';
  }

  static Future<String> fingerprint() async {
    final bytes = await _digest();
    final hex = bytes.take(8).map((item) => item.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'.toUpperCase();
  }
}
