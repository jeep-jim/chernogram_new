import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class _PublicBrokerEndpoint {
  final String host;
  final int port;
  final bool secure;

  const _PublicBrokerEndpoint(this.host, this.port, {required this.secure});

  String get label => '$host:$port';
}

/// Lightweight internet relay used when the project has no private Impulse
/// backend configured. Room contents are already AES-GCM encrypted by
/// InternetTunnelSession before they reach this transport.
class CgPublicMqttRelay {
  static const List<_PublicBrokerEndpoint> _endpoints =
      <_PublicBrokerEndpoint>[
        _PublicBrokerEndpoint('broker.emqx.io', 8883, secure: true),
        _PublicBrokerEndpoint('test.mosquitto.org', 8886, secure: true),
        _PublicBrokerEndpoint('broker.emqx.io', 1883, secure: false),
        _PublicBrokerEndpoint('test.mosquitto.org', 1883, secure: false),
      ];

  final String roomKey;
  final String deviceId;

  final StreamController<Map<String, dynamic>> _packets =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final StreamController<Map<String, dynamic>> _statuses =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;
  bool _connecting = false;
  bool _closed = false;
  String? _brokerLabel;

  CgPublicMqttRelay({required this.roomKey, required this.deviceId});

  Stream<Map<String, dynamic>> get packets => _packets.stream;
  Stream<Map<String, dynamic>> get statuses => _statuses.stream;

  bool get connected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  String get _topicBase => 'chernogram/v81/rooms/$roomKey';
  String get _liveTopic => '$_topicBase/live';
  String get _historyTopic => '$_topicBase/history';
  String get _subscriptionTopic => '$_topicBase/#';

  String _newClientId() {
    final safe = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final base = safe.isEmpty ? 'device' : safe;
    final take = base.length < 18 ? base.length : 18;
    return 'cg81_${base.substring(0, take)}_$suffix';
  }

  Future<void> connect() async {
    if (_closed || connected || _connecting) return;
    _connecting = true;
    _emitStatus('connecting');
    Object? lastError;

    try {
      for (final endpoint in _endpoints) {
        if (_closed) return;
        MqttServerClient? candidate;
        try {
          final clientId = _newClientId();
          candidate = MqttServerClient.withPort(
            endpoint.host,
            clientId,
            endpoint.port,
            maxConnectionAttempts: 1,
          );
          candidate.logging(on: false);
          candidate.setProtocolV311();
          candidate.secure = endpoint.secure;
          candidate.keepAlivePeriod = 20;
          candidate.connectTimeoutPeriod = 6500;
          candidate.disconnectOnNoResponsePeriod = 12;
          candidate.autoReconnect = false;
          candidate.resubscribeOnAutoReconnect = true;
          candidate.connectionMessage = MqttConnectMessage()
              .withClientIdentifier(clientId)
              .startClean()
              .withWillQos(MqttQos.atLeastOnce);

          final status = await candidate.connect().timeout(
            const Duration(seconds: 8),
          );
          if (status?.state != MqttConnectionState.connected) {
            throw StateError(
              'MQTT ${endpoint.label}: ${status?.returnCode ?? 'not connected'}',
            );
          }

          await _subscription?.cancel();
          _client?.disconnect();
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
      throw lastError ?? StateError('No public MQTT broker is reachable');
    } finally {
      _connecting = false;
    }
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
    if (_closed) return false;
    if (!connected) {
      try {
        await connect();
      } catch (_) {
        return false;
      }
    }
    final client = _client;
    if (client == null || !connected) return false;
    try {
      final builder = MqttClientPayloadBuilder()
        ..addUTF8String(jsonEncode(envelope));
      final payload = builder.payload;
      if (payload == null) return false;
      client.publishMessage(
        retain ? _historyTopic : _liveTopic,
        MqttQos.atLeastOnce,
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
