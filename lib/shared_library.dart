import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';

class CgLocalSharedFile {
  final CgSharedFileInfo info;
  final String path;

  const CgLocalSharedFile({required this.info, required this.path});

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...info.toJson(),
        'path': path,
      };

  factory CgLocalSharedFile.fromJson(Map<String, dynamic> json) =>
      CgLocalSharedFile(
        info: CgSharedFileInfo.fromJson(json),
        path: json['path']?.toString() ?? '',
      );
}

class CgSharedLibraryStore {
  static String _tunnelKey(String tunnelId) => 'cg_share_v2_$tunnelId';
  static const String _musicFoldersKey = 'cg_music_folders_v2';

  static String kindForName(String name) {
    final value = name.toLowerCase();
    if (value.endsWith('.jpg') ||
        value.endsWith('.jpeg') ||
        value.endsWith('.png') ||
        value.endsWith('.webp') ||
        value.endsWith('.gif')) {
      return 'image';
    }
    if (value.endsWith('.mp3') ||
        value.endsWith('.m4a') ||
        value.endsWith('.aac') ||
        value.endsWith('.wav') ||
        value.endsWith('.flac') ||
        value.endsWith('.ogg') ||
        value.endsWith('.opus')) {
      return 'audio';
    }
    if (value.endsWith('.mp4') ||
        value.endsWith('.mov') ||
        value.endsWith('.mkv') ||
        value.endsWith('.webm') ||
        value.endsWith('.avi')) {
      return 'video';
    }
    if (value.endsWith('.zip') ||
        value.endsWith('.rar') ||
        value.endsWith('.7z')) {
      return 'archive';
    }
    return 'file';
  }

  static Future<List<CgLocalSharedFile>> chooseFolder(
    String tunnelId, {
    int maxFiles = 500,
    int maxFileBytes = 20 * 1024 * 1024,
  }) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите общую папку',
    );
    if (path == null || path.isEmpty) return loadTunnelFiles(tunnelId);
    final root = Directory(path);
    final files = <CgLocalSharedFile>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (files.length >= maxFiles) break;
      if (entity is! File) continue;
      try {
        final size = await entity.length();
        if (size <= 0 || size > maxFileBytes) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final relative = entity.path.startsWith('${root.path}${Platform.pathSeparator}')
            ? entity.path.substring(root.path.length + 1)
            : name;
        final id = base64Url
            .encode(utf8.encode('$tunnelId:$relative:$size'))
            .replaceAll('=', '');
        files.add(
          CgLocalSharedFile(
            info: CgSharedFileInfo(
              id: id,
              name: relative,
              size: size,
              kind: kindForName(name),
            ),
            path: entity.path,
          ),
        );
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tunnelKey(tunnelId),
      jsonEncode(files.map((item) => item.toJson()).toList()),
    );
    return files;
  }

  static Future<List<CgLocalSharedFile>> loadTunnelFiles(String tunnelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tunnelKey(tunnelId));
    if (raw == null) return const <CgLocalSharedFile>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (item) => CgLocalSharedFile.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.path.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const <CgLocalSharedFile>[];
  }

  static Future<CgLocalSharedFile?> find(
    String tunnelId,
    String fileId,
  ) async {
    final files = await loadTunnelFiles(tunnelId);
    for (final item in files) {
      if (item.info.id == fileId) return item;
    }
    return null;
  }

  static Future<List<String>> loadMusicFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_musicFoldersKey) ?? const <String>[];
  }

  static Future<List<String>> addMusicFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку с музыкой',
    );
    final folders = [...await loadMusicFolders()];
    if (path != null && path.isNotEmpty && !folders.contains(path)) {
      folders.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_musicFoldersKey, folders);
    }
    return folders;
  }

  static Future<void> removeMusicFolder(String path) async {
    final folders = [...await loadMusicFolders()]..remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_musicFoldersKey, folders);
  }

  static Future<List<File>> scanMusicFolders({int maxFiles = 3000}) async {
    final result = <File>[];
    for (final folder in await loadMusicFolders()) {
      final root = Directory(folder);
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (result.length >= maxFiles) return result;
        if (entity is! File) continue;
        if (kindForName(entity.path) == 'audio') result.add(entity);
      }
    }
    return result;
  }
}
