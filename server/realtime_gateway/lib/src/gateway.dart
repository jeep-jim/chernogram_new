import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'store.dart';
import 'token.dart';

class GatewayConfig {
  final InternetAddress address;
  final int port;
  final Directory dataDirectory;
  final String signingSecret;
  final bool allowAnonymousDevelopment;
  final int maxFrameBytes;
  final int heartbeatSeconds;

  const GatewayConfig({
    required this.address,
    required this.port,
    required this.dataDirectory,
    required this.signingSecret,
    required this.allowAnonymousDevelopment,
    this.maxFrameBytes = 65536,
    this.heartbeatSeconds = 20,
  });
}

class CernogramGateway {
  final GatewayConfig config;
  late final GatewayJsonStore store = GatewayJsonStore(config.dataDirectory);
  GatewayTokenCodec? _tokenCodec;
  HttpServer? _server;
  final Set<_ClientSession> _clients = <_ClientSession>{};
  final Map<String, Set<_ClientSession>> _roomMembers =
      <String, Set<_ClientSession>>{};
  final String _instanceId = _randomId(12);

  CernogramGateway(this.config) {
    if (config.signingSecret.isNotEmpty) {
      _tokenCodec = GatewayTokenCodec(config.signingSecret);
    }
  }

  Future<void> start() async {
    await store.initialize();
    _server = await HttpServer.bind(config.address, config.port, shared: true);
    _server!.listen(
      (request) => unawaited(_handleHttp(request)),
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('gateway_http_error: $error');
      },
    );
  }

  Future<void> stop() async {
    for (final client in _clients.toList()) {
      await client.socket.close(WebSocketStatus.goingAway, 'server_shutdown');
    }
    _clients.clear();
    _roomMembers.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleHttp(HttpRequest request) async {
    if (request.method == 'GET' && request.uri.path == '/health') {
      final stats = await store.stats();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, dynamic>{
          'ok': true,
          'service': 'cernogram-realtime-gateway',
          'instanceId': _instanceId,
          'clients': _clients.length,
          'roomsOnline': _roomMembers.length,
          'store': stats.toJson(),
          'time': DateTime.now().toUtc().toIso8601String(),
        }));
      await request.response.close();
      return;
    }

    if (request.method == 'GET' &&
        request.uri.path == '/v1/realtime' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = Duration(seconds: config.heartbeatSeconds);
      _attach(socket);
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(<String, dynamic>{
        'error': 'not_found',
        'path': request.uri.path,
      }));
    await request.response.close();
  }

  void _attach(WebSocket socket) {
    final client = _ClientSession(socket);
    _clients.add(client);
    socket.listen(
      (raw) {
        client.serial = client.serial
            .then((_) => _handleFrame(client, raw))
            .catchError((Object error, StackTrace stackTrace) {
          _sendError(client, 'frame_processing_failed', error.toString());
        });
      },
      onDone: () => unawaited(_detach(client)),
      onError: (_) => unawaited(_detach(client)),
      cancelOnError: true,
    );
  }

  Future<void> _handleFrame(_ClientSession client, dynamic raw) async {
    if (raw is! String) {
      await client.socket.close(
        WebSocketStatus.unsupportedData,
        'text_frames_only',
      );
      return;
    }
    if (utf8.encode(raw).length > config.maxFrameBytes) {
      await client.socket
          .close(WebSocketStatus.messageTooBig, 'frame_too_large');
      return;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      _sendError(client, 'invalid_frame', 'JSON object expected');
      return;
    }
    final frame = Map<String, dynamic>.from(decoded);
    final type = frame['type']?.toString() ?? '';
    if (!client.authenticated && type != 'hello') {
      _sendError(client, 'hello_required', 'Send hello before other frames');
      return;
    }

    switch (type) {
      case 'hello':
        await _handleHello(client, frame);
        return;
      case 'event':
        await _handleEvent(client, frame);
        return;
      case 'ack':
        await _handleAck(client, frame);
        return;
      case 'subscribe':
        await _handleSubscribe(client, frame);
        return;
      case 'unsubscribe':
        await _handleUnsubscribe(client, frame);
        return;
      case 'ping':
        _send(client, <String, dynamic>{
          'type': 'pong',
          'protocol': 1,
          'requestId': frame['requestId'],
          'serverTime': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      default:
        _sendError(client, 'unsupported_type', type);
        return;
    }
  }

  Future<void> _handleHello(
    _ClientSession client,
    Map<String, dynamic> frame,
  ) async {
    if (client.authenticated) {
      _sendError(client, 'already_authenticated', 'hello already accepted');
      return;
    }
    if (frame['protocol'] != 1) {
      _sendError(
        client,
        'unsupported_protocol',
        frame['protocol']?.toString() ?? '',
      );
      return;
    }

    GatewayIdentity identity;
    final accessToken = frame['accessToken']?.toString() ?? '';
    if (accessToken.isNotEmpty) {
      final codec = _tokenCodec;
      if (codec == null) {
        _sendError(
          client,
          'token_verification_unavailable',
          'server secret missing',
        );
        return;
      }
      try {
        identity = codec.verify(accessToken);
      } on FormatException catch (error) {
        _sendError(client, 'authentication_failed', error.message.toString());
        await client.socket.close(
          WebSocketStatus.policyViolation,
          'authentication_failed',
        );
        return;
      }
    } else if (config.allowAnonymousDevelopment) {
      final profileId = frame['profileId']?.toString().trim() ?? '';
      final deviceId = frame['deviceId']?.toString().trim() ?? '';
      if (profileId.isEmpty || deviceId.isEmpty) {
        _sendError(
          client,
          'identity_required',
          'profileId and deviceId required',
        );
        return;
      }
      identity = GatewayIdentity(
        profileId: profileId,
        deviceId: deviceId,
        allowedRooms: const <String>{'*'},
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      );
    } else {
      _sendError(
        client,
        'access_token_required',
        'anonymous access disabled',
      );
      await client.socket.close(
        WebSocketStatus.policyViolation,
        'access_token_required',
      );
      return;
    }

    final suppliedProfile = frame['profileId']?.toString().trim() ?? '';
    final suppliedDevice = frame['deviceId']?.toString().trim() ?? '';
    if ((suppliedProfile.isNotEmpty && suppliedProfile != identity.profileId) ||
        (suppliedDevice.isNotEmpty && suppliedDevice != identity.deviceId)) {
      _sendError(
        client,
        'identity_mismatch',
        'token identity differs from hello',
      );
      await client.socket.close(
        WebSocketStatus.policyViolation,
        'identity_mismatch',
      );
      return;
    }

    client.identity = identity;
    final rooms = ((frame['rooms'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    for (final room in rooms) {
      final roomId = room['roomId']?.toString().trim() ?? '';
      if (roomId.isEmpty || !identity.canAccess(roomId)) continue;
      client.rooms.add(roomId);
      _roomMembers.putIfAbsent(roomId, () => <_ClientSession>{}).add(client);
    }

    _send(client, <String, dynamic>{
      'type': 'hello_ack',
      'protocol': 1,
      'requestId': frame['requestId'],
      'sessionId': client.sessionId,
      'instanceId': _instanceId,
      'serverTime': DateTime.now().toUtc().toIso8601String(),
      'heartbeatSeconds': config.heartbeatSeconds,
      'maxFrameBytes': config.maxFrameBytes,
    });

    for (final room in rooms) {
      final roomId = room['roomId']?.toString().trim() ?? '';
      if (!client.rooms.contains(roomId)) continue;
      final requestedCursor =
          int.tryParse(room['lastRoomSeq']?.toString() ?? '') ?? 0;
      final storedCursor = await store.loadCursor(
        profileId: identity.profileId,
        deviceId: identity.deviceId,
        roomId: roomId,
      );
      final cursor = max(requestedCursor, storedCursor);
      final replay = await store.readAfter(roomId, cursor);
      for (final event in replay) {
        _send(client, _eventFrame(event, replay: true));
      }
      _send(client, <String, dynamic>{
        'type': 'replay_complete',
        'protocol': 1,
        'roomId': roomId,
        'afterRoomSeq': cursor,
        'events': replay.length,
      });
      _broadcastPresence(roomId);
    }
  }

  Future<void> _handleEvent(
    _ClientSession client,
    Map<String, dynamic> frame,
  ) async {
    final identity = client.identity!;
    final roomId = frame['roomId']?.toString().trim() ?? '';
    final packetId = frame['packetId']?.toString().trim() ?? '';
    final kind = frame['kind']?.toString().trim() ?? 'message';
    final priority = frame['priority']?.toString().trim() ?? 'normal';
    final crypto = frame['crypto'];
    if (roomId.isEmpty || packetId.isEmpty || crypto is! Map) {
      _sendError(
        client,
        'invalid_event',
        'roomId, packetId and crypto required',
      );
      return;
    }
    if (!client.rooms.contains(roomId) || !identity.canAccess(roomId)) {
      _sendError(client, 'room_access_denied', roomId);
      return;
    }
    final cryptoMap = Map<String, dynamic>.from(crypto);
    if ((cryptoMap['ciphertext']?.toString() ?? '').isEmpty ||
        (cryptoMap['nonce']?.toString() ?? '').isEmpty ||
        (cryptoMap['mac']?.toString() ?? '').isEmpty) {
      _sendError(client, 'invalid_crypto_envelope', packetId);
      return;
    }

    final createdAt =
        DateTime.tryParse(frame['createdAt']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc();
    final requestedTtl = int.tryParse(frame['ttlSeconds']?.toString() ?? '') ??
        const Duration(days: 7).inSeconds;
    final ttlSeconds =
        requestedTtl.clamp(5, const Duration(days: 30).inSeconds).toInt();
    final result = await store.append(
      roomId: roomId,
      packetId: packetId,
      senderProfileId: identity.profileId,
      senderDeviceId: identity.deviceId,
      kind: kind,
      priority: priority,
      createdAt: createdAt,
      ttl: Duration(seconds: ttlSeconds),
      crypto: cryptoMap,
    );

    _send(client, <String, dynamic>{
      'type': 'event_ack',
      'protocol': 1,
      'requestId': frame['requestId'],
      'packetId': result.event.packetId,
      'roomId': result.event.roomId,
      'roomSeq': result.event.roomSeq,
      'serverSeq': result.event.serverSeq,
      'duplicate': result.duplicate,
      'storedAt': DateTime.now().toUtc().toIso8601String(),
    });

    if (!result.duplicate) {
      final outgoing = _eventFrame(result.event, replay: false);
      final members =
          _roomMembers[roomId]?.toList() ?? const <_ClientSession>[];
      for (final member in members) {
        if (identical(member, client)) continue;
        _send(member, outgoing);
      }
    }
  }

  Future<void> _handleAck(
    _ClientSession client,
    Map<String, dynamic> frame,
  ) async {
    final identity = client.identity!;
    final roomId = frame['roomId']?.toString().trim() ?? '';
    final roomSeq = int.tryParse(frame['roomSeq']?.toString() ?? '') ?? 0;
    if (roomId.isEmpty || roomSeq <= 0 || !client.rooms.contains(roomId)) {
      return;
    }
    await store.saveCursor(
      profileId: identity.profileId,
      deviceId: identity.deviceId,
      roomId: roomId,
      roomSeq: roomSeq,
    );
  }

  Future<void> _handleSubscribe(
    _ClientSession client,
    Map<String, dynamic> frame,
  ) async {
    final roomId = frame['roomId']?.toString().trim() ?? '';
    final identity = client.identity!;
    if (roomId.isEmpty || !identity.canAccess(roomId)) {
      _sendError(client, 'room_access_denied', roomId);
      return;
    }
    client.rooms.add(roomId);
    _roomMembers.putIfAbsent(roomId, () => <_ClientSession>{}).add(client);
    final requestedCursor =
        int.tryParse(frame['lastRoomSeq']?.toString() ?? '') ?? 0;
    final storedCursor = await store.loadCursor(
      profileId: identity.profileId,
      deviceId: identity.deviceId,
      roomId: roomId,
    );
    final replay = await store.readAfter(
      roomId,
      max(requestedCursor, storedCursor),
    );
    for (final event in replay) {
      _send(client, _eventFrame(event, replay: true));
    }
    _broadcastPresence(roomId);
  }

  Future<void> _handleUnsubscribe(
    _ClientSession client,
    Map<String, dynamic> frame,
  ) async {
    final roomId = frame['roomId']?.toString().trim() ?? '';
    if (roomId.isEmpty) return;
    client.rooms.remove(roomId);
    final members = _roomMembers[roomId];
    members?.remove(client);
    if (members?.isEmpty == true) _roomMembers.remove(roomId);
    _broadcastPresence(roomId);
  }

  Map<String, dynamic> _eventFrame(
    StoredGatewayEvent event, {
    required bool replay,
  }) {
    return <String, dynamic>{
      'type': 'event',
      'protocol': 1,
      'serverSeq': event.serverSeq,
      'roomSeq': event.roomSeq,
      'roomId': event.roomId,
      'packetId': event.packetId,
      'senderProfileId': event.senderProfileId,
      'senderDeviceId': event.senderDeviceId,
      'kind': event.kind,
      'priority': event.priority,
      'createdAt': event.createdAt.toUtc().toIso8601String(),
      'expiresAt': event.expiresAt.toUtc().toIso8601String(),
      'crypto': event.crypto,
      'replay': replay,
    };
  }

  void _broadcastPresence(String roomId) {
    final members = _roomMembers[roomId]
            ?.where((member) => member.authenticated)
            .toList() ??
        const <_ClientSession>[];
    final profiles = <String, int>{};
    for (final member in members) {
      final profileId = member.identity!.profileId;
      profiles[profileId] = (profiles[profileId] ?? 0) + 1;
    }
    final frame = <String, dynamic>{
      'type': 'presence',
      'protocol': 1,
      'roomId': roomId,
      'onlineProfiles': profiles.length,
      'onlineDevices': members.length,
      'members': profiles.entries
          .map(
            (entry) => <String, dynamic>{
              'profileId': entry.key,
              'devices': entry.value,
            },
          )
          .toList(),
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    for (final member in members) {
      _send(member, frame);
    }
  }

  Future<void> _detach(_ClientSession client) async {
    if (!_clients.remove(client)) return;
    for (final roomId in client.rooms.toList()) {
      final members = _roomMembers[roomId];
      members?.remove(client);
      if (members?.isEmpty == true) _roomMembers.remove(roomId);
      _broadcastPresence(roomId);
    }
    client.rooms.clear();
  }

  void _send(_ClientSession client, Map<String, dynamic> frame) {
    if (client.socket.readyState != WebSocket.open) return;
    final encoded = jsonEncode(frame);
    if (utf8.encode(encoded).length > config.maxFrameBytes) {
      _sendError(
        client,
        'server_frame_too_large',
        frame['type']?.toString() ?? '',
      );
      return;
    }
    client.socket.add(encoded);
  }

  void _sendError(_ClientSession client, String code, String details) {
    if (client.socket.readyState != WebSocket.open) return;
    client.socket.add(jsonEncode(<String, dynamic>{
      'type': 'error',
      'protocol': 1,
      'code': code,
      'details': details,
      'serverTime': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  static String _randomId(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

class _ClientSession {
  final WebSocket socket;
  final String sessionId = CernogramGateway._randomId(24);
  final Set<String> rooms = <String>{};
  Future<void> serial = Future<void>.value();
  GatewayIdentity? identity;

  _ClientSession(this.socket);

  bool get authenticated => identity != null;
}
