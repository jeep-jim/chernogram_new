import 'dart:convert';
import 'dart:math';

String libraryRandomId([int bytes = 12]) {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(bytes, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

abstract final class LibraryKinds {
  static const String audio = 'audio';
  static const String video = 'video';
  static const String image = 'image';
  static const String document = 'document';
  static const String archive = 'archive';
  static const String voice = 'voice';
  static const String circle = 'circle';
  static const String link = 'link';
  static const String other = 'other';

  static const List<String> all = <String>[
    audio,
    video,
    image,
    document,
    archive,
    voice,
    circle,
    link,
    other,
  ];

  static String detect(String fileName, {String? hint}) {
    final normalizedHint = hint?.toLowerCase().trim();
    if (normalizedHint == voice || normalizedHint == circle) {
      return normalizedHint!;
    }
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (<String>{'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'}.contains(extension)) {
      return audio;
    }
    if (<String>{'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'}.contains(extension)) {
      return video;
    }
    if (<String>{'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'}.contains(extension)) {
      return image;
    }
    if (<String>{'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'}.contains(extension)) {
      return archive;
    }
    if (<String>{
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'csv',
      'json',
      'xml',
      'epub',
    }.contains(extension)) {
      return document;
    }
    return other;
  }
}

abstract final class LibraryAccess {
  static const String private = 'private';
  static const String room = 'room';
  static const String link = 'link';
  static const String public = 'public';
  static const String oneTime = 'oneTime';
  static const String deviceOnly = 'deviceOnly';

  static const List<String> all = <String>[
    private,
    room,
    link,
    public,
    oneTime,
    deviceOnly,
  ];
}

class LibraryItem {
  final String id;
  final String name;
  final String kind;
  final String access;
  final String? localPath;
  final String? remoteUrl;
  final String? roomId;
  final String? messageId;
  final String ownerId;
  final String ownerName;
  final String sourceDeviceId;
  final int size;
  final int? durationMs;
  final String? artist;
  final String? album;
  final String? description;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool available;
  final bool downloaded;

  const LibraryItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.access,
    required this.ownerId,
    required this.ownerName,
    required this.sourceDeviceId,
    required this.size,
    required this.createdAt,
    required this.updatedAt,
    this.localPath,
    this.remoteUrl,
    this.roomId,
    this.messageId,
    this.durationMs,
    this.artist,
    this.album,
    this.description,
    this.tags = const <String>[],
    this.available = true,
    this.downloaded = true,
  });

  LibraryItem copyWith({
    String? name,
    String? kind,
    String? access,
    String? localPath,
    String? remoteUrl,
    String? roomId,
    String? messageId,
    String? ownerId,
    String? ownerName,
    String? sourceDeviceId,
    int? size,
    int? durationMs,
    String? artist,
    String? album,
    String? description,
    List<String>? tags,
    DateTime? updatedAt,
    bool? available,
    bool? downloaded,
  }) => LibraryItem(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    access: access ?? this.access,
    localPath: localPath ?? this.localPath,
    remoteUrl: remoteUrl ?? this.remoteUrl,
    roomId: roomId ?? this.roomId,
    messageId: messageId ?? this.messageId,
    ownerId: ownerId ?? this.ownerId,
    ownerName: ownerName ?? this.ownerName,
    sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
    size: size ?? this.size,
    durationMs: durationMs ?? this.durationMs,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    available: available ?? this.available,
    downloaded: downloaded ?? this.downloaded,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'kind': kind,
    'access': access,
    'localPath': localPath,
    'remoteUrl': remoteUrl,
    'roomId': roomId,
    'messageId': messageId,
    'ownerId': ownerId,
    'ownerName': ownerName,
    'sourceDeviceId': sourceDeviceId,
    'size': size,
    'durationMs': durationMs,
    'artist': artist,
    'album': album,
    'description': description,
    'tags': tags,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'available': available,
    'downloaded': downloaded,
  };

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
    id: json['id']?.toString() ?? libraryRandomId(),
    name: json['name']?.toString() ?? 'Файл',
    kind: json['kind']?.toString() ?? LibraryKinds.other,
    access: json['access']?.toString() ?? LibraryAccess.private,
    localPath: json['localPath']?.toString(),
    remoteUrl: json['remoteUrl']?.toString(),
    roomId: json['roomId']?.toString(),
    messageId: json['messageId']?.toString(),
    ownerId: json['ownerId']?.toString() ?? '',
    ownerName: json['ownerName']?.toString() ?? 'Устройство',
    sourceDeviceId: json['sourceDeviceId']?.toString() ?? '',
    size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
    durationMs: int.tryParse(json['durationMs']?.toString() ?? ''),
    artist: json['artist']?.toString(),
    album: json['album']?.toString(),
    description: json['description']?.toString(),
    tags: ((json['tags'] as List?) ?? const <dynamic>[])
        .map((value) => value.toString())
        .toList(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    available: json['available'] != false,
    downloaded: json['downloaded'] != false,
  );
}

class LibraryIndex {
  final int version;
  final List<LibraryItem> items;
  final DateTime updatedAt;

  const LibraryIndex({
    required this.version,
    required this.items,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory LibraryIndex.empty() => LibraryIndex(
    version: 1,
    items: const <LibraryItem>[],
    updatedAt: DateTime.now(),
  );

  factory LibraryIndex.fromJson(Map<String, dynamic> json) => LibraryIndex(
    version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
    items: ((json['items'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((value) => LibraryItem.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}
