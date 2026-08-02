import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity.dart';

class CgIds {
  static final Random _random = Random.secure();
  static const String _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  static String random([int length = 18]) => List<String>.generate(
    length,
    (_) => _alphabet[_random.nextInt(_alphabet.length)],
  ).join();
}

class CgProfile {
  final String id;
  final String nickname;
  final DateTime createdAt;
  final String? avatarBase64;

  const CgProfile({
    required this.id,
    required this.nickname,
    required this.createdAt,
    this.avatarBase64,
  });

  CgProfile copyWith({String? nickname, String? avatarBase64}) => CgProfile(
    id: id,
    nickname: nickname ?? this.nickname,
    createdAt: createdAt,
    avatarBase64: avatarBase64 ?? this.avatarBase64,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'createdAt': createdAt.toIso8601String(),
    if (avatarBase64 != null) 'avatarBase64': avatarBase64,
  };

  factory CgProfile.fromJson(Map<String, dynamic> json) => CgProfile(
    id: json['id']?.toString().trim().isNotEmpty == true
        ? json['id'].toString()
        : CgIds.random(12),
    nickname: json['nickname']?.toString().trim().isNotEmpty == true
        ? json['nickname'].toString()
        : 'user_${CgIds.random(4).toLowerCase()}',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    avatarBase64: json['avatarBase64']?.toString(),
  );
}

class CgContact {
  final String id;
  final String nickname;
  final DateTime lastSeenAt;
  final List<String> tunnelIds;
  final String? avatarBase64;

  const CgContact({
    required this.id,
    required this.nickname,
    required this.lastSeenAt,
    required this.tunnelIds,
    this.avatarBase64,
  });

  CgContact copyWith({
    String? nickname,
    DateTime? lastSeenAt,
    List<String>? tunnelIds,
    String? avatarBase64,
  }) => CgContact(
    id: id,
    nickname: nickname ?? this.nickname,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    tunnelIds: tunnelIds ?? this.tunnelIds,
    avatarBase64: avatarBase64 ?? this.avatarBase64,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'tunnelIds': tunnelIds,
    if (avatarBase64 != null) 'avatarBase64': avatarBase64,
  };

