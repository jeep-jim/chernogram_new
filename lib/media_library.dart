import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_media.dart';
import 'core_models.dart';

enum CgMediaLibrarySource { device, chat, voice, saved, publicCatalog }

enum CgMediaVisibility { private, contacts, public }

class CgMediaRights {
  final CgMediaVisibility visibility;
  final bool canDownload;
  final bool canShare;
  final bool canSave;
  final bool indexed;

  const CgMediaRights({
    this.visibility = CgMediaVisibility.private,
    this.canDownload = true,
    this.canShare = true,
    this.canSave = true,
    this.indexed = false,
  });

  CgMediaRights copyWith({
    CgMediaVisibility? visibility,
    bool? canDownload,
    bool? canShare,
    bool? canSave,
    bool? indexed,
  }) =>
      CgMediaRights(
        visibility: visibility ?? this.visibility,
        canDownload: canDownload ?? this.canDownload,
        canShare: canShare ?? this.canShare,
        canSave: canSave ?? this.canSave,
        indexed: indexed ?? this.indexed,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'visibility': visibility.name,
        'canDownload': canDownload,
        'canShare': canShare,
        'canSave': canSave,
        'indexed': indexed,
      };

  factory CgMediaRights.fromJson(Map<String, dynamic> json) {
    final visibilityName = json['visibility']?.toString() ?? 'private';
    return CgMediaRights(
      visibility: CgMediaVisibility.values.firstWhere(
        (value) => value.name == visibilityName,
        orElse: () => CgMediaVisibility.private,
      ),
      canDownload: json['canDownload'] != false,
      canShare: json['canShare'] != false,
      canSave: json['canSave'] != false,
      indexed: json['indexed'] == true,
    );
  }
}

class CgMediaLibraryAsset {
  final String id;
  final String ownerId;
  final String ownerName;
  final String name;
  final String kind;
  final int size;
  final String? localPath;
  final String? thumbnailPath;
  final String? tunnelId;
  final String? tunnelName;
  final String? messageId;
  final String? sourceAssetId;
  final CgMediaLibrarySource source;
  final CgMediaRights rights;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CgMediaLibraryAsset({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.kind,
    required this.size,
    this.localPath,
    this.thumbnailPath,
    this.tunnelId,
    this.tunnelName,
    this.messageId,
    this.sourceAssetId,
    required this.source,
    this.rights = const CgMediaRights(),
    required this.createdAt,
    required this.updatedAt,
  });

  bool get existsLocally => localPath != null && localPath!.isNotEmpty;
  bool get published => rights.visibility == CgMediaVisibility.public && rights.indexed;

