import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final config = GatewayConfig.fromEnvironment();
  final store = EventStore(Directory(config.dataDirectory));
  await store.initialize();

  final gateway = RealtimeGateway(
    config: config,
    store: store,
    tokenVerifier: AccessTokenVerifier(
      secret: config.tokenSecret,
      allowInsecureDevelopmentToken: config.allowInsecureDevelopmentToken,
    ),
  );
  await gateway.start();
}

class GatewayConfig {
  final InternetAddress bindAddress;
  final int port;
  final String dataDirectory;
  final String tokenSecret;
  final bool allowInsecureDevelopmentToken;
  final int maxRoomsPerClient;
  final int maxFrameBytes;
  final Duration heartbeatInterval;
  final Duration staleClientTimeout;

  const GatewayConfig({
    required this.bindAddress,
    required this.port,
    required this.dataDirectory,
    required this.tokenSecret,
    required this.allowInsecureDevelopmentToken,
    required this.maxRoomsPerClient,
    required this.maxFrameBytes,
    required this.heartbeatInterval,
    required this.staleClientTimeout,
  });

  factory GatewayConfig.fromEnvironment() {
    final env = Platform.environment;
    final host = env['CG_BIND']?.trim();
    final tokenSecret = env['CG_TOKEN_SECRET']?.trim() ?? '';
    final allowDev = env['CG_ALLOW_INSECURE_DEV'] == '1';
    if (tokenSecret.length < 32 && !allowDev) {
      throw StateError(
        'CG_TOKEN_SECRET must contain at least 32 characters. '
        'For local-only development, set CG_ALLOW_INSECURE_DEV=1.',
      );
    }
    return GatewayConfig(
      bindAddress: host == null || host.isEmpty
          ? InternetAddress.anyIPv4
          : InternetAddress(host),
      port: int.tryParse(env['CG_PORT'] ?? '') ?? 8080,
      dataDirectory: env['CG_DATA_DIR']?.trim().isNotEmpty == true
          ? env['CG_DATA_DIR']!.trim()
          : 'data',
      tokenSecret: tokenSecret,
      allowInsecureDevelopmentToken: allowDev,
      maxRoomsPerClient:
          (int.tryParse(env['CG_MAX_ROOMS'] ?? '') ?? 500).clamp(1, 2000),
      maxFrameBytes:
          (int.tryParse(env['CG_MAX_FRAME_BYTES'] ?? '') ?? 65536)
              .clamp(4096, 1048576),
      heartbeatInterval: const Duration(seconds: 20),
      staleClientTimeout: const Duration(seconds: 55),
    );
  }
}

class AccessTokenClaims {
  final String profileId;
  final String deviceId;
  final DateTime expiresAt;

  const AccessTokenClaims({
    required this.profileId,
    required this.deviceId,
    required this.expiresAt,
  });
}

class AccessTokenVerifier {
  final String secret;
  final bool allowInsecureDevelopmentToken;
  final Hmac _hmac = Hmac.sha256();

  AccessTokenVerifier({
    required this.secret,
    required this.allowInsecureDevelopmentToken,
  });