  factory CgContact.fromJson(Map<String, dynamic> json) => CgContact(
    id: json['id']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? 'user',
    lastSeenAt:
        DateTime.tryParse(json['lastSeenAt']?.toString() ?? '') ??
        DateTime.now(),
    tunnelIds: ((json['tunnelIds'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(),
    avatarBase64: json['avatarBase64']?.toString(),
  );
}

class CgAttachment {
  final String id;
  final String name;
  final int size;
  final String kind;
  final String? dataBase64;
  final String? localPath;

  const CgAttachment({
    required this.id,
    required this.name,
    required this.size,
    required this.kind,
    this.dataBase64,
    this.localPath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'kind': kind,
    if (dataBase64 != null) 'dataBase64': dataBase64,
    if (localPath != null) 'localPath': localPath,
  };

  factory CgAttachment.fromJson(Map<String, dynamic> json) => CgAttachment(
    id: json['id']?.toString() ?? CgIds.random(),
    name: json['name']?.toString() ?? 'file',
    size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
    kind: json['kind']?.toString() ?? 'file',
    dataBase64: json['dataBase64']?.toString(),
    localPath: json['localPath']?.toString() ?? json['path']?.toString(),
  );
}

class CgMessage {
  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime sentAt;
  final String type;
  final CgAttachment? attachment;
  final bool deleted;
  final Map<String, List<String>> reactions;
  final Map<String, dynamic> meta;

  const CgMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.sentAt,
    this.type = 'text',
    this.attachment,
    this.deleted = false,
    this.reactions = const <String, List<String>>{},
    this.meta = const <String, dynamic>{},
  });

  CgMessage copyWith({
    String? text,
    String? type,
    CgAttachment? attachment,
    bool? deleted,
    Map<String, List<String>>? reactions,
    Map<String, dynamic>? meta,
  }) => CgMessage(
    id: id,
    authorId: authorId,
    authorName: authorName,
    text: text ?? this.text,
    sentAt: sentAt,
    type: type ?? this.type,
    attachment: attachment ?? this.attachment,
    deleted: deleted ?? this.deleted,
    reactions: reactions ?? this.reactions,
    meta: meta ?? this.meta,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'authorName': authorName,
    'author': authorName,
    'text': text,
    'sentAt': sentAt.toIso8601String(),
    'type': type,
    'deleted': deleted,
    if (attachment != null) 'attachment': attachment!.toJson(),
    if (reactions.isNotEmpty) 'reactions': reactions,
    if (meta.isNotEmpty) 'meta': meta,
  };

  factory CgMessage.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'];
    final reactions = <String, List<String>>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        reactions[entry.key
            .toString()] = ((entry.value as List?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    }
    final rawMeta = json['meta'];
    return CgMessage(
      id: json['id']?.toString() ?? CgIds.random(),
      authorId: json['authorId']?.toString() ?? '',
      authorName:
          json['authorName']?.toString() ??
          json['author']?.toString() ??
          'user',
      text: json['text']?.toString() ?? '',
      sentAt:
          DateTime.tryParse(json['sentAt']?.toString() ?? '') ?? DateTime.now(),
      type: json['type']?.toString() ?? 'text',
      attachment: json['attachment'] is Map
          ? CgAttachment.fromJson(
              Map<String, dynamic>.from(json['attachment'] as Map),
            )
          : null,
      deleted: json['deleted'] == true,
      reactions: reactions,
      meta: rawMeta is Map
          ? Map<String, dynamic>.from(rawMeta)
          : const <String, dynamic>{},
    );
  }
}

class CgTunnel {
  final String id;
  final String name;
  final bool isPrivate;
  final String ownerId;
  final String secret;
  final DateTime createdAt;
  final String? avatarBase64;
  final List<CgMessage> messages;
  final int revision;

  const CgTunnel({
    required this.id,
    required this.name,
    required this.isPrivate,
    required this.ownerId,
    required this.secret,
    required this.createdAt,
    required this.messages,
    this.avatarBase64,
    this.revision = 0,
  });

  String get displayName => name.trim().isEmpty ? 'Без названия' : name.trim();

  CgTunnel copyWith({
    String? name,
    bool? isPrivate,
    String? secret,
    String? avatarBase64,
    List<CgMessage>? messages,
    int? revision,
  }) => CgTunnel(
    id: id,
    name: name ?? this.name,
    isPrivate: isPrivate ?? this.isPrivate,
    ownerId: ownerId,
    secret: secret ?? this.secret,
    createdAt: createdAt,
    avatarBase64: avatarBase64 ?? this.avatarBase64,
    messages: messages ?? this.messages,
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isPrivate': isPrivate,
    'isPublic': !isPrivate,
    'ownerId': ownerId,
    'secret': secret,
    'inviteSecret': secret,
    'createdAt': createdAt.toIso8601String(),
    'revision': revision,
    if (avatarBase64 != null) 'avatarBase64': avatarBase64,
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  String get inviteToken {
    final payload = jsonEncode({
      'v': 4,
      'id': id,
      'name': name,
      'private': isPrivate,
      'owner': ownerId,
      'secret': secret,
      'revision': revision,
    });
    return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  }

  static CgTunnel? fromInviteToken(String token) {
    try {
      var normalized = token.trim();
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final id = map['id']?.toString() ?? '';
      final secret = map['secret']?.toString() ?? '';
      if (id.isEmpty || secret.isEmpty) return null;
      return CgTunnel(
        id: id,
        name: map['name']?.toString() ?? '',
        isPrivate: map['private'] != false,
        ownerId: map['owner']?.toString() ?? '',
        secret: secret,
        revision: int.tryParse(map['revision']?.toString() ?? '') ?? 0,
        createdAt: DateTime.now(),
        messages: const [],
      );
    } catch (_) {
      return null;
    }
  }

  factory CgTunnel.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List?) ?? const [];
    return CgTunnel(
      id: json['id']?.toString() ?? CgIds.random(16),
      name: json['name']?.toString() ?? '',
      isPrivate: json.containsKey('isPrivate')
          ? json['isPrivate'] != false
          : json['isPublic'] != true,
      ownerId: json['ownerId']?.toString() ?? '',
      secret:
          json['secret']?.toString() ??
          json['inviteSecret']?.toString() ??
          CgIds.random(36),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      revision: int.tryParse(json['revision']?.toString() ?? '') ?? 0,
      avatarBase64: json['avatarBase64']?.toString(),
      messages: rawMessages
          .whereType<Map>()
          .map((item) => CgMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class CgStore {
  static const String profileKey = 'chernogram_profile_v1';
  static const String tunnelsKey = 'chernogram_tunnels_v1';
  static const String contactsKey = 'chernogram_contacts_v1';
  static const String darkModeKey = 'dark_mode';
  static const String privacyLensKey = 'privacy_lens';

  static Future<CgProfile> loadOrCreateProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(profileKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return CgProfile.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    final profile = CgProfile(
      id: await CgDeviceIdentity.stableProfileId(),
      nickname: 'user_${CgIds.random(5).toLowerCase()}',
      createdAt: DateTime.now(),
    );
    await saveProfile(profile);
    return profile;
  }

  static Future<void> saveProfile(CgProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profileKey, jsonEncode(profile.toJson()));
  }

  static Future<List<CgTunnel>> loadTunnels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(tunnelsKey);
    if (raw == null) return <CgTunnel>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CgTunnel>[];
      return decoded
          .whereType<Map>()
          .map((item) => CgTunnel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <CgTunnel>[];
    }
  }

  static Future<void> saveTunnels(List<CgTunnel> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      tunnelsKey,
      jsonEncode(tunnels.map((tunnel) => tunnel.toJson()).toList()),
    );
  }

  static Future<List<CgContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(contactsKey);
    if (raw == null) return <CgContact>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CgContact>[];
      return decoded
          .whereType<Map>()
          .map((item) => CgContact.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return <CgContact>[];
    }
  }

  static Future<void> saveContacts(List<CgContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      contactsKey,
      jsonEncode(contacts.map((contact) => contact.toJson()).toList()),
    );
  }

  static Future<bool> loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(darkModeKey) ?? true;
  }

  static Future<void> saveDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(darkModeKey, value);
  }

  static Future<bool> loadPrivacyLens() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(privacyLensKey) ?? false;
  }

  static Future<void> savePrivacyLens(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(privacyLensKey, value);
  }
}
