import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class StoredGatewayEvent {
  final int serverSeq;
  final int roomSeq;
  final String roomId;
  final String packetId;
  final String senderProfileId;
  final String senderDeviceId;
  final String kind;
  final String priority;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, dynamic> crypto;

  const StoredGatewayEvent({
    required this.serverSeq,
    required this.roomSeq,
    required this.roomId,
    required this.packetId,
    required this.senderProfileId,
    required this.senderDeviceId,
    required this.kind,
    required this.priority,
    required this.createdAt,
    required this.expiresAt,
    required this.crypto,
  });

  bool get expired => !expiresAt.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'serverSeq': serverSeq,
        'roomSeq': roomSeq,
        'roomId': roomId,
        'packetId': packetId,
        'senderProfileId': senderProfileId,
        'senderDeviceId': senderDeviceId,
        'kind': kind,
        'priority': priority,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'crypto': crypto,
      };

  factory StoredGatewayEvent.fromJson(Map<String, dynamic> json) {
    return StoredGatewayEvent(
      serverSeq: int.tryParse(json['serverSeq']?.toString() ?? '') ?? 0,
      roomSeq: int.tryParse(json['roomSeq']?.toString() ?? '') ?? 0,
      roomId: json['roomId']?.toString() ?? '',
      packetId: json['packetId']?.toString() ?? '',
      senderProfileId: json['senderProfileId']?.toString() ?? '',
      senderDeviceId: json['senderDeviceId']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'message',
      priority: json['priority']?.toString() ?? 'normal',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      crypto: json['crypto'] is Map
          ? Map<String, dynamic>.from(json['crypto'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class AppendGatewayResult {
  final StoredGatewayEvent event;
  final bool duplicate;

  const AppendGatewayResult(this.event, {required this.duplicate});
}

class GatewayStoreStats {
  final int rooms;
  final int events;
  final int lastServerSeq;

  const GatewayStoreStats({
    required this.rooms,
    required this.events,
    required this.lastServerSeq,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rooms': rooms,
        'events': events,
        'lastServerSeq': lastServerSeq,
      };
}

class GatewayJsonStore {
  static const int maxEventsPerChunk = 500;

  final Directory root;
  final Map<String, _RoomState> _rooms = <String, _RoomState>{};
  Future<void> _writeTail = Future<void>.value();
  int _lastServerSeq = 0;
  bool _initialized = false;

  GatewayJsonStore(this.root);

  Future<void> initialize() async {
    if (_initialized) return;
    await root.create(recursive: true);
    await Directory('${root.path}/rooms').create(recursive: true);
    await Directory('${root.path}/cursors').create(recursive: true);
    final stateFile = File('${root.path}/server_state.json');
    if (await stateFile.exists()) {
      final decoded = await _readJson(stateFile);
      if (decoded is Map) {
        _lastServerSeq =
            int.tryParse(decoded['lastServerSeq']?.toString() ?? '') ?? 0;
      }
    }
    _initialized = true;
  }

  Future<AppendGatewayResult> append({
    required String roomId,
    required String packetId,
    required String senderProfileId,
    required String senderDeviceId,
    required String kind,
    required String priority,
    required DateTime createdAt,
    required Duration ttl,
    required Map<String, dynamic> crypto,
  }) {
    return _exclusive(() async {
      await initialize();
      final room = await _loadRoom(roomId);
      final existing = room.byPacketId[packetId];
      if (existing != null) {
        return AppendGatewayResult(existing, duplicate: true);
      }

      _lastServerSeq++;
      room.lastRoomSeq++;
      final event = StoredGatewayEvent(
        serverSeq: _lastServerSeq,
        roomSeq: room.lastRoomSeq,
        roomId: roomId,
        packetId: packetId,
        senderProfileId: senderProfileId,
        senderDeviceId: senderDeviceId,
        kind: kind,
        priority: priority,
        createdAt: createdAt.toUtc(),
        expiresAt: DateTime.now().toUtc().add(ttl),
        crypto: Map<String, dynamic>.from(crypto),
      );

      if (room.currentChunkEvents.length >= maxEventsPerChunk) {
        room.currentChunk++;
        room.currentChunkEvents = <Map<String, dynamic>>[];
      }
      room.currentChunkEvents.add(event.toJson());
      await _writeJsonAtomic(
        _chunkFile(room, room.currentChunk),
        room.currentChunkEvents,
      );
      room.byPacketId[event.packetId] = event;
      await _writeRoomMeta(room);
      await _writeJsonAtomic(
        File('${root.path}/server_state.json'),
        <String, dynamic>{'lastServerSeq': _lastServerSeq},
      );
      return AppendGatewayResult(event, duplicate: false);
    });
  }

  Future<List<StoredGatewayEvent>> readAfter(
    String roomId,
    int lastRoomSeq, {
    int limit = 1000,
  }) async {
    await initialize();
    final room = await _loadRoom(roomId);
    final events = room.byPacketId.values
        .where((event) => event.roomSeq > lastRoomSeq && !event.expired)
        .toList()
      ..sort((left, right) => left.roomSeq.compareTo(right.roomSeq));
    if (events.length <= limit) return events;
    return events.sublist(0, limit);
  }

  Future<void> saveCursor({
    required String profileId,
    required String deviceId,
    required String roomId,
    required int roomSeq,
  }) async {
    await _exclusive(() async {
      await initialize();
      final file = _cursorFile(profileId, deviceId);
      final decoded = await _readJson(file);
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final current = int.tryParse(map[roomId]?.toString() ?? '') ?? 0;
      if (roomSeq > current) {
        map[roomId] = roomSeq;
        await _writeJsonAtomic(file, map);
      }
    });
  }

  Future<int> loadCursor({
    required String profileId,
    required String deviceId,
    required String roomId,
  }) async {
    await initialize();
    final decoded = await _readJson(_cursorFile(profileId, deviceId));
    if (decoded is! Map) return 0;
    return int.tryParse(decoded[roomId]?.toString() ?? '') ?? 0;
  }

  Future<GatewayStoreStats> stats() async {
    await initialize();
    var events = 0;
    final roomsDirectory = Directory('${root.path}/rooms');
    await for (final entity in roomsDirectory.list()) {
      if (entity is! Directory) continue;
      final metaFile = File('${entity.path}/room_meta.json');
      if (!await metaFile.exists()) continue;
      final meta = await _readJson(metaFile);
      if (meta is! Map) continue;
      final roomId = meta['roomId']?.toString() ?? '';
      if (roomId.isEmpty) continue;
      final room = await _loadRoom(roomId);
      events += room.byPacketId.values.where((event) => !event.expired).length;
    }
    return GatewayStoreStats(
      rooms: _rooms.length,
      events: events,
      lastServerSeq: _lastServerSeq,
    );
  }

  Future<_RoomState> _loadRoom(String roomId) async {
    final cached = _rooms[roomId];
    if (cached != null) return cached;

    final key = sha256.convert(utf8.encode(roomId)).toString();
    final directory = Directory('${root.path}/rooms/$key');
    await directory.create(recursive: true);
    final room = _RoomState(roomId: roomId, directory: directory);
    final metaFile = File('${directory.path}/room_meta.json');
    final decodedMeta = await _readJson(metaFile);
    if (decodedMeta is Map) {
      room.lastRoomSeq =
          int.tryParse(decodedMeta['lastRoomSeq']?.toString() ?? '') ?? 0;
      room.currentChunk =
          int.tryParse(decodedMeta['currentChunk']?.toString() ?? '') ?? 1;
    }

    final chunks = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File &&
          RegExp(r'events_\d{6}\.json$').hasMatch(entity.path)) {
        chunks.add(entity);
      }
    }
    chunks.sort((left, right) => left.path.compareTo(right.path));

    var highestChunk = 0;
    var highestChunkEvents = <Map<String, dynamic>>[];
    for (final file in chunks) {
      final raw = await _readEventChunk(file);
      for (final item in raw) {
        final event = StoredGatewayEvent.fromJson(item);
        if (event.packetId.isEmpty || event.roomSeq <= 0) continue;
        room.byPacketId[event.packetId] = event;
        if (event.roomSeq > room.lastRoomSeq) room.lastRoomSeq = event.roomSeq;
      }
      final match = RegExp(r'events_(\d{6})\.json$').firstMatch(file.path);
      final index = int.tryParse(match?.group(1) ?? '') ?? 1;
      if (index >= highestChunk) {
        highestChunk = index;
        highestChunkEvents = raw;
      }
    }

    if (highestChunk > room.currentChunk) room.currentChunk = highestChunk;
    if (highestChunk == room.currentChunk) {
      room.currentChunkEvents = highestChunkEvents;
    } else {
      room.currentChunkEvents =
          await _readEventChunk(_chunkFile(room, room.currentChunk));
    }

    _rooms[roomId] = room;
    await _writeRoomMeta(room);
    return room;
  }

  File _chunkFile(_RoomState room, int index) => File(
        '${room.directory.path}/events_${index.toString().padLeft(6, '0')}.json',
      );

  File _cursorFile(String profileId, String deviceId) {
    final key = sha256.convert(utf8.encode('$profileId:$deviceId')).toString();
    return File('${root.path}/cursors/$key.json');
  }

  Future<void> _writeRoomMeta(_RoomState room) {
    return _writeJsonAtomic(
      File('${room.directory.path}/room_meta.json'),
      <String, dynamic>{
        'roomId': room.roomId,
        'lastRoomSeq': room.lastRoomSeq,
        'currentChunk': room.currentChunk,
      },
    );
  }

  Future<List<Map<String, dynamic>>> _readEventChunk(File file) async {
    final decoded = await _readJson(file);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<dynamic> _readJson(File file) async {
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJsonAtomic(File file, Object value) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsString(jsonEncode(value));
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _RoomState {
  final String roomId;
  final Directory directory;
  final Map<String, StoredGatewayEvent> byPacketId =
      <String, StoredGatewayEvent>{};
  int lastRoomSeq = 0;
  int currentChunk = 1;
  List<Map<String, dynamic>> currentChunkEvents = <Map<String, dynamic>>[];

  _RoomState({required this.roomId, required this.directory});
}