  Future<AccessTokenClaims?> verify(String token) async {
    if (allowInsecureDevelopmentToken && token == 'dev') {
      return AccessTokenClaims(
        profileId: '*',
        deviceId: '*',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      );
    }

    final parts = token.split('.');
    if (parts.length != 2 || secret.isEmpty) return null;
    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[0]));
      final receivedMac = base64Url.decode(base64Url.normalize(parts[1]));
      final expected = await _hmac.calculateMac(
        payloadBytes,
        secretKey: SecretKey(utf8.encode(secret)),
      );
      if (!_constantTimeEquals(receivedMac, expected.bytes)) return null;

      final decoded = jsonDecode(utf8.decode(payloadBytes));
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      final profileId = json['profileId']?.toString().trim() ?? '';
      final deviceId = json['deviceId']?.toString().trim() ?? '';
      final expiresSeconds = int.tryParse(json['exp']?.toString() ?? '');
      if (profileId.isEmpty || deviceId.isEmpty || expiresSeconds == null) {
        return null;
      }
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresSeconds * 1000,
        isUtc: true,
      );
      if (!expiresAt.isAfter(DateTime.now().toUtc())) return null;
      return AccessTokenClaims(
        profileId: profileId,
        deviceId: deviceId,
        expiresAt: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

class StoredEvent {
  final int serverSeq;
  final int roomSeq;
  final String packetId;
  final String roomId;
  final String kind;
  final String priority;
  final String fromProfileId;
  final String fromDeviceId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, dynamic> crypto;

  const StoredEvent({
    required this.serverSeq,
    required this.roomSeq,
    required this.packetId,
    required this.roomId,
    required this.kind,
    required this.priority,
    required this.fromProfileId,
    required this.fromDeviceId,
    required this.createdAt,
    required this.expiresAt,
    required this.crypto,
  });

  factory StoredEvent.fromJson(Map<String, dynamic> json) => StoredEvent(
        serverSeq: int.tryParse(json['serverSeq']?.toString() ?? '') ?? 0,
        roomSeq: int.tryParse(json['roomSeq']?.toString() ?? '') ?? 0,
        packetId: json['packetId']?.toString() ?? '',
        roomId: json['roomId']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        priority: json['priority']?.toString() ?? 'normal',
        fromProfileId: json['fromProfileId']?.toString() ?? '',
        fromDeviceId: json['fromDeviceId']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        crypto: json['crypto'] is Map
            ? Map<String, dynamic>.from(json['crypto'] as Map)
            : const <String, dynamic>{},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'serverSeq': serverSeq,
        'roomSeq': roomSeq,
        'packetId': packetId,
        'roomId': roomId,
        'kind': kind,
        'priority': priority,
        'fromProfileId': fromProfileId,
        'fromDeviceId': fromDeviceId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'crypto': crypto,
      };

  Map<String, dynamic> toClientFrame({bool replay = false}) =>
      <String, dynamic>{
        'type': 'event',
        'protocol': 1,
        'packetId': packetId,
        'roomId': roomId,
        'kind': kind,
        'priority': priority,
        'serverSeq': serverSeq,
        'roomSeq': roomSeq,
        'fromProfileId': fromProfileId,
        'fromDeviceId': fromDeviceId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'crypto': crypto,
        if (replay) 'replay': true,
      };
}

class AppendResult {
  final StoredEvent event;
  final bool duplicate;

  const AppendResult(this.event, {required this.duplicate});
}

class EventStore {
  final Directory directory;
  final Map<String, List<StoredEvent>> _eventsByRoom =
      <String, List<StoredEvent>>{};
  final Map<String, StoredEvent> _eventsByPacketId = <String, StoredEvent>{};
  final Map<String, int> _lastRoomSeq = <String, int>{};
  late final File _journal;
  int _lastServerSeq = 0;
  Future<void> _writeTail = Future<void>.value();

  EventStore(this.directory);

  Future<void> initialize() async {
    await directory.create(recursive: true);
    _journal = File(
      '${directory.path}${Platform.pathSeparator}events-v1.jsonl',
    );
    if (!await _journal.exists()) return;

    final now = DateTime.now().toUtc();
    await for (final line in _journal
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final event = StoredEvent.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (!_valid(event) || !event.expiresAt.isAfter(now)) continue;
        _remember(event);
      } catch (_) {
        // Ignore an incomplete final journal line after an interrupted write.
      }
    }
  }

  Future<AppendResult> append({
    required String packetId,
    required String roomId,
    required String kind,
    required String priority,
    required String fromProfileId,
    required String fromDeviceId,
    required DateTime createdAt,
    required Duration ttl,
    required Map<String, dynamic> crypto,
  }) async {
    final duplicate = _eventsByPacketId[packetId];
    if (duplicate != null) return AppendResult(duplicate, duplicate: true);

    final event = StoredEvent(
      serverSeq: ++_lastServerSeq,
      roomSeq: (_lastRoomSeq[roomId] ?? 0) + 1,
      packetId: packetId,
      roomId: roomId,
      kind: kind,
      priority: priority,
      fromProfileId: fromProfileId,
      fromDeviceId: fromDeviceId,
      createdAt: createdAt,
      expiresAt: createdAt.add(ttl),
      crypto: Map<String, dynamic>.unmodifiable(crypto),
    );
    _remember(event);
    final line = '${jsonEncode(event.toJson())}\n';
    _writeTail = _writeTail.then((_) async {
      await _journal.writeAsString(
        line,
        mode: FileMode.append,
        flush: true,
      );
    });
    await _writeTail;
    return AppendResult(event, duplicate: false);
  }

  List<StoredEvent> eventsAfter(String roomId, int roomSeq) {
    final now = DateTime.now().toUtc();
    return (_eventsByRoom[roomId] ?? const <StoredEvent>[])
        .where((event) =>
            event.roomSeq > roomSeq && event.expiresAt.isAfter(now))
        .toList(growable: false);
  }

  StoredEvent? find(String packetId) => _eventsByPacketId[packetId];

  void cleanupExpired() {
    final now = DateTime.now().toUtc();
    final expiredIds = _eventsByPacketId.entries
        .where((entry) => !entry.value.expiresAt.isAfter(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in expiredIds) {
      final event = _eventsByPacketId.remove(id);
      if (event == null) continue;
      _eventsByRoom[event.roomId]
          ?.removeWhere((candidate) => candidate.packetId == id);
    }
  }

  bool _valid(StoredEvent event) =>
      event.serverSeq > 0 &&
      event.roomSeq > 0 &&
      event.packetId.isNotEmpty &&
      event.roomId.isNotEmpty &&
      event.crypto.isNotEmpty;

  void _remember(StoredEvent event) {
    if (!_valid(event) || _eventsByPacketId.containsKey(event.packetId)) return;
    _eventsByPacketId[event.packetId] = event;
    (_eventsByRoom[event.roomId] ??= <StoredEvent>[]).add(event);
    _lastServerSeq = max(_lastServerSeq, event.serverSeq);
    _lastRoomSeq[event.roomId] = max(
      _lastRoomSeq[event.roomId] ?? 0,
      event.roomSeq,
    );
  }
}

class ClientSession {
  final String sessionId;
  final String profileId;
  final String deviceId;
  final WebSocket socket;
  final Set<String> rooms;
  final Map<String, int> cursors;
  DateTime lastActivity;

  ClientSession({
    required this.sessionId,
    required this.profileId,
    required this.deviceId,
    required this.socket,
    required this.rooms,
    required this.cursors,
  }) : lastActivity = DateTime.now().toUtc();

  void send(Map<String, dynamic> frame) {
    if (socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(frame));
  }
}

class RealtimeGateway {
  final GatewayConfig config;
  final EventStore store;
  final AccessTokenVerifier tokenVerifier;
  final Map<String, ClientSession> _sessions = <String, ClientSession>{};
  final Map<String, Set<String>> _roomSessions = <String, Set<String>>{};
  HttpServer? _server;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;

  RealtimeGateway({
    required this.config,
    required this.store,
    required this.tokenVerifier,
  });

  Future<void> start() async {
    _server = await HttpServer.bind(config.bindAddress, config.port);
    stdout.writeln(
      'Cernogram realtime gateway listening on '
      '${config.bindAddress.address}:${config.port}',
    );
    _heartbeatTimer = Timer.periodic(
      config.heartbeatInterval,
      (_) => _heartbeat(),
    );
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => store.cleanupExpired(),
    );
    ProcessSignal.sigterm.watch().listen((_) => unawaited(close()));
    ProcessSignal.sigint.watch().listen((_) => unawaited(close()));

    await for (final request in _server!) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/healthz') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, dynamic>{
          'ok': true,
          'sessions': _sessions.length,
          'time': DateTime.now().toUtc().toIso8601String(),
        }));
      await request.response.close();
      return;
    }
    if (request.uri.path != '/v1/realtime' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = config.heartbeatInterval;
      unawaited(_serveSocket(socket));
    } catch (error, stackTrace) {
      stderr.writeln('WebSocket upgrade failed: $error\n$stackTrace');
    }
  }

  Future<void> _serveSocket(WebSocket socket) async {
    final iterator = StreamIterator<dynamic>(socket);
    ClientSession? session;
    try {
      final hasHello = await iterator
          .moveNext()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!hasHello) {
        await socket.close(WebSocketStatus.policyViolation, 'hello required');
        return;
      }
      final hello = _decodeFrame(iterator.current);
      session = await _acceptHello(socket, hello);
      if (session == null) return;

      while (await iterator.moveNext()) {
        final raw = iterator.current;
        if (raw is String && utf8.encode(raw).length > config.maxFrameBytes) {
          await socket.close(WebSocketStatus.messageTooBig, 'frame too large');
          break;
        }
        final frame = _decodeFrame(raw);
        if (frame == null) continue;
        session.lastActivity = DateTime.now().toUtc();
        await _handleFrame(session, frame);
      }
    } catch (error, stackTrace) {
      stderr.writeln('Session error: $error\n$stackTrace');
    } finally {
      await iterator.cancel();
      if (session != null) _removeSession(session);
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<ClientSession?> _acceptHello(
    WebSocket socket,
    Map<String, dynamic>? hello,
  ) async {
    if (hello == null ||
        hello['type'] != 'hello' ||
        hello['protocol'] != 1) {
      await socket.close(WebSocketStatus.policyViolation, 'invalid hello');
      return null;
    }
    final profileId = hello['profileId']?.toString().trim() ?? '';
    final deviceId = hello['deviceId']?.toString().trim() ?? '';
    final token = hello['accessToken']?.toString() ?? '';
    final claims = await tokenVerifier.verify(token);
    final developmentWildcard = claims?.profileId == '*' && claims?.deviceId == '*';
    if (claims == null ||
        profileId.isEmpty ||
        deviceId.isEmpty ||
        (!developmentWildcard &&
            (claims.profileId != profileId || claims.deviceId != deviceId))) {
      await socket.close(WebSocketStatus.policyViolation, 'unauthorized');
      return null;
    }

    final rooms = <String>{};
    final cursors = <String, int>{};
    final rawRooms = hello['rooms'];
    if (rawRooms is List) {
      for (final raw in rawRooms.whereType<Map>()) {
        if (rooms.length >= config.maxRoomsPerClient) break;
        final room = Map<String, dynamic>.from(raw);
        final roomId = room['roomId']?.toString().trim() ?? '';
        if (!_validId(roomId)) continue;
        rooms.add(roomId);
        cursors[roomId] =
            max(0, int.tryParse(room['lastRoomSeq']?.toString() ?? '') ?? 0);
      }
    }

    final session = ClientSession(
      sessionId: _randomId(18),
      profileId: profileId,
      deviceId: deviceId,
      socket: socket,
      rooms: rooms,
      cursors: cursors,
    );
    _sessions[session.sessionId] = session;
    for (final roomId in rooms) {
      (_roomSessions[roomId] ??= <String>{}).add(session.sessionId);
    }

    session.send(<String, dynamic>{
      'type': 'hello_ack',
      'protocol': 1,
      'requestId': hello['requestId'],
      'sessionId': session.sessionId,
      'serverTime': DateTime.now().toUtc().toIso8601String(),
      'heartbeatSeconds': config.heartbeatInterval.inSeconds,
      'maxFrameBytes': config.maxFrameBytes,
    });
    for (final roomId in rooms) {
      _replay(session, roomId, cursors[roomId] ?? 0);
      _broadcastPresence(roomId);
    }
    return session;
  }

  Future<void> _handleFrame(
    ClientSession session,
    Map<String, dynamic> frame,
  ) async {
    switch (frame['type']) {
      case 'event':
        await _handleEvent(session, frame);
        return;
      case 'event_ack':
        _handleRecipientAck(session, frame);
        return;
      case 'subscribe':
        _handleSubscribe(session, frame);
        return;
      case 'unsubscribe':
        _handleUnsubscribe(session, frame);
        return;
      case 'ping':
        session.send(<String, dynamic>{
          'type': 'pong',
          'requestId': frame['requestId'],
          'serverTime': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      case 'pong':
        return;
      default:
        session.send(<String, dynamic>{
          'type': 'error',
          'requestId': frame['requestId'],
          'code': 'unsupported_frame',
        });
    }
  }

  Future<void> _handleEvent(
    ClientSession session,
    Map<String, dynamic> frame,
  ) async {
    final packetId = frame['packetId']?.toString().trim() ?? '';
    final roomId = frame['roomId']?.toString().trim() ?? '';
    final kind = frame['kind']?.toString().trim() ?? '';
    final priority = frame['priority']?.toString().trim() ?? 'normal';
    final crypto = frame['crypto'];
    if (!_validId(packetId) ||
        !_validId(roomId) ||
        !session.rooms.contains(roomId) ||
        !_allowedKind(kind) ||
        crypto is! Map ||
        crypto.isEmpty) {
      session.send(<String, dynamic>{
        'type': 'error',
        'requestId': frame['requestId'],
        'code': 'invalid_event',
      });
      return;
    }

    final createdAt = DateTime.tryParse(frame['createdAt']?.toString() ?? '')
            ?.toUtc() ??
        DateTime.now().toUtc();
    final maxTtl = kind == 'signal'
        ? const Duration(minutes: 2)
        : kind == 'presence'
            ? const Duration(seconds: 45)
            : const Duration(days: 7);
    final requestedTtl = Duration(
      seconds: int.tryParse(frame['ttlSeconds']?.toString() ?? '') ??
          maxTtl.inSeconds,
    );
    final ttl = requestedTtl > maxTtl || requestedTtl <= Duration.zero
        ? maxTtl
        : requestedTtl;

    final result = await store.append(
      packetId: packetId,
      roomId: roomId,
      kind: kind,
      priority: priority,
      fromProfileId: session.profileId,
      fromDeviceId: session.deviceId,
      createdAt: createdAt,
      ttl: ttl,
      crypto: Map<String, dynamic>.from(crypto),
    );
    session.send(<String, dynamic>{
      'type': 'event_ack',
      'protocol': 1,
      'requestId': frame['requestId'],
      'packetId': packetId,
      'roomId': roomId,
      'roomSeq': result.event.roomSeq,
      'serverSeq': result.event.serverSeq,
      'status': result.duplicate ? 'duplicate' : 'stored',
      'storedAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (!result.duplicate) {
      _broadcastEvent(result.event, excludingSessionId: session.sessionId);
    }
  }

  void _handleRecipientAck(
    ClientSession session,
    Map<String, dynamic> frame,
  ) {
    final packetId = frame['packetId']?.toString() ?? '';
    final event = store.find(packetId);
    if (event == null || !session.rooms.contains(event.roomId)) return;
    for (final target in _sessions.values) {
      if (target.profileId != event.fromProfileId) continue;
      target.send(<String, dynamic>{
        'type': 'delivery',
        'packetId': event.packetId,
        'roomId': event.roomId,
        'state': 'delivered',
        'byProfileId': session.profileId,
        'byDeviceId': session.deviceId,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  void _handleSubscribe(
    ClientSession session,
    Map<String, dynamic> frame,
  ) {
    final roomId = frame['roomId']?.toString().trim() ?? '';
    if (!_validId(roomId) ||
        session.rooms.length >= config.maxRoomsPerClient) {
      return;
    }
    session.rooms.add(roomId);
    final cursor = max(
      0,
      int.tryParse(frame['lastRoomSeq']?.toString() ?? '') ?? 0,
    );
    session.cursors[roomId] = cursor;
    (_roomSessions[roomId] ??= <String>{}).add(session.sessionId);
    _replay(session, roomId, cursor);
    _broadcastPresence(roomId);
  }

  void _handleUnsubscribe(
    ClientSession session,
    Map<String, dynamic> frame,
  ) {
    final roomId = frame['roomId']?.toString().trim() ?? '';
    session.rooms.remove(roomId);
    session.cursors.remove(roomId);
    _roomSessions[roomId]?.remove(session.sessionId);
    if (_roomSessions[roomId]?.isEmpty == true) _roomSessions.remove(roomId);
    _broadcastPresence(roomId);
  }

  void _replay(ClientSession session, String roomId, int cursor) {
    for (final event in store.eventsAfter(roomId, cursor)) {
      session.send(event.toClientFrame(replay: true));
    }
  }

  void _broadcastEvent(
    StoredEvent event, {
    String? excludingSessionId,
  }) {
    final sessionIds = _roomSessions[event.roomId];
    if (sessionIds == null) return;
    for (final sessionId in sessionIds) {
      if (sessionId == excludingSessionId) continue;
      _sessions[sessionId]?.send(event.toClientFrame());
    }
  }

  void _broadcastPresence(String roomId) {
    if (roomId.isEmpty) return;
    final sessionIds = _roomSessions[roomId] ?? const <String>{};
    final members = sessionIds
        .map((id) => _sessions[id])
        .whereType<ClientSession>()
        .map((session) => <String, dynamic>{
              'profileId': session.profileId,
              'deviceId': session.deviceId,
              'sessionId': session.sessionId,
              'online': true,
            })
        .toList(growable: false);
    final frame = <String, dynamic>{
      'type': 'presence',
      'roomId': roomId,
      'members': members,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    for (final sessionId in sessionIds) {
      _sessions[sessionId]?.send(frame);
    }
  }

  void _heartbeat() {
    final now = DateTime.now().toUtc();
    final stale = <ClientSession>[];
    for (final session in _sessions.values) {
      if (now.difference(session.lastActivity) > config.staleClientTimeout) {
        stale.add(session);
        continue;
      }
      session.send(<String, dynamic>{
        'type': 'server_ping',
        'serverTime': now.toIso8601String(),
      });
    }
    for (final session in stale) {
      unawaited(session.socket.close(WebSocketStatus.goingAway, 'stale'));
      _removeSession(session);
    }
  }

  void _removeSession(ClientSession session) {
    if (_sessions.remove(session.sessionId) == null) return;
    for (final roomId in session.rooms) {
      _roomSessions[roomId]?.remove(session.sessionId);
      if (_roomSessions[roomId]?.isEmpty == true) _roomSessions.remove(roomId);
      _broadcastPresence(roomId);
    }
  }

  Map<String, dynamic>? _decodeFrame(dynamic raw) {
    if (raw is! String) return null;
    if (utf8.encode(raw).length > config.maxFrameBytes) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  bool _validId(String value) =>
      value.isNotEmpty && value.length <= 160 && RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(value);

  bool _allowedKind(String value) => const <String>{
        'message',
        'control',
        'signal',
        'presence',
        'receipt',
      }.contains(value);

  Future<void> close() async {
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    final server = _server;
    _server = null;
    await server?.close(force: false);
    for (final session in _sessions.values.toList(growable: false)) {
      try {
        await session.socket.close(WebSocketStatus.goingAway, 'shutdown');
      } catch (_) {}
    }
    _sessions.clear();
    _roomSessions.clear();
  }
}

String _randomId(int byteCount) {
  final random = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(byteCount, (_) => random.nextInt(256)),
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}
