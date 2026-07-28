import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => <String, dynamic>{
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

  Map<String, dynamic> toJson() => <String, dynamic>{
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
    tunnelIds: ((json['tunnelIds'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(),
    avatarBase64: json['avatarBase64']?.toString(),
  );
}

class CgPermissions {
  final bool canWriteMessages;
  final bool canSendMedia;
  final bool canDownload;
  final bool canInvite;
  final bool canSeeHistory;
  final bool canCall;

  const CgPermissions({
    this.canWriteMessages = true,
    this.canSendMedia = true,
    this.canDownload = true,
    this.canInvite = false,
    this.canSeeHistory = true,
    this.canCall = true,
  });

  CgPermissions copyWith({
    bool? canWriteMessages,
    bool? canSendMedia,
    bool? canDownload,
    bool? canInvite,
    bool? canSeeHistory,
    bool? canCall,
  }) => CgPermissions(
    canWriteMessages: canWriteMessages ?? this.canWriteMessages,
    canSendMedia: canSendMedia ?? this.canSendMedia,
    canDownload: canDownload ?? this.canDownload,
    canInvite: canInvite ?? this.canInvite,
    canSeeHistory: canSeeHistory ?? this.canSeeHistory,
    canCall: canCall ?? this.canCall,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'canWriteMessages': canWriteMessages,
    'canSendMedia': canSendMedia,
    'canDownload': canDownload,
    'canInvite': canInvite,
    'canSeeHistory': canSeeHistory,
    'canCall': canCall,
  };

  factory CgPermissions.fromJson(Map<String, dynamic> json) => CgPermissions(
    canWriteMessages: json['canWriteMessages'] != false,
    canSendMedia: json['canSendMedia'] != false,
    canDownload: json['canDownload'] != false,
    canInvite: json['canInvite'] == true,
    canSeeHistory: json['canSeeHistory'] != false,
    canCall: json['canCall'] != false,
  );
}

class CgSharedFileInfo {
  final String id;
  final String name;
  final int size;
  final String kind;

  const CgSharedFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.kind,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'size': size,
    'kind': kind,
  };

  factory CgSharedFileInfo.fromJson(Map<String, dynamic> json) =>
      CgSharedFileInfo(
        id: json['id']?.toString() ?? CgIds.random(18),
        name: json['name']?.toString() ?? 'file',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        kind: json['kind']?.toString() ?? 'file',
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

  CgAttachment copyWith({
    String? dataBase64,
    String? localPath,
    bool clearData = false,
    bool clearLocalPath = false,
  }) => CgAttachment(
    id: id,
    name: name,
    size: size,
    kind: kind,
    dataBase64: clearData ? null : (dataBase64 ?? this.dataBase64),
    localPath: clearLocalPath ? null : (localPath ?? this.localPath),
  );

  Map<String, dynamic> toJson({
    bool includeData = true,
    bool includeLocalPath = true,
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'size': size,
    'kind': kind,
    if (includeData && dataBase64 != null) 'dataBase64': dataBase64,
    if (includeLocalPath && localPath != null) 'localPath': localPath,
  };

  Map<String, dynamic> metadataJson() =>
      toJson(includeData: false, includeLocalPath: false);

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
    bool clearAttachment = false,
  }) => CgMessage(
    id: id,
    authorId: authorId,
    authorName: authorName,
    text: text ?? this.text,
    sentAt: sentAt,
    type: type ?? this.type,
    attachment: clearAttachment ? null : (attachment ?? this.attachment),
    deleted: deleted ?? this.deleted,
    reactions: reactions ?? this.reactions,
    meta: meta ?? this.meta,
  );

  Map<String, dynamic> toJson({
    bool includeAttachmentData = true,
    bool includeLocalPaths = true,
  }) => <String, dynamic>{
    'id': id,
    'authorId': authorId,
    'authorName': authorName,
    'author': authorName,
    'text': text,
    'sentAt': sentAt.toIso8601String(),
    'type': type,
    'deleted': deleted,
    if (attachment != null)
      'attachment': attachment!.toJson(
        includeData: includeAttachmentData,
        includeLocalPath: includeLocalPaths,
      ),
    if (reactions.isNotEmpty) 'reactions': reactions,
    if (meta.isNotEmpty) 'meta': meta,
  };

  Map<String, dynamic> metadataJson() =>
      toJson(includeAttachmentData: false, includeLocalPaths: false);

  bool sameVisibleContent(CgMessage other) {
    return id == other.id &&
        text == other.text &&
        type == other.type &&
        deleted == other.deleted &&
        attachment?.id == other.attachment?.id &&
        attachment?.localPath == other.attachment?.localPath &&
        reactions.toString() == other.reactions.toString() &&
        meta.toString() == other.meta.toString();
  }

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
          'пользователь',
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
  final CgPermissions permissions;
  final List<CgSharedFileInfo> sharedFiles;

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
    this.permissions = const CgPermissions(),
    this.sharedFiles = const <CgSharedFileInfo>[],
  });

  String get displayName => name.trim().isEmpty ? 'Без названия' : name.trim();

  CgTunnel copyWith({
    String? name,
    bool? isPrivate,
    String? secret,
    String? avatarBase64,
    List<CgMessage>? messages,
    int? revision,
    CgPermissions? permissions,
    List<CgSharedFileInfo>? sharedFiles,
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
    permissions: permissions ?? this.permissions,
    sharedFiles: sharedFiles ?? this.sharedFiles,
  );

  Map<String, dynamic> toJson({bool includeAttachmentData = false}) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'isPrivate': isPrivate,
        'isPublic': !isPrivate,
        'ownerId': ownerId,
        'secret': secret,
        'inviteSecret': secret,
        'createdAt': createdAt.toIso8601String(),
        'revision': revision,
        'permissions': permissions.toJson(),
        'sharedFiles': sharedFiles.map((item) => item.toJson()).toList(),
        if (avatarBase64 != null) 'avatarBase64': avatarBase64,
        'messages': messages
            .map(
              (message) => message.toJson(
                includeAttachmentData: includeAttachmentData,
                includeLocalPaths: true,
              ),
            )
            .toList(),
      };

  List<Map<String, dynamic>> historyJson({int limit = 120}) {
    final start = messages.length > limit ? messages.length - limit : 0;
    return messages
        .skip(start)
        .map((message) => message.metadataJson())
        .toList(growable: false);
  }

  String get inviteToken {
    final payload = jsonEncode(<String, dynamic>{
      'v': 5,
      'id': id,
      'name': name,
      'private': isPrivate,
      'owner': ownerId,
      'secret': secret,
      'revision': revision,
      'permissions': permissions.toJson(),
      'sharedFiles': sharedFiles.map((item) => item.toJson()).toList(),
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
      final rawPermissions = map['permissions'];
      final rawShared = (map['sharedFiles'] as List?) ?? const <dynamic>[];
      return CgTunnel(
        id: id,
        name: map['name']?.toString() ?? '',
        isPrivate: map['private'] != false,
        ownerId: map['owner']?.toString() ?? '',
        secret: secret,
        revision: int.tryParse(map['revision']?.toString() ?? '') ?? 0,
        createdAt: DateTime.now(),
        permissions: rawPermissions is Map
            ? CgPermissions.fromJson(Map<String, dynamic>.from(rawPermissions))
            : const CgPermissions(),
        sharedFiles: rawShared
            .whereType<Map>()
            .map(
              (item) =>
                  CgSharedFileInfo.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
        messages: const <CgMessage>[],
      );
    } catch (_) {
      return null;
    }
  }

  factory CgTunnel.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List?) ?? const <dynamic>[];
    final rawPermissions = json['permissions'];
    final rawShared = (json['sharedFiles'] as List?) ?? const <dynamic>[];
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
      permissions: rawPermissions is Map
          ? CgPermissions.fromJson(Map<String, dynamic>.from(rawPermissions))
          : const CgPermissions(),
      sharedFiles: rawShared
          .whereType<Map>()
          .map(
            (item) =>
                CgSharedFileInfo.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
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
      id: CgIds.random(12),
      nickname: 'user_${CgIds.random(4).toLowerCase()}',
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
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => CgTunnel.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}
    return <CgTunnel>[];
  }

  static Future<void> saveTunnels(List<CgTunnel> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      tunnelsKey,
      jsonEncode(tunnels.map((item) => item.toJson()).toList()),
    );
  }

  static Future<List<CgContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(contactsKey);
    if (raw == null) return <CgContact>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => CgContact.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}
    return <CgContact>[];
  }

  static Future<void> saveContacts(List<CgContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      contactsKey,
      jsonEncode(contacts.map((item) => item.toJson()).toList()),
    );
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
