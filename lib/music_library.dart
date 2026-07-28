import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';

enum CgMusicSource { device, chats, folders, saved, public }

class CgMediaPermissions {
  final bool canPlay;
  final bool canDownload;
  final bool canShare;
  final bool canSave;
  final bool canIndex;

  const CgMediaPermissions({
    this.canPlay = true,
    this.canDownload = true,
    this.canShare = true,
    this.canSave = true,
    this.canIndex = false,
  });

  CgMediaPermissions copyWith({
    bool? canPlay,
    bool? canDownload,
    bool? canShare,
    bool? canSave,
    bool? canIndex,
  }) => CgMediaPermissions(
    canPlay: canPlay ?? this.canPlay,
    canDownload: canDownload ?? this.canDownload,
    canShare: canShare ?? this.canShare,
    canSave: canSave ?? this.canSave,
    canIndex: canIndex ?? this.canIndex,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'canPlay': canPlay,
    'canDownload': canDownload,
    'canShare': canShare,
    'canSave': canSave,
    'canIndex': canIndex,
  };

  factory CgMediaPermissions.fromJson(Map<String, dynamic> json) =>
      CgMediaPermissions(
        canPlay: json['canPlay'] != false,
        canDownload: json['canDownload'] != false,
        canShare: json['canShare'] != false,
        canSave: json['canSave'] != false,
        canIndex: json['canIndex'] == true,
      );
}

class CgMusicTrack {
  final String id;
  final String title;
  final String subtitle;
  final String path;
  final CgMusicSource source;
  final String author;
  final CgMediaPermissions permissions;
  final bool published;
  final DateTime addedAt;

  const CgMusicTrack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.path,
    this.source = CgMusicSource.device,
    this.author = '',
    this.permissions = const CgMediaPermissions(),
    this.published = false,
    required this.addedAt,
  });

  CgMusicTrack copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? path,
    CgMusicSource? source,
    String? author,
    CgMediaPermissions? permissions,
    bool? published,
    DateTime? addedAt,
  }) => CgMusicTrack(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    path: path ?? this.path,
    source: source ?? this.source,
    author: author ?? this.author,
    permissions: permissions ?? this.permissions,
    published: published ?? this.published,
    addedAt: addedAt ?? this.addedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'path': path,
    'source': source.name,
    'author': author,
    'permissions': permissions.toJson(),
    'published': published,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  factory CgMusicTrack.fromJson(Map<String, dynamic> json) => CgMusicTrack(
    id: json['id']?.toString().trim().isNotEmpty == true
        ? json['id'].toString()
        : CgIds.random(20),
    title: json['title']?.toString() ?? 'Track',
    subtitle: json['subtitle']?.toString() ?? '',
    path: json['path']?.toString() ?? '',
    source: CgMusicSource.values.firstWhere(
      (item) => item.name == json['source']?.toString(),
      orElse: () => CgMusicSource.device,
    ),
    author: json['author']?.toString() ?? '',
    permissions: json['permissions'] is Map
        ? CgMediaPermissions.fromJson(
            Map<String, dynamic>.from(json['permissions'] as Map),
          )
        : const CgMediaPermissions(),
    published: json['published'] == true,
    addedAt:
        DateTime.tryParse(json['addedAt']?.toString() ?? '') ??
        DateTime.now().toUtc(),
  );
}

class CgPlaylist {
  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;

