import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../optical/optical_models.dart';
import 'library_models.dart';

class LibraryStore {
  static Future<Directory> _root() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/chernogram_library');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> _indexFile() async {
    final root = await _root();
    return File('${root.path}/index.json');
  }

  static Future<Directory> _importsDirectory() async {
    final root = await _root();
    final directory = Directory('${root.path}/imports');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<List<LibraryItem>> loadItems() async {
    final file = await _indexFile();
    if (!await file.exists()) return <LibraryItem>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <LibraryItem>[];
      final index = LibraryIndex.fromJson(Map<String, dynamic>.from(decoded));
      final result = <LibraryItem>[];
      for (final item in index.items) {
        final path = item.localPath;
        if (path != null && path.isNotEmpty) {
          final available = await File(path).exists();
          result.add(item.copyWith(available: available));
        } else {
          result.add(item);
        }
      }
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (_) {
      return <LibraryItem>[];
    }
  }

  static Future<void> saveItems(List<LibraryItem> items) async {
    final file = await _indexFile();
    final temporary = File('${file.path}.tmp');
    final index = LibraryIndex(
      version: 1,
      items: items,
      updatedAt: DateTime.now(),
    );
    await temporary.writeAsString(index.encode(), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static Future<List<LibraryItem>> syncRooms({
    required List<OpticalRoom> rooms,
    required List<LibraryItem> current,
    required String localDeviceId,
  }) async {
    final byId = <String, LibraryItem>{for (final item in current) item.id: item};
    final now = DateTime.now();
    for (final room in rooms) {
      for (final message in room.messages) {
        if (!message.isFile || message.deleted) continue;
        final itemId = 'chat_${room.id}_${message.id}';
        final old = byId[itemId];
        final kind = LibraryKinds.detect(message.fileName ?? 'file.bin', hint: message.kind);
        final item = LibraryItem(
          id: itemId,
          name: message.fileName ?? 'Файл',
          kind: kind,
          access: LibraryAccess.room,
          localPath: message.filePath ?? old?.localPath,
          roomId: room.id,
          messageId: message.id,
          ownerId: message.senderId,
          ownerName: message.senderName,
          sourceDeviceId: message.senderId == localDeviceId
              ? localDeviceId
              : message.senderId,
          size: message.fileSize,
          createdAt: message.sentAt,
          updatedAt: old?.updatedAt ?? message.sentAt,
          available: message.filePath != null
              ? await File(message.filePath!).exists()
              : old?.available ?? false,
          downloaded: message.filePath != null,
          artist: old?.artist,
          album: old?.album,
          description: old?.description,
          tags: old?.tags ?? const <String>[],
        );
        byId[itemId] = item;
      }
    }
    final result = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveItems(result);
    return result;
  }

  static Future<List<LibraryItem>> importFiles({
    required List<PlatformFile> files,
    required List<LibraryItem> current,
    required String ownerId,
    required String ownerName,
    required String deviceId,
  }) async {
    final imports = await _importsDirectory();
    final result = <LibraryItem>[...current];
    for (final selected in files) {
      final sourcePath = selected.path;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      final source = File(sourcePath);
      if (!await source.exists()) continue;
      final id = libraryRandomId();
      final safeName = _safeName(selected.name);
      final destination = File('${imports.path}/${id}_$safeName');
      await source.copy(destination.path);
      final stat = await destination.stat();
      result.insert(
        0,
        LibraryItem(
          id: id,
          name: selected.name,
          kind: LibraryKinds.detect(selected.name),
          access: LibraryAccess.private,
          localPath: destination.path,
          ownerId: ownerId,
          ownerName: ownerName,
          sourceDeviceId: deviceId,
          size: stat.size,
          createdAt: stat.changed,
          updatedAt: stat.modified,
          available: true,
          downloaded: true,
        ),
      );
    }
    await saveItems(result);
    return result;
  }

  static Future<List<LibraryItem>> removeItem({
    required String id,
    required List<LibraryItem> current,
    bool deleteLocalCopy = false,
  }) async {
    final item = current.where((value) => value.id == id).firstOrNull;
    if (deleteLocalCopy && item?.localPath != null) {
      final file = File(item!.localPath!);
      if (await file.exists()) await file.delete();
    }
    final result = current.where((value) => value.id != id).toList();
    await saveItems(result);
    return result;
  }

  static Future<List<LibraryItem>> updateItem({
    required LibraryItem item,
    required List<LibraryItem> current,
  }) async {
    final result = <LibraryItem>[...current];
    final index = result.indexWhere((value) => value.id == item.id);
    if (index < 0) {
      result.insert(0, item);
    } else {
      result[index] = item;
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveItems(result);
    return result;
  }

  static String _safeName(String value) {
    final clean = value.trim().isEmpty ? 'file.bin' : value.trim();
    return clean.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
