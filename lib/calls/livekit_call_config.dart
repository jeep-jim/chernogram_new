import 'package:shared_preferences/shared_preferences.dart';

import '../core_models.dart';

class CgLiveKitCallConfig {
  static const String _enabledKey = 'cg_livekit_calls_enabled_v1';
  static const String _brokerUrlKey = 'cg_livekit_calls_broker_url_v1';
  static const String _deviceIdKey = 'cg_livekit_calls_device_id_v1';

  static const bool compileEnabled =
      bool.fromEnvironment('CG_LIVEKIT_CALLS_ENABLED', defaultValue: false);
  static const String compileBrokerUrl =
      String.fromEnvironment('CG_LIVEKIT_CALLS_BROKER_URL', defaultValue: '');

  final bool enabled;
  final Uri? brokerUri;
  final String deviceId;

  const CgLiveKitCallConfig({
    required this.enabled,
    required this.brokerUri,
    required this.deviceId,
  });

  static Future<CgLiveKitCallConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey)?.trim() ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'device_${CgIds.random(20)}';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    final runtimeUrl = prefs.getString(_brokerUrlKey)?.trim() ?? '';
    final selectedUrl = runtimeUrl.isNotEmpty ? runtimeUrl : compileBrokerUrl;
    final uri = Uri.tryParse(selectedUrl);
    final valid = uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'https' || uri.scheme == 'http');
    return CgLiveKitCallConfig(
      enabled: (prefs.getBool(_enabledKey) ?? compileEnabled) && valid,
      brokerUri: valid ? uri : null,
      deviceId: deviceId,
    );
  }

  static Future<void> save({
    required bool enabled,
    required String brokerUrl,
  }) async {
    final value = brokerUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (enabled &&
        (uri == null ||
            !uri.hasAuthority ||
            (uri.scheme != 'https' && uri.scheme != 'http'))) {
      throw const FormatException('Calls broker URL must use https:// or http://');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setString(_brokerUrlKey, value);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
  }
}
