import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'realtime_gateway_models.dart';
import 'realtime_gateway_outbox.dart';

class CgRealtimeGatewayStatus {
  final String state;
  final String? code;
  final int reconnectAttempt;
  final DateTime at;

  const CgRealtimeGatewayStatus({
    required this.state,
    this.code,
    this.reconnectAttempt = 0,
    required this.at,
  });
}

class CgRealtimeGatewayClient {
  final Uri uri;
  final String profileId;
  final String deviceId;
  final Future<String> Function() accessTokenProvider;
  final CgGatewayOutboxStore outbox;

  final StreamController<CgGatewayEvent> _events =
      StreamController<CgGatewayEvent>.broadcast(sync: true);
  final StreamController<CgGatewayPresence> _presence =
      StreamController<CgGatewayPresence>.broadcast(sync: true);
  final StreamController<CgRealtimeGatewayStatus> _status =
      StreamController<CgRealtimeGatewayStatus>.broadcast(sync: true);
  final Map<String, CgRealtimeRoomCursor> _rooms =
      <String, CgRealtimeRoomCursor>{};
  final Map<String, Completer<CgGatewayAck>> _pendingAcks =
      <String, Completer<CgGatewayAck>>{};
  final Set<String> _receivedPacketIds = <String>{};

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _outboxTimer;
  Completer<void>? _helloCompleter;
  bool _closed = false;
  bool _connecting = false;
  bool _authenticated = false;
  int _reconnectAttempt = 0;
  int _heartbeatSeconds = 20;
  Future<void> _flushTail = Future<void>.value();

  CgRealtimeGatewayClient({
    required this.uri,
    required this.profileId,
    required this.deviceId,
    required this.accessTokenProvider,
    CgGatewayOutboxStore? outbox,
  }) : outbox = outbox ?? CgGatewayOutboxStore();

  Stream<CgGatewayEvent> get events => _events.stream;
  Stream<CgGatewayPresence> get presence => _presence.stream;
  Stream<CgRealtimeGatewayStatus> get status => _status.stream;
  bool get connected => _authenticated && _socket?.readyState == WebSocket.open;
  List<CgRealtimeRoomCursor> get rooms =>
      _rooms.values.toList(growable: false);

  Future<void> initialize(Iterable<CgRealtimeRoomCursor> rooms) async {
    await outbox.load();
    final saved = await _loadSavedCursors();
    for (final room in rooms) {
      final savedSeq = saved[room.roomId] ?? 0;
      _rooms[room.roomId] = CgRealtimeRoomCursor(
        roomId: room.roomId,
        lastRoomSeq: max(room.lastRoomSeq, savedSeq),
      );
    }
  }

  Future<bool> connect({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_closed) return false;
    if (connected) return true;
    if (_connecting) {
      final hello = _helloCompleter;
      if (hello != null) {
        try {
          await hello.future.timeout(timeout);
        } catch (_) {}
      }
      return connected;
    }

    _connecting = true;
    _authenticated = false;
    _helloCompleter = Completer<void>();
    _emitStatus('connecting');
    try {
      await _closeSocketOnly();
      final socket = await WebSocket.connect(uri.toString()).timeout(timeout);
      if (_closed) {
        await socket.close();
        return false;
      }
      _socket = socket;
      socket.pingInterval = Duration(seconds: _heartbeatSeconds);
      _subscription = socket.listen(
        _onRawFrame,
        onError: (Object error, StackTrace stackTrace) {
          _onDisconnected('socket_error:${error.runtimeType}');
        },
        onDone: () => _onDisconnected('socket_closed'),
        cancelOnError: true,
      );
      final token = await accessTokenProvider();
      _sendFrame(<String, dynamic>{
        'type': 'hello',
        'protocol': 1,
        'requestId': _randomId(20),
        'profileId': profileId,
        'deviceId': deviceId,
        if (token.isNotEmpty) 'accessToken': token,
        'rooms': _rooms.values.map((room) => room.toJson()).toList(),
      });
      await _helloCompleter!.future.timeout(timeout);
      return connected;
    } catch (error) {
      _emitStatus('offline', code: 'connect_failed:${error.runtimeType}');
      _scheduleReconnect();
      return false;
    } finally {
      _connecting = false;
    }
  }

