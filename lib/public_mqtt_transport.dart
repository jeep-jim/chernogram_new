import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class _PublicBrokerEndpoint {
  final String server;
  final int port;
  final bool webSocket;
  final bool secureTcp;

  const _PublicBrokerEndpoint(
    this.server,
    this.port, {
    this.webSocket = false,
    this.secureTcp = false,
  });

  String get label => '$server:$port';
}

/// Lightweight encrypted room relay.
///
/// WSS is preferred because it behaves better across mobile networks and
/// desktop firewalls than raw MQTT ports. Message contents are AES-GCM
/// encrypted by InternetTunnelSession before they reach this transport.
class CgPublicMqttRelay {
  static const List<_PublicBrokerEndpoint> _endpoints =
      <_PublicBrokerEndpoint>[
        _PublicBrokerEndpoint(
          'wss://broker.emqx.io/mqtt',
          8084,
          webSocket: true,
        ),
        _PublicBrokerEndpoint(
          'wss://test.mosquitto.org/mqtt',
          8081,
          webSocket: true,
        ),
        _PublicBrokerEndpoint(
          'broker.emqx.io',
          8883,
          secureTcp: true,
        ),
        _PublicBrokerEndpoint(
          'test.mosquitto.org',
          8886,
          secureTcp: true,
        ),
      ];

  final String roomKey;
  final String deviceId;

  final StreamController<Map<String, dynamic>> _packets =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final StreamController<Map<String, dynamic>> _statuses =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;
  Completer<void>? _connectCompleter;
  bool _closed = false;
  String? _brokerLabel;

  CgPublicMqttRelay({required this.roomKey, required this.deviceId});

  Stream<Map<String, dynamic>> get packets => _packets.stream;
  Stream<Map<String, dynamic>> get statuses => _statuses.stream;

  bool get connected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  // Keep the 0.81 topic namespace during the 0.82 -> 0.83 upgrade so rooms
  // remain compatible while devices update at different times.
  String get _topicBase => 'chernogram/v81/rooms/$roomKey';
  String get _liveTopic => '$_topicBase/live';
  String get _historyTopic => '$_topicBase/history';
  String get _subscriptionTopic => '$_topicBase/#';

  String _newClientId() {
    final safe = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final base = safe.isEmpty ? 'device' : safe;
    final take = base.length < 16 ? base.length : 16;
    return 'cg83_${base.substring(0, take)}_$suffix';
  }

  Future<void> connect() {
    if (_closed || connected) return Future<void>.value();
    final current = _connectCompleter;
    if (current != null) return current.future;

    final completer = Completer<void>();
    _connectCompleter = completer;
    unawaited(() async {
      try {
        await _connectImpl();
        if (!completer.isCompleted) completer.complete();
      } catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      } finally {
        if (identical(_connectCompleter, completer)) {
          _connectCompleter = null;
        }
      }
    }());
    return completer.future;
  }

  Future<void> _connectImpl() async {
    if (_closed || connected) return;
    _emitStatus('connecting');
    Object? lastError;

    for (final endpoint in _endpoints) {
      if (_closed) return;
      MqttServerClient? candidate;
      try {
        final clientId = _newClientId();
        candidate = MqttServerClient.withPort(
          endpoint.server,
          clientId,
          endpoint.port,
          maxConnectionAttempts: 1,
        );
        candidate.logging(on: false, logPayloads: false);
        candidate.setProtocolV311();
        candidate.keepAlivePeriod = 20;
        candidate.connectTimeoutPeriod = 4500;
        candidate.disconnectOnNoResponsePeriod = 10;
        candidate.autoReconnect = false;
        candidate.resubscribeOnAutoReconnect = true;
        candidate.useWebSocket = endpoint.webSocket;
        if (endpoint.webSocket) {
          candidate.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
          candidate.secure = false;
        } else {
          candidate.secure = endpoint.secureTcp;
        }
        candidate.connectionMessage = MqttConnectMessage()
            .withClientIdentifier(clientId)
            .startClean();

        final status = await candidate.connect().timeout(
          const Duration(seconds: 6),
        );
        if (status?.state != MqttConnectionState.connected) {
          throw StateError(
            'MQTT ${endpoint.label}: ${status?.returnCode ?? 'not connected'}',
          );
        }

        await _subscription?.cancel();
        try {
          _client?.disconnect();
        } catch (_) {}
        _client = candidate;
        _brokerLabel = endpoint.label;
        candidate.onDisconnected = _onDisconnected;
        candidate.subscribe(_subscriptionTopic, MqttQos.atLeastOnce);
        _subscription = candidate.updates?.listen(
          _onUpdates,
          onError: (_) => _onDisconnected(),
          cancelOnError: false,
        );
        _emitStatus('connected');
        return;
      } catch (error) {
        lastError = error;
        try {
          candidate?.disconnect();
        } catch (_) {}
      }
    }

    _emitStatus('queued');
    throw lastError ?? StateError('No public MQTT broker is reachable');
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final item in messages) {
      final raw = item.payload;
      if (raw is! MqttPublishMessage) continue;
      try {
        final text = MqttPublishPayload.bytesToStringAsString(
          raw.payload.message,
        );
        final decoded = jsonDecode(text);
        if (decoded is! Map) continue;
        final packet = Map<String, dynamic>.from(decoded);
        final createdAt = int.tryParse(packet['createdAt']?.toString() ?? '');
        if (createdAt != null) {
          final age = DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(createdAt),
          );
          if (age > const Duration(hours: 36)) continue;
        }
        if (!_packets.isClosed) _packets.add(packet);
      } catch (_) {}
    }
  }

  Future<bool> publish(
    Map<String, dynamic> envelope, {
    bool retain = false,
  }) async {
    if (_closed || !connected) return false;
    final client = _client;
    if (client == null) return false;
    try {
      final builder = MqttClientPayloadBuilder()
        ..addUTF8String(jsonEncode(envelope));
      final payload = builder.payload;
      if (payload == null) return false;
      final kind = envelope['kind']?.toString() ?? '';
      final qos = kind == 'presence' || kind == 'signal'
          ? MqttQos.atMostOnce
          : MqttQos.atLeastOnce;
      client.publishMessage(
        retain ? _historyTopic : _liveTopic,
        qos,
        payload,
        retain: retain,
      );
      return true;
    } catch (_) {
      _onDisconnected();
      return false;
    }
  }

  void _onDisconnected() {
    if (_closed) return;
    _emitStatus('queued');
  }

  void _emitStatus(String state) {
    if (_statuses.isClosed) return;
    _statuses.add(<String, dynamic>{
      'state': state,
      'transport': 'public_mqtt',
      if (_brokerLabel != null) 'broker': _brokerLabel,
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    await _packets.close();
    await _statuses.close();
  }
}