  const CgPlaylist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
  });

  CgPlaylist copyWith({String? name, List<String>? trackIds}) => CgPlaylist(
    id: id,
    name: name ?? this.name,
    trackIds: trackIds ?? this.trackIds,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory CgPlaylist.fromJson(Map<String, dynamic> json) => CgPlaylist(
    id: json['id']?.toString().trim().isNotEmpty == true
        ? json['id'].toString()
        : CgIds.random(16),
    name: json['name']?.toString().trim().isNotEmpty == true
        ? json['name'].toString()
        : 'Playlist',
    trackIds: ((json['trackIds'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now().toUtc(),
  );
}

class CgPlayerSnapshot {
  final List<CgMusicTrack> queue;
  final int index;
  final Duration position;
  final String loopMode;
  final bool shuffle;

  const CgPlayerSnapshot({
    required this.queue,
    required this.index,
    required this.position,
    required this.loopMode,
    required this.shuffle,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'queue': queue.map((item) => item.toJson()).toList(),
    'index': index,
    'positionMs': position.inMilliseconds,
    'loopMode': loopMode,
    'shuffle': shuffle,
  };

  factory CgPlayerSnapshot.fromJson(Map<String, dynamic> json) =>
      CgPlayerSnapshot(
        queue: ((json['queue'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (item) => CgMusicTrack.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.path.isNotEmpty)
            .toList(),
        index: int.tryParse(json['index']?.toString() ?? '') ?? 0,
        position: Duration(
          milliseconds: int.tryParse(json['positionMs']?.toString() ?? '') ?? 0,
        ),
        loopMode: json['loopMode']?.toString() ?? 'off',
        shuffle: json['shuffle'] == true,
      );
}

class CgMusicLibraryStore {
  static const _savedKey = 'cg_music_saved_v1';
  static const _publishedKey = 'cg_music_published_v1';
  static const _playlistsKey = 'cg_music_playlists_v1';
  static const _playerKey = 'cg_music_player_v1';

  static Future<List<CgMusicTrack>> loadSaved() => _loadTracks(_savedKey);

  static Future<List<CgMusicTrack>> loadPublished() =>
      _loadTracks(_publishedKey);

  static Future<void> saveTrack(CgMusicTrack track) async {
    final tracks = await loadSaved();
    final next = track.copyWith(source: CgMusicSource.saved, published: false);
    final index = tracks.indexWhere((item) => item.path == next.path);
    if (index >= 0) {
      tracks[index] = next;
    } else {
      tracks.add(next);
    }
    await _saveTracks(_savedKey, tracks);
  }

  static Future<void> removeSaved(String trackId) async {
    final tracks = await loadSaved()
      ..removeWhere((item) => item.id == trackId);
    await _saveTracks(_savedKey, tracks);
  }

  static Future<void> publish(
    CgMusicTrack track, {
    required CgMediaPermissions permissions,
  }) async {
    final tracks = await loadPublished();
    final next = track.copyWith(
      source: CgMusicSource.public,
      permissions: permissions.copyWith(canIndex: true),
      published: true,
    );
    final index = tracks.indexWhere((item) => item.path == next.path);
    if (index >= 0) {
      tracks[index] = next;
    } else {
      tracks.add(next);
    }
    await _saveTracks(_publishedKey, tracks);
  }

  static Future<void> unpublish(String path) async {
    final tracks = await loadPublished()
      ..removeWhere((item) => item.path == path);
    await _saveTracks(_publishedKey, tracks);
  }

  static Future<List<CgPlaylist>> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null || raw.isEmpty) return <CgPlaylist>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CgPlaylist>[];
      return decoded
          .whereType<Map>()
          .map((item) => CgPlaylist.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <CgPlaylist>[];
    }
  }

  static Future<CgPlaylist> createPlaylist(String name) async {
    final playlists = await loadPlaylists();
    final playlist = CgPlaylist(
      id: CgIds.random(16),
      name: name.trim().isEmpty ? 'Playlist' : name.trim(),
      trackIds: <String>[],
      createdAt: DateTime.now().toUtc(),
    );
    playlists.add(playlist);
    await savePlaylists(playlists);
    return playlist;
  }

  static Future<void> addToPlaylist(String playlistId, String trackId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((item) => item.id == playlistId);
    if (index < 0) return;
    final ids = <String>[...playlists[index].trackIds];
    if (!ids.contains(trackId)) ids.add(trackId);
    playlists[index] = playlists[index].copyWith(trackIds: ids);
    await savePlaylists(playlists);
  }

  static Future<void> removePlaylist(String id) async {
    final playlists = await loadPlaylists()
      ..removeWhere((item) => item.id == id);
    await savePlaylists(playlists);
  }

  static Future<void> savePlaylists(List<CgPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistsKey,
      jsonEncode(playlists.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> savePlayerSnapshot(CgPlayerSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerKey, jsonEncode(snapshot.toJson()));
  }

  static Future<CgPlayerSnapshot?> loadPlayerSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playerKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? CgPlayerSnapshot.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPlayerSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playerKey);
  }

  static Future<List<CgMusicTrack>> _loadTracks(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <CgMusicTrack>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CgMusicTrack>[];
      return decoded
          .whereType<Map>()
          .map((item) => CgMusicTrack.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.path.isNotEmpty)
          .toList();
    } catch (_) {
      return <CgMusicTrack>[];
    }
  }

  static Future<void> _saveTracks(String key, List<CgMusicTrack> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    final tail = tracks.length > 500
        ? tracks.sublist(tracks.length - 500)
        : tracks;
    await prefs.setString(
      key,
      jsonEncode(tail.map((item) => item.toJson()).toList()),
    );
  }
}
