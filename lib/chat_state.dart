import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CgContact {
  final String id;
  final String nickname;
  final DateTime lastSeenAt;
  final List<String> tunnelIds;

  const CgContact({
    required this.id,
    required this.nickname,
    required this.lastSeenAt,
    required this.tunnelIds,
  });

  CgContact touch({required String name, required String tunnelId}) {
    final ids = <String>{...tunnelIds, if (tunnelId.isNotEmpty) tunnelId}.toList();
    return CgContact(
      id: id,
      nickname: name.trim().isEmpty ? nickname : name.trim(),
      lastSeenAt: DateTime.now(),
      tunnelIds: ids,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nickname': nickname,
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'tunnelIds': tunnelIds,
      };

  factory CgContact.fromJson(Map<String, dynamic> json) => CgContact(
        id: json['id']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? 'user',
        lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? '') ??
            DateTime.now(),
        tunnelIds: ((json['tunnelIds'] as List?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(),
      );
}

class CgContactStore {
  static const String _key = 'chernogram_contacts_v1';

  static Future<List<CgContact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return <CgContact>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CgContact>[];
      return decoded
          .whereType<Map>()
          .map((item) => CgContact.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    } catch (_) {
      return <CgContact>[];
    }
  }

  static Future<void> save(List<CgContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(contacts.map((item) => item.toJson()).toList()),
    );
  }
}

class CgChatMeta {
  final Set<String> deletedMessageIds;
  final Map<String, Map<String, Set<String>>> reactions;

  const CgChatMeta({
    required this.deletedMessageIds,
    required this.reactions,
  });

  factory CgChatMeta.empty() => const CgChatMeta(
        deletedMessageIds: <String>{},
        reactions: <String, Map<String, Set<String>>>{},
      );

  CgChatMeta copy() => CgChatMeta(
        deletedMessageIds: <String>{...deletedMessageIds},
        reactions: <String, Map<String, Set<String>>>{
          for (final entry in reactions.entries)
            entry.key: <String, Set<String>>{
              for (final reaction in entry.value.entries)
                reaction.key: <String>{...reaction.value},
            },
        },
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deleted': deletedMessageIds.toList(),
        'reactions': <String, dynamic>{
          for (final entry in reactions.entries)
            entry.key: <String, dynamic>{
              for (final reaction in entry.value.entries)
                reaction.key: reaction.value.toList(),
            },
        },
      };

  factory CgChatMeta.fromJson(Map<String, dynamic> json) {
    final deleted = ((json['deleted'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toSet();
    final reactions = <String, Map<String, Set<String>>>{};
    final rawReactions = json['reactions'];
    if (rawReactions is Map) {
      for (final messageEntry in rawReactions.entries) {
        if (messageEntry.value is! Map) continue;
        final messageReactions = <String, Set<String>>{};
        for (final reactionEntry in (messageEntry.value as Map).entries) {
          final actors = ((reactionEntry.value as List?) ?? const <dynamic>[])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toSet();
          if (actors.isNotEmpty) {
            messageReactions[reactionEntry.key.toString()] = actors;
          }
        }
        if (messageReactions.isNotEmpty) {
          reactions[messageEntry.key.toString()] = messageReactions;
        }
      }
    }
    return CgChatMeta(deletedMessageIds: deleted, reactions: reactions);
  }

  void merge(CgChatMeta other) {
    deletedMessageIds.addAll(other.deletedMessageIds);
    for (final messageEntry in other.reactions.entries) {
      final local = reactions.putIfAbsent(
        messageEntry.key,
        () => <String, Set<String>>{},
      );
      for (final reactionEntry in messageEntry.value.entries) {
        local
            .putIfAbsent(reactionEntry.key, () => <String>{})
            .addAll(reactionEntry.value);
      }
    }
  }
}

class CgChatMetaStore {
  static String _key(String tunnelId) => 'chernogram_chat_meta_$tunnelId';

  static Future<CgChatMeta> load(String tunnelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(tunnelId));
    if (raw == null) return CgChatMeta.empty();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? CgChatMeta.fromJson(Map<String, dynamic>.from(decoded))
          : CgChatMeta.empty();
    } catch (_) {
      return CgChatMeta.empty();
    }
  }

  static Future<void> save(String tunnelId, CgChatMeta meta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(tunnelId), jsonEncode(meta.toJson()));
  }
}