  Future<void> subscribe(CgRealtimeRoomCursor room) async {
    final saved = await _loadSavedCursors();
    final cursor = CgRealtimeRoomCursor(
      roomId: room.roomId,
      lastRoomSeq: max(room.lastRoomSeq, saved[room.roomId] ?? 0),
    );
    _rooms[room.roomId] = cursor;
    if (!connected) {
      unawaited(connect());
      return;
    }
    _sendFrame(<String, dynamic>{
      'type': 'subscribe',
      'protocol': 1,
      'requestId': _randomId(20),
      ...cursor.toJson(),
    });
  }

  Future<void> unsubscribe(String roomId) async {
    _rooms.remove(roomId);
    if (connected) {
      _sendFrame(<String, dynamic>{
        'type': 'unsubscribe',
        'protocol': 1,
        'requestId': _randomId(20),
        'roomId': roomId,
      });
    }
  }

  Future<CgGatewayAck?> sendEncrypted({
    required String roomId,
    required String kind,
    required Map<String, dynamic> crypto,
    String priority = 'normal',
    Duration ttl = const Duration(days: 7),
    String? packetId,
    Duration ackTimeout = const Duration(seconds: 6),
  }) async {
    if (_closed || roomId.isEmpty || crypto.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final record = CgGatewayOutboxRecord(
      packetId: packetId ?? _randomId(24),
      requestId: _randomId(20),
      roomId: roomId,
      kind: kind,
      priority: priority,
      createdAt: now,
      ttlSeconds: ttl.inSeconds.clamp(5, const Duration(days: 30).inSeconds),
      crypto: Map<String, dynamic>.from(crypto),
      nextAttemptAt: now,
    );
    await outbox.put(record);
    if (!connected) await connect();
    return _sendRecord(record, ackTimeout: ackTimeout);
  }

  Future<CgGatewayAck?> _sendRecord(
    CgGatewayOutboxRecord record, {
    Duration ackTimeout = const Duration(seconds: 6),
  }) async {
    if (!connected) return null;
    final completer = Completer<CgGatewayAck>();
    _pendingAcks[record.packetId]?.completeError(
      StateError('Superseded by a new retry'),
    );
    _pendingAcks[record.packetId] = completer;
    _sendFrame(record.toEventFrame());
    try {
      return await completer.future.timeout(ackTimeout);
    } catch (_) {
      final attempts = record.attempts + 1;
      final delaySeconds = min(30, 1 << min(attempts, 5));
      await outbox.markAttempt(
        record.packetId,
        attempts: attempts,
        nextAttemptAt: DateTime.now().toUtc().add(
              Duration(seconds: delaySeconds),
            ),
      );
      return null;
    } finally {
      if (identical(_pendingAcks[record.packetId], completer)) {
        _pendingAcks.remove(record.packetId);
      }
    }
  }

  void _onRawFrame(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      final type = frame['type']?.toString() ?? '';
      switch (type) {
        case 'hello_ack':
          _authenticated = true;
          _reconnectAttempt = 0;
          _heartbeatSeconds =
              int.tryParse(frame['heartbeatSeconds']?.toString() ?? '') ?? 20;
          if (_helloCompleter?.isCompleted == false) {
            _helloCompleter!.complete();
          }
          _startTimers();
          _emitStatus('connected');
          unawaited(_flushOutbox());
          break;
        case 'event_ack':
          unawaited(_handleEventAck(frame));
          break;
        case 'event':
          unawaited(_handleEvent(frame));
          break;
        case 'presence':
          if (!_presence.isClosed) {
            _presence.add(CgGatewayPresence.fromJson(frame));
          }
          break;
        case 'server_ping':
        case 'ping':
          _sendFrame(<String, dynamic>{
            'type': 'pong',
            'protocol': 1,
            'requestId': frame['requestId'],
            'clientTime': DateTime.now().toUtc().toIso8601String(),
          });
          break;
        case 'error':
          _emitStatus(
            connected ? 'connected' : 'offline',
            code: frame['code']?.toString() ?? 'gateway_error',
          );
          break;
      }
    } catch (_) {
      _emitStatus('connected', code: 'invalid_server_frame');
    }
  }

