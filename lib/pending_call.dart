import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CgPendingCall {
  final String callId;
  final String tunnelId;
  final String fromId;
  final String fromName;
  final String? avatarBase64;
  final bool video;
  final bool group;
  final DateTime createdAt;

  const CgPendingCall({
    required this.callId,
    required this.tunnelId,
    required this.fromId,
    required this.fromName,
    required this.video,
    required this.group,
    required this.createdAt,
    this.avatarBase64,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'callId': callId,
        'tunnelId': tunnelId,
        'fromId': fromId,
        'fromName': fromName,
        'video': video,
        'group': group,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (avatarBase64 != null) 'avatarBase64': avatarBase64,
      };

  factory CgPendingCall.fromJson(Map<String, dynamic> json) => CgPendingCall(
        callId: json['callId']?.toString() ?? '',
        tunnelId: json['tunnelId']?.toString() ?? '',
        fromId: json['fromId']?.toString() ?? '',
        fromName: json['fromName']?.toString() ?? 'user',
        avatarBase64: json['avatarBase64']?.toString(),
        video: json['video'] == true,
        group: json['group'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
      );
}

class CgPendingCallStore {
  static const String _key = 'cg_pending_calls_v1';

  static Future<Map<String, CgPendingCall>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, CgPendingCall>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, CgPendingCall>{};
      final now = DateTime.now().toUtc();
      final result = <String, CgPendingCall>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final call = CgPendingCall.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (call.callId.isEmpty ||
            now.difference(call.createdAt.toUtc()).abs() >
                const Duration(minutes: 3)) {
          continue;
        }
        result[entry.key.toString()] = call;
      }
      return result;
    } catch (_) {
      return <String, CgPendingCall>{};
    }
  }

  static Future<void> _saveAll(Map<String, CgPendingCall> calls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(<String, dynamic>{
        for (final entry in calls.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  static Future<void> save(CgPendingCall call) async {
    if (call.callId.isEmpty) return;
    final calls = await _loadAll();
    calls[call.callId] = call;
    await _saveAll(calls);
  }

  static Future<CgPendingCall?> take(String callId) async {
    if (callId.isEmpty) return null;
    final calls = await _loadAll();
    final call = calls.remove(callId);
    await _saveAll(calls);
    return call;
  }

  static Future<void> remove(String callId) async {
    final calls = await _loadAll();
    if (calls.remove(callId) != null) await _saveAll(calls);
  }
}