  CgMediaLibraryAsset copyWith({
    String? localPath,
    String? thumbnailPath,
    CgMediaLibrarySource? source,
    CgMediaRights? rights,
    DateTime? updatedAt,
  }) =>
      CgMediaLibraryAsset(
        id: id,
        ownerId: ownerId,
        ownerName: ownerName,
        name: name,
        kind: kind,
        size: size,
        localPath: localPath ?? this.localPath,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        tunnelId: tunnelId,
        tunnelName: tunnelName,
        messageId: messageId,
        sourceAssetId: sourceAssetId,
        source: source ?? this.source,
        rights: rights ?? this.rights,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'name': name,
        'kind': kind,
        'size': size,
        if (localPath != null) 'localPath': localPath,
        if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
        if (tunnelId != null) 'tunnelId': tunnelId,
        if (tunnelName != null) 'tunnelName': tunnelName,
        if (messageId != null) 'messageId': messageId,
        if (sourceAssetId != null) 'sourceAssetId': sourceAssetId,
        'source': source.name,
        'rights': rights.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory CgMediaLibraryAsset.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source']?.toString() ?? 'saved';
    return CgMediaLibraryAsset(
      id: json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? '',
      name: json['name']?.toString() ?? 'file',
      kind: json['kind']?.toString() ?? 'file',
      size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
      localPath: json['localPath']?.toString(),
      thumbnailPath: json['thumbnailPath']?.toString(),
      tunnelId: json['tunnelId']?.toString(),
      tunnelName: json['tunnelName']?.toString(),
      messageId: json['messageId']?.toString(),
      sourceAssetId: json['sourceAssetId']?.toString(),
      source: CgMediaLibrarySource.values.firstWhere(
        (value) => value.name == sourceName,
        orElse: () => CgMediaLibrarySource.saved,
      ),
      rights: json['rights'] is Map
          ? CgMediaRights.fromJson(
              Map<String, dynamic>.from(json['rights'] as Map),
            )
          : const CgMediaRights(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

class CgMediaLibraryStore {
  static const int chunkSize = 500;
  static final CgMediaLibraryStore instance = CgMediaLibraryStore._();

  CgMediaLibraryStore._();

  final Map<String, CgMediaLibraryAsset> _assets =
      <String, CgMediaLibraryAsset>{};
  bool _loaded = false;
  Future<void> _writeTail = Future<void>.value();

  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}media_library',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _savedRoot() async {
    final root = await _root();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}saved_files',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final root = await _root();
    final files = await root
        .list(followLinks: false)
        .where((entity) => entity is File && RegExp(r'catalog_\d{4}\.json$').hasMatch(entity.path))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! List) continue;
        for (final raw in decoded.whereType<Map>()) {
          final asset = CgMediaLibraryAsset.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (asset.id.isNotEmpty) _assets[asset.id] = asset;
        }
      } catch (_) {
        // One broken chunk must not hide the other chunks.
      }
    }
  }

  Future<List<CgMediaLibraryAsset>> rebuildFromTunnels({
    required List<CgTunnel> tunnels,
    required CgProfile profile,
  }) async {
    await load();
    final preserved = _assets.values
        .where((asset) =>
            asset.source == CgMediaLibrarySource.saved ||
            asset.source == CgMediaLibrarySource.device ||
            asset.rights.indexed)
        .toList(growable: false);
    _assets
      ..clear()
      ..addEntries(preserved.map((asset) => MapEntry(asset.id, asset)));

    final now = DateTime.now().toUtc();
    for (final item in CgMediaStore.collect(tunnels)) {
      final attachment = item.attachment;
      final source = attachment.kind == 'voice'
          ? CgMediaLibrarySource.voice
          : CgMediaLibrarySource.chat;
      final id = 'chat:${item.tunnelId}:${item.messageId}:${attachment.id}';
      final existing = _assets[id];
      _assets[id] = CgMediaLibraryAsset(
        id: id,
        ownerId: profile.id,
        ownerName: item.authorName,
        name: attachment.kind == 'voice' ? 'Voice ${item.authorName}' : attachment.name,
        kind: attachment.kind,
        size: attachment.size,
        localPath: attachment.localPath,
        tunnelId: item.tunnelId,
        tunnelName: item.tunnelName,
        messageId: item.messageId,
        sourceAssetId: attachment.id,
        source: source,
        rights: existing?.rights ?? const CgMediaRights(),
        createdAt: item.sentAt,
        updatedAt: now,
      );
    }
    await _persist();
    return all();
  }

  Future<List<CgMediaLibraryAsset>> importFiles({
    required CgProfile profile,
  }) async {
    await load();
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
    );
    if (result == null) return all();
    final savedRoot = await _savedRoot();
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null || path.isEmpty) continue;
      final source = File(path);
      if (!await source.exists()) continue;
      final id = 'device:${CgIds.random(22)}';
      final safeName = _safeName(picked.name);
      final target = File(
        '${savedRoot.path}${Platform.pathSeparator}${id.replaceAll(':', '_')}_$safeName',
      );
      await source.copy(target.path);
      final now = DateTime.now().toUtc();
      _assets[id] = CgMediaLibraryAsset(
        id: id,
        ownerId: profile.id,
        ownerName: profile.nickname,
        name: picked.name,
        kind: _kindForName(picked.name),
        size: await target.length(),
        localPath: target.path,
        source: CgMediaLibrarySource.device,
        rights: const CgMediaRights(),
        createdAt: now,
        updatedAt: now,
      );
    }
    await _persist();
    return all();
  }

  Future<CgMediaLibraryAsset?> saveToLibrary(
    CgMediaLibraryAsset source, {
    required CgProfile profile,
  }) async {
    await load();
    if (!source.rights.canSave || source.localPath == null) return null;
    final input = File(source.localPath!);
    if (!await input.exists()) return null;
    final root = await _savedRoot();
    final id = 'saved:${CgIds.random(22)}';
    final target = File(
      '${root.path}${Platform.pathSeparator}${id.replaceAll(':', '_')}_${_safeName(source.name)}',
    );
    await input.copy(target.path);
    final now = DateTime.now().toUtc();
    final saved = CgMediaLibraryAsset(
      id: id,
      ownerId: profile.id,
      ownerName: profile.nickname,
      name: source.name,
      kind: source.kind,
      size: await target.length(),
      localPath: target.path,
      sourceAssetId: source.id,
      source: CgMediaLibrarySource.saved,
      rights: const CgMediaRights(),
      createdAt: now,
      updatedAt: now,
    );
    _assets[id] = saved;
    await _persist();
    return saved;
  }

  Future<void> updateRights(String id, CgMediaRights rights) async {
    await load();
    final existing = _assets[id];
    if (existing == null) return;
    var normalized = rights;
    if (rights.visibility != CgMediaVisibility.public) {
      normalized = rights.copyWith(indexed: false);
    }
    _assets[id] = existing.copyWith(
      rights: normalized,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> remove(String id) async {
    await load();
    final asset = _assets.remove(id);
    if (asset == null) return;
    if ((asset.source == CgMediaLibrarySource.saved ||
            asset.source == CgMediaLibrarySource.device) &&
        asset.localPath != null) {
      try {
        final file = File(asset.localPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _persist();
  }

  List<CgMediaLibraryAsset> all() {
    final result = _assets.values.toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return result;
  }

  List<CgMediaLibraryAsset> search({
    String query = '',
    CgMediaLibrarySource? source,
    String? kind,
  }) {
    final normalized = query.trim().toLowerCase();
    return all().where((asset) {
      if (source != null && asset.source != source) return false;
      if (kind != null && kind.isNotEmpty && asset.kind != kind) return false;
      if (normalized.isEmpty) return true;
      return asset.name.toLowerCase().contains(normalized) ||
          asset.ownerName.toLowerCase().contains(normalized) ||
          (asset.tunnelName?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);
  }

  List<CgMediaLibraryAsset> publicLocalSearch(String query) {
    final normalized = query.trim().toLowerCase();
    return all().where((asset) {
      if (!asset.published) return false;
      if (normalized.isEmpty) return true;
      return asset.name.toLowerCase().contains(normalized) ||
          asset.ownerName.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }

  Future<void> _persist() async {
    final snapshot = all();
    _writeTail = _writeTail.then((_) async {
      final root = await _root();
      final old = await root
          .list(followLinks: false)
          .where((entity) => entity is File && RegExp(r'catalog_\d{4}\.json$').hasMatch(entity.path))
          .cast<File>()
          .toList();
      final temporaryFiles = <File>[];
      for (var offset = 0, chunk = 1;
          offset < snapshot.length;
          offset += chunkSize, chunk++) {
        final end = (offset + chunkSize).clamp(0, snapshot.length).toInt();
        final file = File(
          '${root.path}${Platform.pathSeparator}catalog_${chunk.toString().padLeft(4, '0')}.json.tmp',
        );
        await file.writeAsString(
          jsonEncode(
            snapshot
                .sublist(offset, end)
                .map((asset) => asset.toJson())
                .toList(growable: false),
          ),
          flush: true,
        );
        temporaryFiles.add(file);
      }
      for (final file in old) {
        try {
          await file.delete();
        } catch (_) {}
      }
      for (var index = 0; index < temporaryFiles.length; index++) {
        final target = File(
          '${root.path}${Platform.pathSeparator}catalog_${(index + 1).toString().padLeft(4, '0')}.json',
        );
        await temporaryFiles[index].rename(target.path);
      }
    });
    await _writeTail;
  }

  String _safeName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-ЯёЁ._-]+'), '_');
    return sanitized.isEmpty ? 'file' : sanitized;
  }

  String _kindForName(String name) {
    final extension = name.toLowerCase().split('.').last;
    if (<String>{'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'}.contains(extension)) {
      return 'image';
    }
    if (<String>{'mp4', 'mov', 'mkv', 'avi', 'webm'}.contains(extension)) {
      return 'video';
    }
    if (<String>{'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'}.contains(extension)) {
      return 'audio';
    }
    return 'file';
  }
}
