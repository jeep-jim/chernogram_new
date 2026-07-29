import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'realtime_gateway_models.dart';

class CgGatewayOutboxStore {
  static const int maxRecords = 500;
  final Directory? directoryOverride;
  final Map<String, CgGatewayOutboxRecord> _records =
      <String, CgGatewayOutboxRecord>{};
  bool _loaded = false;
  Future<void> _writeTail = Future<void>.value();

  CgGatewayOutboxStore({this.directoryOverride});

  Future<Directory> _directory() async {
    final override = directoryOverride;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}realtime_gateway',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}outbox_v1.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final file = await _file();
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      final now = DateTime.now().toUtc();
      for (final raw in decoded.whereType<Map>()) {
        final record = CgGatewayOutboxRecord.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (record.packetId.isEmpty ||
            record.roomId.isEmpty ||
            record.crypto.isEmpty ||
            record.createdAt
                .add(Duration(seconds: record.ttlSeconds))
                .isBefore(now)) {
          continue;
        }
        _records[record.packetId] = record;
      }
      await _trimAndPersistIfNeeded();
    } catch (_) {
      final damaged = File('${file.path}.damaged');
      try {
        if (await damaged.exists()) await damaged.delete();
        await file.rename(damaged.path);
      } catch (_) {}
      _records.clear();
    }
  }

  Future<List<CgGatewayOutboxRecord>> pending() async {
    await load();
    final now = DateTime.now().toUtc();
    final result = _records.values
        .where((record) => !record.nextAttemptAt.isAfter(now))
        .toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return result;
  }

  Future<List<CgGatewayOutboxRecord>> all() async {
    await load();
    final result = _records.values.toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return result;
  }

  Future<void> put(CgGatewayOutboxRecord record) async {
    await load();
    if (record.packetId.isEmpty ||
        record.roomId.isEmpty ||
        record.crypto.isEmpty) {
      throw ArgumentError('Invalid gateway outbox record');
    }
    _records[record.packetId] = record;
    await _trimAndPersistIfNeeded(force: true);
  }

  Future<void> markAttempt(
    String packetId, {
    required int attempts,
    required DateTime nextAttemptAt,
  }) async {
    await load();
    final existing = _records[packetId];
    if (existing == null) return;
    _records[packetId] = existing.copyWith(
      attempts: attempts,
      nextAttemptAt: nextAttemptAt.toUtc(),
    );
    await _persist();
  }

  Future<void> remove(String packetId) async {
    await load();
    if (_records.remove(packetId) == null) return;
    await _persist();
  }

  Future<void> clear() async {
    await load();
    _records.clear();
    await _persist();
  }

  Future<void> _trimAndPersistIfNeeded({bool force = false}) async {
    var changed = false;
    if (_records.length > maxRecords) {
      final ordered = _records.values.toList()
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      final overflow = ordered.length - maxRecords;
      for (final record in ordered.take(overflow)) {
        _records.remove(record.packetId);
      }
      changed = true;
    }
    if (force || changed) await _persist();
  }

  Future<void> _persist() async {
    final snapshot = _records.values.toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    _writeTail = _writeTail.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      final encoded = jsonEncode(
        snapshot.map((record) => record.toJson()).toList(growable: false),
      );
      await temporary.writeAsString(encoded, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    await _writeTail;
  }
}
