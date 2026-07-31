import 'dart:convert';

import 'package:http/http.dart' as http;

import 'realtime_gateway_config.dart';

class CgIceConfig {
  static const List<Map<String, dynamic>> _fallback = <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': <String>[
        'stun:stun.cloudflare.com:3478',
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
    <String, dynamic>{
      'urls': <String>[
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:80?transport=tcp',
        'turns:openrelay.metered.ca:443?transport=tcp',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  static List<Map<String, dynamic>>? _cached;
  static DateTime? _cachedAt;

  static Future<List<Map<String, dynamic>>> load() async {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 20)) {
      return cached;
    }
    try {
      final config = await CgRealtimeGatewayConfig.load();
      final gateway = config.uri;
      if (!config.enabled || gateway == null) return _fallback;
      final endpoint = gateway.replace(
        scheme: gateway.scheme == 'wss' ? 'https' : 'http',
        path: '/v1/ice',
        query: '',
      );
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallback;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['iceServers'] is! List) return _fallback;
      final servers = (decoded['iceServers'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['urls'] != null)
          .toList(growable: false);
      if (servers.isEmpty) return _fallback;
      _cached = servers;
      _cachedAt = DateTime.now();
      return servers;
    } catch (_) {
      return _fallback;
    }
  }
}
