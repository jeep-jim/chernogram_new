import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

import 'core_models.dart';
import 'legacy_ntfy_transport.dart' as legacy;
import 'realtime_gateway_client.dart';
import 'realtime_gateway_config.dart';
import 'realtime_gateway_models.dart';

class InternetEvent {
  final String type;
  final Map<String, dynamic> data;

  const InternetEvent(this.type, [this.data = const <String, dynamic>{}]);
}

class _RoomCipher {
  final String tunnelId;
  final String secret;
  SecretKey? _key;

  _RoomCipher(this.tunnelId, this.secret);

  Future<SecretKey> _resolveKey() async {
    final cached = _key;
    if (cached != null) return cached;
    final hash = await Sha256().hash(utf8.encode('$tunnelId:$secret'));
    final key = SecretKey(hash.bytes);
    _key = key;
    return key;
  }

  Future<Map<String, dynamic>> encrypt(Map<String, dynamic> payload) async {
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: await _resolveKey(),
      nonce: nonce,
    );
    return <String, dynamic>{
      'algorithm': 'AES-256-GCM',
      'keyVersion': 1,
      'nonce': base64Url.encode(box.nonce),
      'ciphertext': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>?> decrypt(Map<String, dynamic> crypto) async {
    try {
      final nonce = base64Url.decode(
        base64Url.normalize(crypto['nonce']?.toString() ?? ''),
      );
      final cipherText = base64Url.decode(
        base64Url.normalize(crypto['ciphertext']?.toString() ?? ''),
      );
      final mac = base64Url.decode(
        base64Url.normalize(crypto['mac']?.toString() ?? ''),
      );
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: await _resolveKey(),
      );
      final decoded = jsonDecode(utf8.decode(clear));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

class _GatewayHub {
  static final Map<String, Future<_GatewayHub>> _instances =
      <String, Future<_GatewayHub>>{};

  static Future<_GatewayHub> acquire({
    required String profileId,
    required String nickname,
  }) => _instances.putIfAbsent(profileId, () async {
    final config = await CgRealtimeGatewayConfig.load();
    return _GatewayHub._(
      profileId: profileId,
      nickname: nickname,
      config: config,
    );
  });

  final String profileId;
  String nickname;
  final CgRealtimeGatewayConfig config;
  final Map<String, InternetTunnelSession> _rooms =
      <String, InternetTunnelSession>{};

  CgRealtimeGatewayClient? _client;
  StreamSubscription<CgGatewayEvent>? _eventSubscription;
  StreamSubscription<CgGatewayPresence>? _presenceSubscription;
  StreamSubscription<CgRealtimeGatewayStatus>? _statusSubscription;
  bool _initialized = false;
  bool _closed = false;

  _GatewayHub._({
    required this.profileId,
    required this.nickname,
    required this.config,
  });

  bool get enabled => config.enabled && config.uri != null;
  bool get connected => _client?.connected == true;
  String get deviceId => config.deviceId;

  Future<void> register(InternetTunnelSession session) async {
    if (_closed) return;
    nickname = session.nickname;
    _rooms[session.tunnelId] = session;
    if (!enabled) return;
    await _ensureClient();
    if (_initialized) {
      await _client!.subscribe(
        CgRealtimeRoomCursor(roomId: session.tunnelId),
      );
    }
  }

  Future<void> unregister(String roomId, InternetTunnelSession session) async {
    if (!identical(_rooms[roomId], session)) return;
    _rooms.remove(roomId);
    if (_initialized) await _client?.unsubscribe(roomId);
  }

  Future<void> _ensureClient() async {
    if (_closed || !enabled || _client != null) return;
    const accessToken = String.fromEnvironment(
      'CG_GATEWAY_ACCESS_TOKEN',
      defaultValue: 'dev',
    );
    final client = CgRealtimeGatewayClient(
      uri: config.uri!,
      profileId: profileId,
      deviceId: config.deviceId,
      accessTokenProvider: () async => accessToken,
    );
    _client = client;
    await client.initialize(
      _rooms.keys.map((roomId) => CgRealtimeRoomCursor(roomId: roomId)),
    );
    _initialized = true;
    _eventSubscription = client.events.listen((event) {
      _rooms[event.roomId]?._handleGatewayEvent(event, config.deviceId);
    });
    _presenceSubscription = client.presence.listen((presence) {
      _rooms[presence.roomId]?._handleGatewayPresence(presence);
    });
    _statusSubscription = client.status.listen((status) {
      for (final room in _rooms.values.toList(growable: false)) {
        room._handleGatewayStatus(status);
      }
    });
  }

  Future<bool> connect({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!enabled || _closed) return false;
    await _ensureClient();
    return _client?.connect(timeout: timeout) ?? false;
  }

  Future<CgGatewayAck?> send({
    required String roomId,
    required String kind,
    required Map<String, dynamic> crypto,
    required String priority,
    required Duration ttl,
    required String packetId,
  }) async {
    if (!enabled || _closed) return null;
    await _ensureClient();
    if (_client?.connected != true) {
      await _client?.connect(timeout: const Duration(seconds: 4));
    }
    return _client?.sendEncrypted(
      roomId: roomId,
      kind: kind,
      crypto: crypto,
      priority: priority,
      ttl: ttl,
      packetId: packetId,
      ackTimeout: kind == 'file_chunk'
          ? const Duration(seconds: 10)
          : const Duration(seconds: 6),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventSubscription?.cancel();
    await _presenceSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _client?.close();
    _rooms.clear();
    _instances.remove(profileId);
  }
}

class InternetTunnelSession {
  static const int _inlineFileChars = 26000;
  static const int _fileChunkChars = 22000;

  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;

  final StreamController<InternetEvent> _events =
      StreamController<InternetEvent>.broadcast(sync: true);
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _signalHistory = <Map<String, dynamic>>[];
  final Set<String> _seenMessages = <String>{};
  final Set<String> _seenSignals = <String>{};
  final Map<String, Map<String, dynamic>> _pendingFileManifests =
      <String, Map<String, dynamic>>{};
  final Map<String, List<String?>> _pendingFileChunks =
      <String, List<String?>>{};
  final Map<String, DateTime> _peers = <String, DateTime>{};
  final Map<String, String> _peerNames = <String, String>{};

  late final _RoomCipher _cipher = _RoomCipher(tunnelId, secret);
  _GatewayHub? _hub;
  legacy.LegacyInternetTunnelSession? _fallback;
  StreamSubscription<legacy.LegacyInternetEvent>? _fallbackSubscription;
  bool _closed = false;
  bool _connecting = false;
  int _onlineDevices = 1;
  List<Map<String, dynamic>> _gatewayMembers = const <Map<String, dynamic>>[];

  InternetTunnelSession({
    required this.tunnelId,
    required this.secret,
    required this.profileId,
    required this.nickname,
  });

  Stream<InternetEvent> get events => _events.stream;
  bool get connected => _hub?.connected == true || _fallback?.connected == true;
  int get onlinePeers => math.max(
    _onlineDevices,
    (_fallback?.onlinePeers ?? 1),
  );
  List<Map<String, dynamic>> get members {
    if (_gatewayMembers.isNotEmpty) return _gatewayMembers;
    final fallback = _fallback;
    if (fallback != null) return fallback.members;
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': profileId,
        'name': nickname,
        'self': true,
        'seenAt': DateTime.now().toUtc().toIso8601String(),
      },
    ];
  }

  Future<void> connect() async {
    if (_closed || _connecting || connected) return;
    _connecting = true;
    try {
      final hub = await _GatewayHub.acquire(
        profileId: profileId,
        nickname: nickname,
      );
      _hub = hub;
      await hub.register(this);
      final gatewayReady = await hub.connect();
      if (!gatewayReady) {
        await _activateFallback();
        _emit('status', const <String, dynamic>{
          'state': 'queued',
          'transport': 'legacy_fallback',
        });
      } else {
        _emit('status', const <String, dynamic>{
          'state': 'connected',
          'transport': 'gateway',
        });
      }
    } finally {
      _connecting = false;
    }
  }

  Future<bool> waitUntilConnected([
    Duration timeout = const Duration(seconds: 5),
  ]) async {
    if (connected) return true;
    unawaited(connect());
    final deadline = DateTime.now().add(timeout);
    while (!_closed && DateTime.now().isBefore(deadline)) {
      if (connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return connected;
  }

  Future<void> _activateFallback() async {
    if (_closed || _fallback != null) return;
    final fallback = await legacy.LegacyInternetRelay.open(
      tunnelId: tunnelId,
      secret: secret,
      profileId: profileId,
      nickname: nickname,
      history: _history,
    );
    _fallback = fallback;
    _fallbackSubscription = fallback.events.listen((event) {
      _handleFallbackEvent(event);
    });
    unawaited(fallback.connect());
  }

  Future<void> _deactivateFallback() async {
    final fallback = _fallback;
    _fallback = null;
    await _fallbackSubscription?.cancel();
    _fallbackSubscription = null;
    await fallback?.close();
  }

  void _handleGatewayStatus(CgRealtimeGatewayStatus status) {
    if (_closed) return;
    if (status.state == 'connected') {
      _emit('status', const <String, dynamic>{
        'state': 'connected',
        'transport': 'gateway',
      });
      if (_fallback != null) unawaited(_deactivateFallback());
    } else if (_fallback == null &&
        (status.state == 'offline' || status.state == 'reconnecting')) {
      unawaited(_activateFallback());
    }
  }

  void _handleGatewayPresence(CgGatewayPresence presence) {
    _onlineDevices = math.max(1, presence.onlineDevices);
    _gatewayMembers = <Map<String, dynamic>>[
      for (final member in presence.members)
        <String, dynamic>{
          'id': member['profileId']?.toString() ?? '',
          'deviceId': member['deviceId']?.toString() ?? '',
          'name': member['profileId']?.toString() == profileId
              ? nickname
              : (_peerNames[member['profileId']?.toString()] ?? 'пользователь'),
          'self': member['profileId']?.toString() == profileId &&
              member['deviceId']?.toString() == _hub?.deviceId,
          'seenAt': presence.at.toIso8601String(),
        },
    ];
    _emit('presence', <String, dynamic>{
      'online': onlinePeers,
      'members': members,
    });
  }

  Future<void> _handleGatewayEvent(
    CgGatewayEvent event,
    String localDeviceId,
  ) async {
    if (_closed || event.senderDeviceId == localDeviceId) return;
    final envelope = await _cipher.decrypt(event.crypto);
    if (envelope == null) return;
    final rawData = envelope['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    final sender = event.senderProfileId;
    final senderName = envelope['name']?.toString() ?? 'пользователь';
    if (sender.isNotEmpty) {
      _peers[sender] = DateTime.now();
      _peerNames[sender] = senderName;
      _emit('peer', <String, dynamic>{
        'id': sender,
        'name': senderName,
        'seenAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    switch (event.kind) {
      case 'message':
      case 'public_index':
        final rawMessage = data['message'];
        if (rawMessage is Map) {
          _receiveMessage(
            Map<String, dynamic>.from(rawMessage),
            sender: sender,
            senderName: senderName,
            source: 'gateway',
          );
        }
        break;
      case 'file_chunk':
        _receiveFileChunk(
          data,
          sender: sender,
          senderName: senderName,
          source: 'gateway',
        );
        break;
      case 'control':
        _emit('control', <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
      case 'signal':
        _receiveSignal(<String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
        });
        break;
      case 'receipt':
        _emit('delivery', data);
        break;
    }
  }

  void _handleFallbackEvent(legacy.LegacyInternetEvent event) {
    if (_closed) return;
    if (event.type == 'message' && event.data['message'] is Map) {
      _receiveMessage(
        Map<String, dynamic>.from(event.data['message'] as Map),
        sender: event.data['relaySender']?.toString() ?? '',
        senderName: event.data['relaySenderName']?.toString() ?? 'пользователь',
        source: 'legacy',
      );
      return;
    }
    if (event.type == 'signal') {
      _receiveSignal(Map<String, dynamic>.from(event.data));
      return;
    }
    _emit(event.type, Map<String, dynamic>.from(event.data));
  }

  void _receiveMessage(
    Map<String, dynamic> message, {
    required String sender,
    required String senderName,
    required String source,
  }) {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final rawMeta = message['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};
    final transferId = meta['fileTransferId']?.toString() ?? '';
    if (transferId.isNotEmpty && meta['fileReady'] != true) {
      _pendingFileManifests[transferId] = message;
      _emitMessage(message, sender, senderName, source);
      _tryCompleteFile(transferId, sender, senderName, source);
      return;
    }
    if (!_seenMessages.add(id)) return;
    if (_seenMessages.length > 10000) _seenMessages.remove(_seenMessages.first);
    _rememberMessage(_sanitizeMessage(message));
    _emitMessage(message, sender, senderName, source);
  }

  void _receiveFileChunk(
    Map<String, dynamic> data, {
    required String sender,
    required String senderName,
    required String source,
  }) {
    final transferId = data['transferId']?.toString() ?? '';
    final index = int.tryParse(data['index']?.toString() ?? '') ?? -1;
    final count = int.tryParse(data['count']?.toString() ?? '') ?? 0;
    final chunk = data['chunk']?.toString() ?? '';
    if (transferId.isEmpty || index < 0 || count <= 0 || chunk.isEmpty) {
      return;
    }
    final chunks = _pendingFileChunks.putIfAbsent(
      transferId,
      () => List<String?>.filled(count, null),
    );
    if (chunks.length != count || index >= chunks.length) return;
    chunks[index] = chunk;
    _emit('file_progress', <String, dynamic>{
      'transferId': transferId,
      'received': chunks.whereType<String>().length,
      'total': count,
    });
    _tryCompleteFile(transferId, sender, senderName, source);
  }

  void _tryCompleteFile(
    String transferId,
    String sender,
    String senderName,
    String source,
  ) {
    final manifest = _pendingFileManifests[transferId];
    final chunks = _pendingFileChunks[transferId];
    if (manifest == null || chunks == null || chunks.any((item) => item == null)) {
      return;
    }
    final rawAttachment = manifest['attachment'];
    if (rawAttachment is! Map) return;
    final attachment = Map<String, dynamic>.from(rawAttachment)
      ..['dataBase64'] = chunks.cast<String>().join();
    manifest['attachment'] = attachment;
    final rawMeta = manifest['meta'];
    manifest['meta'] = <String, dynamic>{
      if (rawMeta is Map) ...Map<String, dynamic>.from(rawMeta),
      'fileReady': true,
    };
    _pendingFileManifests.remove(transferId);
    _pendingFileChunks.remove(transferId);
    final id = manifest['id']?.toString() ?? '';
    if (id.isNotEmpty) _seenMessages.add(id);
    _rememberMessage(_sanitizeMessage(manifest));
    _emitMessage(manifest, sender, senderName, source);
  }

  void _receiveSignal(Map<String, dynamic> signal) {
    final callId = signal['callId']?.toString() ?? '';
    final action = signal['action']?.toString() ?? '';
    final fingerprint = '$callId|$action|${signal['sdp']?.hashCode ?? ''}|${signal['candidate']?.hashCode ?? ''}|${signal['relaySender'] ?? signal['from'] ?? ''}';
    if (!_seenSignals.add(fingerprint)) return;
    if (_seenSignals.length > 2000) _seenSignals.remove(_seenSignals.first);
    _signalHistory.add(Map<String, dynamic>.from(signal));
    if (_signalHistory.length > 300) {
      _signalHistory.removeRange(0, _signalHistory.length - 300);
    }
    _emit('signal', signal);
  }

  void _emitMessage(
    Map<String, dynamic> message,
    String sender,
    String senderName,
    String source,
  ) {
    _emit('message', <String, dynamic>{
      'message': message,
      'relaySender': sender,
      'relaySenderName': senderName,
      'relayHost': source,
    });
  }

  Future<bool> _sendGateway(
    String kind,
    Map<String, dynamic> data, {
    required String priority,
    required Duration ttl,
    required String packetId,
  }) async {
    final hub = _hub;
    if (hub == null || !hub.enabled) return false;
    final crypto = await _cipher.encrypt(<String, dynamic>{
      'name': nickname,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
    final ack = await hub.send(
      roomId: tunnelId,
      kind: kind,
      crypto: crypto,
      priority: priority,
      ttl: ttl,
      packetId: packetId,
    );
    return ack != null;
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberMessage(_sanitizeMessage(message));
    if (_hub == null) await connect();
    final rawAttachment = message['attachment'];
    final attachment = rawAttachment is Map
        ? Map<String, dynamic>.from(rawAttachment)
        : null;
    final payload = attachment?['dataBase64']?.toString();
    var gatewayOk = false;
    if (payload == null || payload.length <= _inlineFileChars) {
      final id = message['id']?.toString() ?? CgIds.random(20);
      gatewayOk = await _sendGateway(
        'message',
        <String, dynamic>{'message': message},
        priority: 'normal',
        ttl: const Duration(days: 30),
        packetId: 'msg_$id',
      );
    } else {
      gatewayOk = await _sendLargeFileMessage(message, payload);
    }
    if (!gatewayOk) {
      await _activateFallback();
      await _fallback?.sendMessage(message);
    }
  }

  Future<bool> _sendLargeFileMessage(
    Map<String, dynamic> message,
    String payload,
  ) async {
    final messageId = message['id']?.toString() ?? CgIds.random(20);
    final transferId = 'file_${messageId}_${payload.length}';
    final count = (payload.length / _fileChunkChars).ceil();
    final manifest = _sanitizeMessage(message);
    final rawMeta = manifest['meta'];
    manifest['meta'] = <String, dynamic>{
      if (rawMeta is Map) ...Map<String, dynamic>.from(rawMeta),
      'fileTransferId': transferId,
      'fileChunkCount': count,
      'fileReady': false,
    };
    final manifestOk = await _sendGateway(
      'message',
      <String, dynamic>{'message': manifest},
      priority: 'bulk',
      ttl: const Duration(days: 30),
      packetId: 'msg_$messageId',
    );
    if (!manifestOk) return false;
    for (var start = 0; start < count; start += 4) {
      final end = math.min(start + 4, count);
      final results = await Future.wait<bool>([
        for (var index = start; index < end; index++)
          _sendGateway(
            'file_chunk',
            <String, dynamic>{
              'transferId': transferId,
              'messageId': messageId,
              'index': index,
              'count': count,
              'chunk': payload.substring(
                index * _fileChunkChars,
                math.min((index + 1) * _fileChunkChars, payload.length),
              ),
            },
            priority: 'bulk',
            ttl: const Duration(days: 30),
            packetId: 'chunk_${transferId}_$index',
          ),
      ]);
      if (results.any((result) => !result)) return false;
    }
    return true;
  }

  Future<void> sendControl(Map<String, dynamic> control) async {
    if (_hub == null) await connect();
    final operationId = control['operationId']?.toString() ??
        '${control['action'] ?? 'control'}_${CgIds.random(16)}';
    final ok = await _sendGateway(
      'control',
      control,
      priority: 'high',
      ttl: const Duration(days: 7),
      packetId: 'ctl_$operationId',
    );
    if (!ok) {
      await _activateFallback();
      await _fallback?.sendControl(control);
    }
  }

  Future<void> sendSignal(Map<String, dynamic> signal) async {
    if (_hub == null) await connect();
    final callId = signal['callId']?.toString() ?? CgIds.random(12);
    final action = signal['action']?.toString() ?? 'signal';
    final packetId = 'sig_${callId}_${action}_${CgIds.random(8)}';
    final ok = await _sendGateway(
      'signal',
      signal,
      priority: 'realtime',
      ttl: const Duration(seconds: 45),
      packetId: packetId,
    );
    if (!ok) {
      await _activateFallback();
      await _fallback?.sendSignal(signal);
    }
  }

  List<Map<String, dynamic>> replaySignals(String callId) {
    if (callId.isEmpty) return const <Map<String, dynamic>>[];
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
    return _signalHistory.where((signal) {
      if (signal['callId']?.toString() != callId) return false;
      final at = DateTime.tryParse(
        signal['receivedAt']?.toString() ?? signal['sentAt']?.toString() ?? '',
      );
      return at == null || !at.toUtc().isBefore(cutoff);
    }).map((signal) => Map<String, dynamic>.from(signal)).toList();
  }

  Future<void> sendHistory() async {
    await _fallback?.sendHistory();
  }

  void replaceHistory(List<Map<String, dynamic>> messages) {
    _history.clear();
    for (final message in messages) {
      _rememberMessage(_sanitizeMessage(message));
    }
    _fallback?.replaceHistory(messages);
  }

  Map<String, dynamic> _sanitizeMessage(Map<String, dynamic> message) {
    final copy = Map<String, dynamic>.from(message);
    final rawAttachment = copy['attachment'];
    if (rawAttachment is Map) {
      copy['attachment'] = Map<String, dynamic>.from(rawAttachment)
        ..remove('dataBase64')
        ..remove('localPath')
        ..remove('path');
    }
    return copy;
  }

  void _rememberMessage(Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final index = _history.indexWhere((item) => item['id']?.toString() == id);
    if (index < 0) {
      _history.add(Map<String, dynamic>.from(message));
    } else {
      _history[index] = Map<String, dynamic>.from(message);
    }
    if (_history.length > 500) {
      _history.removeRange(0, _history.length - 500);
    }
  }

  void _emit(String type, [Map<String, dynamic> data = const <String, dynamic>{}]) {
    if (!_events.isClosed) _events.add(InternetEvent(type, data));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _fallbackSubscription?.cancel();
    await _fallback?.close();
    await _hub?.unregister(tunnelId, this);
    await _events.close();
  }
}

class InternetRelay {
  static final Map<String, InternetTunnelSession> _sessions =
      <String, InternetTunnelSession>{};

  static InternetTunnelSession? session(String tunnelId) => _sessions[tunnelId];

  static Future<InternetTunnelSession> open({
    required String tunnelId,
    required String secret,
    required String profileId,
    required String nickname,
    required List<Map<String, dynamic>> history,
  }) async {
    final existing = _sessions[tunnelId];
    if (existing != null &&
        existing.secret == secret &&
        existing.profileId == profileId) {
      existing.replaceHistory(history);
      unawaited(existing.connect());
      return existing;
    }
    if (existing != null) await existing.close();
    final session = InternetTunnelSession(
      tunnelId: tunnelId,
      secret: secret,
      profileId: profileId,
      nickname: nickname,
    )..replaceHistory(history);
    _sessions[tunnelId] = session;
    unawaited(session.connect());
    return session;
  }

  static Future<void> close(String tunnelId) async {
    // A chat, the file index, call signaling and the background monitor share
    // this session. Screen disposal must never tear down the shared transport.
  }

  static Future<void> shutdownAll() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    final hubs = <_GatewayHub>{};
    for (final session in sessions) {
      final hub = session._hub;
      if (hub != null) hubs.add(hub);
      await session.close();
    }
    for (final hub in hubs) {
      await hub.close();
    }
  }
}
