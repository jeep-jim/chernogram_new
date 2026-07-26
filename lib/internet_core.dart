import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'core_models.dart';

class InternetEvent {
  final String type;
  final Map<String, dynamic> data;

  const InternetEvent(this.type, [this.data = const <String, dynamic>{}]);
}

class InternetTunnelSession {
  static const String brokerHost = 'broker.emqx.io';
  static const int brokerPort = 8084;

  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;

  final StreamController<InternetEvent> _events =
      StreamController<InternetEvent>.broadcast(sync: true);
  final Map<String, DateTime> _peers = <String, DateTime>{};
  final Set<String> _seenPackets = <String>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  MqttServerClient? _client;
  StreamSubscription<dynamic>? _updatesSubscription;
  Timer? _reconnectTimer;
  Timer? _presenceTimer;
  Timer? _peerCleanupTimer;
  SecretKey? _secretKey;
  String? _topic;
  bool _closed = false;
  bool _connecting = false;
  bool _connected = false;
  int _reconnectAttempt = 0;

  InternetTunnelSession({
    required this.tunnelId,
    required this.secret,
    required this.profileId,
    required this.nickname,
  });

  Stream<InternetEvent> get events => _events.stream;
  bool get connected => _connected;
  int get onlinePeers => _peers.length + 1;

