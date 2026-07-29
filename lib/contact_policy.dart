import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CgContactPolicy {
  final bool allowMessages;
  final bool allowCalls;
  final bool allowVideoCalls;
  final bool allowFiles;
  final bool allowDownloads;
  final bool allowForwarding;
  final bool muted;
  final bool blocked;

  const CgContactPolicy({
    this.allowMessages = true,
    this.allowCalls = true,
    this.allowVideoCalls = true,
    this.allowFiles = true,
    this.allowDownloads = true,
    this.allowForwarding = true,
    this.muted = false,
    this.blocked = false,
  });

  CgContactPolicy copyWith({
    bool? allowMessages,
    bool? allowCalls,
    bool? allowVideoCalls,
    bool? allowFiles,
    bool? allowDownloads,
    bool? allowForwarding,
    bool? muted,
    bool? blocked,
  }) {
    return CgContactPolicy(
      allowMessages: allowMessages ?? this.allowMessages,
      allowCalls: allowCalls ?? this.allowCalls,
      allowVideoCalls: allowVideoCalls ?? this.allowVideoCalls,
      allowFiles: allowFiles ?? this.allowFiles,
      allowDownloads: allowDownloads ?? this.allowDownloads,
      allowForwarding: allowForwarding ?? this.allowForwarding,
      muted: muted ?? this.muted,
      blocked: blocked ?? this.blocked,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'allowMessages': allowMessages,
        'allowCalls': allowCalls,
        'allowVideoCalls': allowVideoCalls,
        'allowFiles': allowFiles,
        'allowDownloads': allowDownloads,
        'allowForwarding': allowForwarding,
        'muted': muted,
        'blocked': blocked,
      };

  factory CgContactPolicy.fromJson(Map<String, dynamic> json) =>
      CgContactPolicy(
        allowMessages: json['allowMessages'] != false,
        allowCalls: json['allowCalls'] != false,
        allowVideoCalls: json['allowVideoCalls'] != false,
        allowFiles: json['allowFiles'] != false,
        allowDownloads: json['allowDownloads'] != false,
        allowForwarding: json['allowForwarding'] != false,
        muted: json['muted'] == true,
        blocked: json['blocked'] == true,
      );
}

class CgContactPolicyStore {
  static const String _key = 'cg_contact_policies_v1';
  static Map<String, CgContactPolicy>? _cache;

  static Future<Map<String, CgContactPolicy>> _loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final result = <String, CgContactPolicy>{};
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is! Map) continue;
            result[entry.key.toString()] = CgContactPolicy.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      } catch (_) {
        // Corrupted preferences fall back to safe defaults.
      }
    }
    _cache = result;
    return result;
  }

  static Future<CgContactPolicy> load(String contactId) async {
    if (contactId.isEmpty) return const CgContactPolicy();
    final policies = await _loadAll();
    return policies[contactId] ?? const CgContactPolicy();
  }

  static Future<void> save(String contactId, CgContactPolicy policy) async {
    if (contactId.isEmpty) return;
    final policies = await _loadAll();
    policies[contactId] = policy;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(<String, dynamic>{
        for (final entry in policies.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  static Future<void> remove(String contactId) async {
    final policies = await _loadAll();
    if (policies.remove(contactId) == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(<String, dynamic>{
        for (final entry in policies.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