  Future<void> _handleEventAck(Map<String, dynamic> frame) async {
    final ack = CgGatewayAck.fromJson(frame);
    if (ack.packetId.isEmpty) return;
    await outbox.remove(ack.packetId);
    final completer = _pendingAcks.remove(ack.packetId);
    if (completer != null && !completer.isCompleted) completer.complete(ack);
  }

  Future<void> _handleEvent(Map<String, dynamic> frame) async {
    final event = CgGatewayEvent.fromJson(frame);
    if (event.packetId.isEmpty ||
        event.roomId.isEmpty ||
        event.roomSeq <= 0 ||
        !_receivedPacketIds.add(event.packetId)) {
      return;
    }
    if (_receivedPacketIds.length > 10000) {
      _receivedPacketIds.remove(_receivedPacketIds.first);
    }
    final current = _rooms[event.roomId];
    if (current == null || event.roomSeq > current.lastRoomSeq) {
      _rooms[event.roomId] = CgRealtimeRoomCursor(
        roomId: event.roomId,
        lastRoomSeq: max(current?.lastRoomSeq ?? 0, event.roomSeq),
      );
      await _saveCursor(event.roomId, event.roomSeq);
    }
    _sendFrame(<String, dynamic>{
      'type': 'ack',
      'protocol': 1,
      'roomId': event.roomId,
      'roomSeq': event.roomSeq,
    });
    if (!_events.isClosed) _events.add(event);
  }

  void _startTimers() {
    _heartbeatTimer?.cancel();
    _outboxTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: max(8, _heartbeatSeconds - 4)),
      (_) {
        if (!connected) return;
        _sendFrame(<String, dynamic>{
          'type': 'ping',
          'protocol': 1,
          'requestId': _randomId(16),
          'clientTime': DateTime.now().toUtc().toIso8601String(),
        });
      },
    );
    _outboxTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (connected) unawaited(_flushOutbox());
    });
  }

  Future<void> _flushOutbox() async {
    _flushTail = _flushTail.then((_) async {
      if (!connected || _closed) return;
      final pending = await outbox.pending();
      for (final record in pending) {
        if (!connected || _closed) break;
        await _sendRecord(record);
      }
    });
    await _flushTail;
  }

  void _sendFrame(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(frame));
    } catch (_) {
      _onDisconnected('send_failed');
    }
  }

  void _onDisconnected(String code) {
    if (_closed) return;
    _authenticated = false;
    _heartbeatTimer?.cancel();
    _outboxTimer?.cancel();
    if (_helloCompleter?.isCompleted == false) {
      _helloCompleter!.completeError(StateError(code));
    }
    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('gateway_disconnected'));
      }
    }
    _pendingAcks.clear();
    _emitStatus('offline', code: code);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || connected || _reconnectTimer?.isActive == true) return;
    _reconnectAttempt++;
    final base = min(30, 1 << min(_reconnectAttempt, 5));
    final jitter = Random.secure().nextInt(max(1, base * 350));
    final delay = Duration(milliseconds: base * 650 + jitter);
    _emitStatus(
      'reconnecting',
      code: 'retry_in_${delay.inMilliseconds}ms',
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(connect());
    });
  }

  void retryNow() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(connect());
  }

  Future<Map<String, int>> _loadSavedCursors() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cursorKey);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return <String, int>{
        for (final entry in decoded.entries)
          entry.key.toString(): int.tryParse(entry.value.toString()) ?? 0,
      };
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _saveCursor(String roomId, int roomSeq) async {
    final cursors = await _loadSavedCursors();
    if ((cursors[roomId] ?? 0) >= roomSeq) return;
    cursors[roomId] = roomSeq;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cursorKey, jsonEncode(cursors));
  }

  String get _cursorKey => 'cg_gateway_cursor_v1_${profileId}_$deviceId';

  void _emitStatus(String state, {String? code}) {
    if (_status.isClosed) return;
    _status.add(
      CgRealtimeGatewayStatus(
        state: state,
        code: code,
        reconnectAttempt: _reconnectAttempt,
        at: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _closeSocketOnly() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'reconnect');
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _outboxTimer?.cancel();
    _authenticated = false;
    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('gateway_closed'));
      }
    }
    _pendingAcks.clear();
    await _closeSocketOnly();
    await _events.close();
    await _presence.close();
    await _status.close();
  }
}

String _randomId(int byteCount) {
  final random = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(byteCount, (_) => random.nextInt(256)),
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}
