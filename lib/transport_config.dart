import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CgFirebaseConfig {
  final bool enabled;
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  const CgFirebaseConfig({
    required this.enabled,
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });

  bool get complete =>
      enabled &&
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'apiKey': apiKey,
    'appId': appId,
    'messagingSenderId': messagingSenderId,
    'projectId': projectId,
  };

  factory CgFirebaseConfig.fromJson(Map<String, dynamic> json) =>
      CgFirebaseConfig(
        enabled: json['enabled'] == true,
        apiKey: json['apiKey']?.toString().trim() ?? '',
        appId: json['appId']?.toString().trim() ?? '',
        messagingSenderId:
            json['messagingSenderId']?.toString().trim() ?? '',
        projectId: json['projectId']?.toString().trim() ?? '',
      );

  static const disabled = CgFirebaseConfig(
    enabled: false,
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
  );
}

class CgTransportConfig {
  static const String _cacheKey = 'cg_transport_config_v1';
  static const List<String> _urls = <String>[
    'https://raw.githubusercontent.com/jeep-jim/chernogram_new/main/transport.json',
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/transport.json',
    'https://cdn.jsdelivr.net/gh/jeep-jim/chernogram_new@main/transport.json',
  ];

  static CgTransportConfig? _memory;
  static DateTime? _loadedAt;

  final int version;
  final bool impulseEnabled;
  final String impulseBaseUrl;
  final bool fallbackRelayEnabled;
  final CgFirebaseConfig firebase;
  final DateTime? updatedAt;

  const CgTransportConfig({
    required this.version,
    required this.impulseEnabled,
    required this.impulseBaseUrl,
    required this.fallbackRelayEnabled,
    required this.firebase,
    this.updatedAt,
  });

  bool get hasImpulse =>
      impulseEnabled &&
      impulseBaseUrl.startsWith('https://') &&
      Uri.tryParse(impulseBaseUrl)?.host.isNotEmpty == true;

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(impulseBaseUrl);
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}$cleanPath',
      queryParameters: query,
    );
  }

  Uri websocketUri(String path, [Map<String, String>? query]) {
    final value = uri(path, query);
    return value.replace(scheme: value.scheme == 'https' ? 'wss' : 'ws');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'impulseEnabled': impulseEnabled,
    'impulseBaseUrl': impulseBaseUrl,
    'fallbackRelayEnabled': fallbackRelayEnabled,
    'firebase': firebase.toJson(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  factory CgTransportConfig.fromJson(Map<String, dynamic> json) {
    final rawFirebase = json['firebase'];
    return CgTransportConfig(
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      impulseEnabled: json['impulseEnabled'] == true,
      impulseBaseUrl: json['impulseBaseUrl']?.toString().trim() ?? '',
      fallbackRelayEnabled: json['fallbackRelayEnabled'] != false,
      firebase: rawFirebase is Map
          ? CgFirebaseConfig.fromJson(
              Map<String, dynamic>.from(rawFirebase),
            )
          : CgFirebaseConfig.disabled,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  static const fallback = CgTransportConfig(
    version: 1,
    impulseEnabled: false,
    impulseBaseUrl: '',
    fallbackRelayEnabled: true,
    firebase: CgFirebaseConfig.disabled,
  );

  static Future<CgTransportConfig> load({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _memory != null &&
        _loadedAt != null &&
        now.difference(_loadedAt!) < const Duration(minutes: 5)) {
      return _memory!;
    }

    final cached = await loadCached();
    if (!force && cached.hasImpulse) {
      _memory = cached;
    }

    Object? lastError;
    for (final source in _urls) {
      try {
        final separator = source.contains('?') ? '&' : '?';
        final response = await http
            .get(
              Uri.parse(
                '$source${separator}t=${DateTime.now().millisecondsSinceEpoch}',
              ),
              headers: const <String, String>{
                'Accept': 'application/json',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
              },
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw StateError('transport config ${response.statusCode}');
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) throw const FormatException('transport config');
        final config = CgTransportConfig.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        await _save(config);
        _memory = config;
        _loadedAt = now;
        return config;
      } catch (error) {
        lastError = error;
      }
    }

    _memory = cached;
    _loadedAt = now;
    if (cached != fallback) return cached;
    if (lastError != null) {
      return fallback;
    }
    return cached;
  }

  static Future<CgTransportConfig> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return fallback;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return fallback;
      return CgTransportConfig.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> _save(CgTransportConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(config.toJson()));
    } catch (_) {}
  }
}