  Future<void> connect() async {
    if (_closed || _connecting || _connected) return;
    _connecting = true;
    _emit('status', {'state': 'connecting'});
    try {
      await _prepareCryptoAndTopic();
      final clientId =
          'cg_${profileId}_${CgIds.random(8)}'.replaceAll(RegExp('[^A-Za-z0-9_]'), '');
      final client = MqttServerClient.withPort(brokerHost, clientId, brokerPort)
        ..useWebSocket = true
        ..secure = true
        ..websocketProtocols = MqttClientConstants.protocolsSingleDefault
        ..keepAlivePeriod = 20
        ..connectTimeoutPeriod = 9000
        ..logging(on: false);
      client.onDisconnected = _onDisconnected;
      client.onConnected = _onConnected;
      client.pongCallback = () => _emit('pong');
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      _client = client;
      await client.connect();
      if (client.connectionStatus?.state !=
          MqttConnectionState.connected) {
        throw StateError(
          'Relay connection failed: ${client.connectionStatus?.returnCode}',
        );
      }
      _connected = true;
      _reconnectAttempt = 0;
      client.subscribe('$_topic/events', MqttQos.atLeastOnce);
      _updatesSubscription?.cancel();
      _updatesSubscription = client.updates?.listen(_handleUpdates);
      _startTimers();
      await _publishPresence();
      await _sendEnvelope('sync_request', <String, dynamic>{
        'known': _history.map((message) => message['id']).toList(),
      });
      _emit('status', {'state': 'connected'});
      _emitPresence();
    } catch (error) {
      _connected = false;
      _emit('status', {'state': 'error', 'error': error.toString()});
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _prepareCryptoAndTopic() async {
    if (_secretKey != null && _topic != null) return;
    final hash = await Sha256().hash(utf8.encode('$tunnelId:$secret'));
    _secretKey = SecretKey(hash.bytes);
    _topic = 'chernogram/v3/${base64Url.encode(hash.bytes).replaceAll('=', '')}';
  }

  void _onConnected() {
    _connected = true;
  }

  void _onDisconnected() {
    if (_closed) return;
    _connected = false;
    _emit('status', {
      'state': 'disconnected',
      'error': 'Internet relay disconnected',
    });
    _scheduleReconnect();
  }

  void _handleUpdates(dynamic batch) {
    if (batch is! List || batch.isEmpty) return;
    for (final item in batch) {
      try {
        final payload = item.payload;
        if (payload is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );
        unawaited(_handleEncryptedPacket(text));
      } catch (_) {}
    }
  }

  Future<void> _handleEncryptedPacket(String encrypted) async {
    final envelope = await _decrypt(encrypted);
    if (envelope == null) return;
    final packetId = envelope['packetId']?.toString() ?? '';
    final sender = envelope['from']?.toString() ?? '';
    if (packetId.isEmpty || !_seenPackets.add(packetId)) return;
    if (_seenPackets.length > 4000) {
      _seenPackets.remove(_seenPackets.first);
    }
    if (sender == profileId) return;

    final senderName = envelope['name']?.toString() ?? 'user';
    _peers[sender] = DateTime.now();
    _emitPresence();

    final kind = envelope['kind']?.toString() ?? '';
    final rawData = envelope['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    switch (kind) {
      case 'presence':
        break;
      case 'message':
        if (data['message'] is Map) {
          final message = Map<String, dynamic>.from(data['message'] as Map);
          _rememberMessage(message);
          _emit('message', {'message': message});
        }
        break;
      case 'sync_request':
        await _sendEnvelope('history', <String, dynamic>{
          'messages': _history.length > 150
              ? _history.sublist(_history.length - 150)
              : List<Map<String, dynamic>>.from(_history),
        });
        break;
      case 'history':
        final messages = ((data['messages'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        for (final message in messages) {
          _rememberMessage(message);
        }
        _emit('history', {'messages': messages});
        break;
      case 'signal':
        _emit('signal', {
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
    }
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberMessage(message);
    await _sendEnvelope('message', {'message': message});
  }

  Future<void> sendSignal(Map<String, dynamic> signal) async {
    await _sendEnvelope('signal', signal);
  }

  void replaceHistory(List<Map<String, dynamic>> messages) {
    _history.clear();
    for (final message in messages) {
      _rememberMessage(message);
    }
  }

  Future<void> _publishPresence() async {
    await _sendEnvelope('presence', <String, dynamic>{
      'online': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _sendEnvelope(
    String kind,
    Map<String, dynamic> data,
  ) async {
    if (_closed) return;
    if (!_connected) {
      _emit('status', {'state': 'queued'});
      await connect();
      if (!_connected) return;
    }
    final client = _client;
    if (client == null || _topic == null) return;
    final body = <String, dynamic>{
      'v': 3,
      'packetId': CgIds.random(24),
      'from': profileId,
      'name': nickname,
      'kind': kind,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
    final encrypted = await _encrypt(body);
    final builder = MqttClientPayloadBuilder()..addString(encrypted);
    final payload = builder.payload;
    if (payload == null) return;
    client.publishMessage(
      '$_topic/events',
      MqttQos.atLeastOnce,
      payload,
    );
  }

  Future<String> _encrypt(Map<String, dynamic> body) async {
    await _prepareCryptoAndTopic();
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(jsonEncode(body)),
      secretKey: _secretKey!,
      nonce: nonce,
    );
    return jsonEncode({
      'n': base64Url.encode(box.nonce),
      'c': base64Url.encode(box.cipherText),
      'm': base64Url.encode(box.mac.bytes),
    });
  }

  Future<Map<String, dynamic>?> _decrypt(String value) async {
    try {
      await _prepareCryptoAndTopic();
      final raw = jsonDecode(value);
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final box = SecretBox(
        base64Url.decode(map['c']?.toString() ?? ''),
        nonce: base64Url.decode(map['n']?.toString() ?? ''),
        mac: Mac(base64Url.decode(map['m']?.toString() ?? '')),
      );
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: _secretKey!,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  bool _rememberMessage(Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty ||
        _history.any((item) => item['id']?.toString() == id)) {
      return false;
    }
    _history.add(Map<String, dynamic>.from(message));
    if (_history.length > 500) {
      _history.removeRange(0, _history.length - 500);
    }
    return true;
  }

  void _startTimers() {
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      unawaited(_publishPresence());
    });
    _peerCleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 55));
      _peers.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));
      _emitPresence();
    });
  }

  void _emitPresence() {
    _emit('presence', {'peers': onlinePeers});
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final seconds = _reconnectAttempt.clamp(1, 8);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      unawaited(connect());
    });
  }

  void _emit(String type, [Map<String, dynamic> data = const {}]) {
    if (!_events.isClosed) {
      _events.add(InternetEvent(type, data));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _connected = false;
    _reconnectTimer?.cancel();
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    await _updatesSubscription?.cancel();
    _client?.disconnect();
    await _events.close();
  }
}

class InternetRelay {
  static final Map<String, InternetTunnelSession> _sessions =
      <String, InternetTunnelSession>{};

  static InternetTunnelSession? session(String tunnelId) =>
      _sessions[tunnelId];

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
    await session.connect();
    return session;
  }

  static Future<void> close(String tunnelId) async {
    final session = _sessions.remove(tunnelId);
    if (session != null) await session.close();
  }
}
