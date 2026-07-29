import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';

class CgRealtimeGatewayConfig {
  static const String _enabledKey = 'cg_gateway_enabled_v1';
  static const String _urlKey = 'cg_gateway_url_v1';
  static const String _deviceIdKey = 'cg_gateway_device_id_v1';

  static const bool compileEnabled =
      bool.fromEnvironment('CG_GATEWAY_ENABLED', defaultValue: false);
  static const String compileUrl =
      String.fromEnvironment('CG_GATEWAY_URL', defaultValue: '');

  final bool enabled;
  final Uri? uri;
  final String deviceId;

  const CgRealtimeGatewayConfig({
    required this.enabled,
    required this.uri,
    required this.deviceId,
  });

  static Future<CgRealtimeGatewayConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey)?.trim() ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'device_${CgIds.random(20)}';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    final runtimeUrl = prefs.getString(_urlKey)?.trim() ?? '';
    final selectedUrl = runtimeUrl.isNotEmpty ? runtimeUrl : compileUrl;
    final uri = Uri.tryParse(selectedUrl);
    final validUri = uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'wss' || uri.scheme == 'ws');
    return CgRealtimeGatewayConfig(
      enabled: (prefs.getBool(_enabledKey) ?? compileEnabled) && validUri,
      uri: validUri ? uri : null,
      deviceId: deviceId,
    );
  }

  static Future<void> saveEndpoint({
    required bool enabled,
    required String url,
  }) async {
    final value = url.trim();
    final uri = Uri.tryParse(value);
    if (enabled &&
        (uri == null ||
            !uri.hasAuthority ||
            (uri.scheme != 'wss' && uri.scheme != 'ws'))) {
      throw FormatException('Realtime gateway URL must use wss:// or ws://');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setString(_urlKey, value);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
  }
}
