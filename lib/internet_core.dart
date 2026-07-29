import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'core_models.dart';

class InternetEvent {
  final String type;
  final Map<String, dynamic> data;

  const InternetEvent(this.type, [this.data = const <String, dynamic>{}]);
}

class _PendingEnvelope {
  final String kind;
  final Map<String, dynamic> data;

  const _PendingEnvelope(this.kind, this.data);
}

/// Internet relay for Chernogram tunnels.
///
/// Transport:
/// - standard HTTPS/WSS on port 443, so it works across mobile operators,
///   home Wi-Fi and different cities without opening custom ports;
/// - public ntfy relay is used only as an encrypted transport;
/// - message content is encrypted locally with AES-256-GCM before upload;
/// - the relay topic is derived from the tunnel secret and is not guessable.
class InternetTunnelSession {
  static const String relayBase = 'https://ntfy.sh';
  static const String relaySocketHost = 'ntfy.sh';

  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;

  final StreamController<InternetEvent> _events =
      StreamController<InternetEvent>.broadcast(sync: true);
  final Map<String, DateTime> _peers = <String, DateTime>{};
  final Map<String, String> _peerNames = <String, String>{};
  final List<Map<String, dynamic>> _signalHistory = <Map<String, dynamic>>[];
  final Set<String> _seenPackets = <String>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];
  final http.Client _http = http.Client();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
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
  List<Map<String, dynamic>> get members => <Map<String, dynamic>>[
    <String, dynamic>{'id': profileId, 'name': nickname, 'self': true},
    ..._peers.entries.map(
      (entry) => <String, dynamic>{
        'id': entry.key,
        'name': _peerNames[entry.key] ?? 'user',
        'self': false,
        'seenAt': entry.value.toUtc().toIso8601String(),
      },
    ),
  ];

  Future<bool> waitUntilConnected([
    Duration timeout = const Duration(seconds: 4),
  ]) async {
    if (_connected) return true;
    unawaited(connect());
    final deadline = DateTime.now().add(timeout);
    while (!_closed && DateTime.now().isBefore(deadline)) {
      if (_connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return _connected;
  }

  Future<void> connect() async {
    if (_closed || _connecting || _connected) return;
    _connecting = true;
    _emit('status', {'state': 'connecting', 'transport': 'https443'});

    try {
      await _prepareCryptoAndTopic();
      final topic = _topic!;
      final uri = Uri(
        scheme: 'wss',
        host: relaySocketHost,
        path: '/$topic/ws',
        queryParameters: const {'since': '12h'},
      );

      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 14));
      if (_closed) {
        await socket.close();
        return;
      }

      socket.pingInterval = const Duration(seconds: 25);
      await _socketSubscription?.cancel();
      _socket = socket;
      _connected = true;
      _reconnectAttempt = 0;
      _emit('status', {'state': 'connected', 'transport': 'https443'});
      _emitPresence();

      _socketSubscription = socket.listen(
        (raw) => unawaited(_handleSocketMessage(raw)),
        onError: (Object error) => _onDisconnected(error.toString()),
        onDone: () => _onDisconnected('socket_closed'),
        cancelOnError: true,
      );

      _startTimers();
      await _publishPresence();
      await _flushOutbox();
    } catch (error) {
      _connected = false;
      _socket = null;
      _emit('status', {
        'state': 'error',
        'code': 'relay_unavailable',
        'debug': error.toString(),
      });
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _prepareCryptoAndTopic() async {
    if (_secretKey != null && _topic != null) return;
    final hash = await Sha256().hash(utf8.encode('$tunnelId:$secret'));
    _secretKey = SecretKey(hash.bytes);
    final encoded = base64Url.encode(hash.bytes).replaceAll('=', '');
    _topic = 'cg_$encoded';
  }

  Future<void> _handleSocketMessage(dynamic raw) async {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      final event = message['event']?.toString() ?? '';
      if (event == 'open') {
        if (!_connected) {
          _connected = true;
          _emit('status', {'state': 'connected', 'transport': 'https443'});
        }
        return;
      }
      if (event != 'message') return;

      String? encrypted;
      final attachment = message['attachment'];
      if (attachment is Map) {
        final url = attachment['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final response = await _http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            encrypted = utf8.decode(response.bodyBytes, allowMalformed: true);
          }
        }
      }
      encrypted ??= message['message']?.toString();
      if (encrypted == null || encrypted.isEmpty) return;
      await _handleEncryptedPacket(encrypted);
    } catch (_) {
      // A malformed packet must never break the tunnel stream.
    }
  }

  void _onDisconnected(String reason) {
    if (_closed) return;
    _connected = false;
    _socket = null;
    _emit('presence', {'peers': 1});
    _emit('status', {
      'state': 'disconnected',
      'code': 'relay_unavailable',
      'debug': reason,
    });
    _scheduleReconnect();
  }

  Future<void> _handleEncryptedPacket(String encrypted) async {
    final envelope = await _decrypt(encrypted);
    if (envelope == null) return;

    final packetId = envelope['packetId']?.toString() ?? '';
    final sender = envelope['from']?.toString() ?? '';
    if (packetId.isEmpty || !_seenPackets.add(packetId)) return;
    if (_seenPackets.length > 5000) {
      _seenPackets.remove(_seenPackets.first);
    }
    if (sender == profileId) return;

    final kind = envelope['kind']?.toString() ?? '';
    final sentAt = DateTime.tryParse(envelope['sentAt']?.toString() ?? '');
    if (kind == 'signal' &&
        sentAt != null &&
        DateTime.now().toUtc().difference(sentAt.toUtc()).abs() >
            const Duration(minutes: 2)) {
      return;
    }

    final senderName = envelope['name']?.toString() ?? 'user';
    _peers[sender] = DateTime.now();
    _peerNames[sender] = senderName;
    _emit('peer', <String, dynamic>{
      'id': sender,
      'name': senderName,
      'seenAt': DateTime.now().toUtc().toIso8601String(),
    });
    _emitPresence();

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
      case 'control':
        _emit('control', <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
      case 'signal':
        final signal = <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
          'sentAt': envelope['sentAt'],
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
        };
        _signalHistory.add(signal);
        if (_signalHistory.length > 200) {
          _signalHistory.removeRange(0, _signalHistory.length - 200);
        }
        _emit('signal', signal);
        break;
    }
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberMessage(message);
    await _sendEnvelope('message', {'message': message});
  }

  Future<void> sendControl(Map<String, dynamic> control) async {
    await _sendEnvelope('control', control);
  }

  Future<void> sendSignal(Map<String, dynamic> signal) async {
    await _sendEnvelope('signal', signal);
  }

  List<Map<String, dynamic>> replaySignals(String callId) {
    if (callId.isEmpty) return const <Map<String, dynamic>>[];
    return _signalHistory
        .where((item) => item['callId']?.toString() == callId)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> sendHistory() async {
    if (_history.isEmpty) return;
    final start = _history.length > 120 ? _history.length - 120 : 0;
    await _sendEnvelope('history', <String, dynamic>{
      'messages': _history.skip(start).toList(),
    });
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
    }, queueOnFailure: false);
  }

  Future<void> _sendEnvelope(
    String kind,
    Map<String, dynamic> data, {
    bool queueOnFailure = true,
  }) async {
    if (_closed) return;
    await _prepareCryptoAndTopic();
    if (!_connected) unawaited(connect());

    final body = <String, dynamic>{
      'v': 4,
      'packetId': CgIds.random(24),
      'from': profileId,
      'name': nickname,
      'kind': kind,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
    final encrypted = await _encrypt(body);

    try {
      await _publishEncrypted(encrypted, cache: kind != 'presence');
      if (kind == 'message') {
        _emit('status', {'state': 'connected', 'transport': 'https443'});
      }
    } catch (error) {
      if (queueOnFailure && kind == 'message') {
        final packetId = (data['message'] as Map?)?['id']?.toString();
        final duplicate =
            packetId != null &&
            _outbox.any(
              (item) =>
                  (item.data['message'] as Map?)?['id']?.toString() == packetId,
            );
        if (!duplicate) {
          _outbox.add(_PendingEnvelope(kind, Map<String, dynamic>.from(data)));
        }
        _emit('status', {'state': 'queued', 'code': 'relay_unavailable'});
      } else {
        _emit('status', {
          'state': 'error',
          'code': 'relay_unavailable',
          'debug': error.toString(),
        });
      }
      _scheduleReconnect();
    }
  }

  Future<void> _publishEncrypted(
    String encrypted, {
    required bool cache,
  }) async {
    final response = await _http
        .post(
          Uri.parse('$relayBase/${_topic!}'),
          headers: <String, String>{
            'Content-Type': 'text/plain; charset=utf-8',
            'Title': 'Chernogram',
            'Priority': 'min',
            'Firebase': 'no',
            if (!cache) 'Cache': 'no',
          },
          body: encrypted,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('relay_http_${response.statusCode}');
    }
  }

  Future<void> _flushOutbox() async {
    if (_outbox.isEmpty) return;
    final pending = List<_PendingEnvelope>.from(_outbox);
    _outbox.clear();
    for (final item in pending) {
      await _sendEnvelope(item.kind, item.data);
    }
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
    if (id.isEmpty || _history.any((item) => item['id']?.toString() == id)) {
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
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_publishPresence());
    });
    _peerCleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 70));
      _peers.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));
      _emitPresence();
    });
  }

  void _emitPresence() {
    _emit('presence', {'peers': onlinePeers});
  }

  void _scheduleReconnect() {
    if (_closed || _connected) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final seconds = _reconnectAttempt <= 1
        ? 2
        : (_reconnectAttempt * _reconnectAttempt).clamp(4, 30).toInt();
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
    await _socketSubscription?.cancel();
    await _socket?.close();
    _http.close();
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
    final session = _sessions.remove(tunnelId);
    if (session != null) await session.close();
  }
}
