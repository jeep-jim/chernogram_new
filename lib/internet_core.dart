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

class InternetTunnelSession {
  static const List<String> relayHosts = <String>[
    'ntfy.sh',
    'ntfy.jae.fi',
    'ntfy.adminforge.de',
    'ntfy.envs.net',
  ];

  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;

  final StreamController<InternetEvent> _events =
      StreamController<InternetEvent>.broadcast(sync: true);
  final Map<String, DateTime> _peers = <String, DateTime>{};
  final Map<String, String> _peerNames = <String, String>{};
  final Set<String> _seenPackets = <String>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];
  final http.Client _http = http.Client();
  final Map<String, WebSocket> _sockets = <String, WebSocket>{};
  final Map<String, StreamSubscription<dynamic>> _socketSubscriptions =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, Timer> _relayRetryTimers = <String, Timer>{};
  final Set<String> _connectingHosts = <String>{};

  Timer? _presenceTimer;
  Timer? _peerCleanupTimer;
  SecretKey? _secretKey;
  String? _topic;
  bool _closed = false;
  bool _connecting = false;
  int _reconnectAttempt = 0;

  InternetTunnelSession({
    required this.tunnelId,
    required this.secret,
    required this.profileId,
    required this.nickname,
  });

  Stream<InternetEvent> get events => _events.stream;
  bool get connected => _sockets.isNotEmpty;
  int get onlinePeers => _peers.length + 1;
  List<Map<String, dynamic>> get members => <Map<String, dynamic>>[
    <String, dynamic>{
      'id': profileId,
      'name': nickname,
      'self': true,
      'seenAt': DateTime.now().toUtc().toIso8601String(),
    },
    ..._peers.entries.map(
      (entry) => <String, dynamic>{
        'id': entry.key,
        'name': _peerNames[entry.key] ?? 'user',
        'self': false,
        'seenAt': entry.value.toUtc().toIso8601String(),
      },
    ),
  ];

  Future<void> connect() async {
    if (_closed || _connecting) return;
    _connecting = true;
    _emit('status', <String, dynamic>{
      'state': connected ? 'connected' : 'connecting',
      'transport': 'multi_https443',
    });
    try {
      await _prepareCryptoAndTopic();
      await Future.wait(
        relayHosts.map((host) => _connectHost(host)),
        eagerError: false,
      );
      if (connected) {
        _reconnectAttempt = 0;
        _startTimers();
        await _publishPresence();
        await _flushOutbox();
        _emit('status', <String, dynamic>{
          'state': 'connected',
          'transport': 'multi_https443',
          'relays': _sockets.keys.toList(),
        });
      } else {
        _emit('status', const <String, dynamic>{
          'state': 'error',
          'code': 'relay_unavailable',
        });
        _scheduleGlobalReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connectHost(String host) async {
    if (_closed || _sockets.containsKey(host) || !_connectingHosts.add(host)) {
      return;
    }
    try {
      final uri = Uri(
        scheme: 'wss',
        host: host,
        path: '/${_topic!}/ws',
        queryParameters: const <String, String>{'since': '12h'},
      );
      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 12));
      if (_closed) {
        await socket.close();
        return;
      }
      socket.pingInterval = const Duration(seconds: 25);
      _relayRetryTimers.remove(host)?.cancel();
      await _socketSubscriptions.remove(host)?.cancel();
      _sockets[host] = socket;
      _socketSubscriptions[host] = socket.listen(
        (raw) => unawaited(_handleSocketMessage(host, raw)),
        onError: (Object error) => _onHostDisconnected(host, error.toString()),
        onDone: () => _onHostDisconnected(host, 'socket_closed'),
        cancelOnError: true,
      );
      _emit('status', <String, dynamic>{
        'state': 'connected',
        'transport': 'multi_https443',
        'relays': _sockets.keys.toList(),
      });
    } catch (_) {
      _scheduleHostReconnect(host);
    } finally {
      _connectingHosts.remove(host);
    }
  }

  Future<void> _prepareCryptoAndTopic() async {
    if (_secretKey != null && _topic != null) return;
    final hash = await Sha256().hash(utf8.encode('$tunnelId:$secret'));
    _secretKey = SecretKey(hash.bytes);
    final encoded = base64Url.encode(hash.bytes).replaceAll('=', '');
    _topic = 'cg_$encoded';
  }

  Future<void> _handleSocketMessage(String host, dynamic raw) async {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      final event = message['event']?.toString() ?? '';
      if (event == 'open') return;
      if (event != 'message') return;

      String? encrypted;
      final attachment = message['attachment'];
      if (attachment is Map) {
        final url = attachment['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final response = await _http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 120));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            encrypted = utf8.decode(response.bodyBytes, allowMalformed: true);
          }
        }
      }
      encrypted ??= message['message']?.toString();
      if (encrypted == null || encrypted.isEmpty) return;
      final unixTime = int.tryParse(message['time']?.toString() ?? '');
      final relayAt = unixTime == null
          ? DateTime.now().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(unixTime * 1000, isUtc: true);
      await _handleEncryptedPacket(encrypted, relayAt, host);
    } catch (_) {}
  }

  void _onHostDisconnected(String host, String reason) {
    if (_closed) return;
    _sockets.remove(host);
    final subscription = _socketSubscriptions.remove(host);
    if (subscription != null) unawaited(subscription.cancel());
    _scheduleHostReconnect(host);
    _emit('status', <String, dynamic>{
      'state': connected ? 'connected' : 'disconnected',
      'transport': 'multi_https443',
      'relays': _sockets.keys.toList(),
      'debug': reason,
    });
    if (!connected) _scheduleGlobalReconnect();
  }

  Future<void> _handleEncryptedPacket(
    String encrypted,
    DateTime relayAt,
    String relayHost,
  ) async {
    final envelope = await _decrypt(encrypted);
    if (envelope == null) return;

    final packetId = envelope['packetId']?.toString() ?? '';
    final sender = envelope['from']?.toString() ?? '';
    if (packetId.isEmpty || !_seenPackets.add(packetId)) return;
    if (_seenPackets.length > 5000) _seenPackets.remove(_seenPackets.first);
    if (sender == profileId) return;

    final kind = envelope['kind']?.toString() ?? '';
    final sentAt = DateTime.tryParse(envelope['sentAt']?.toString() ?? '');
    if (kind == 'signal' &&
        sentAt != null &&
        DateTime.now().toUtc().difference(sentAt.toUtc()).inSeconds.abs() >
            120) {
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
          final rawMeta = message['meta'];
          final meta = rawMeta is Map
              ? Map<String, dynamic>.from(rawMeta)
              : <String, dynamic>{};
          meta.putIfAbsent('relayAt', () => relayAt.toIso8601String());
          message['meta'] = meta;
          _rememberMessage(message);
          _emit('message', <String, dynamic>{
            'message': message,
            'relaySender': sender,
            'relaySenderName': senderName,
            'relayHost': relayHost,
          });
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
        _emit('history', <String, dynamic>{
          'messages': messages,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
      case 'control':
        _emit('control', <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
      case 'signal':
        _emit('signal', <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
    }
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberMessage(message);
    await _sendEnvelope('message', <String, dynamic>{'message': message});
  }

  Future<void> sendControl(Map<String, dynamic> control) async {
    await _sendEnvelope('control', control);
  }

  Future<void> sendSignal(Map<String, dynamic> signal) async {
    await _sendEnvelope('signal', signal, queueOnFailure: false);
  }

  Future<void> sendHistory() async {
    if (_history.isEmpty) return;
    await _sendEnvelope('history', <String, dynamic>{
      'messages': _history.take(500).toList(),
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
    if (!connected) unawaited(connect());

    final body = <String, dynamic>{
      'v': 6,
      'packetId': CgIds.random(24),
      'from': profileId,
      'name': nickname,
      'kind': kind,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
    final encrypted = await _encrypt(body);

    var successCount = 0;
    final errors = <Object>[];
    await Future.wait(
      relayHosts.map((host) async {
        try {
          await _publishEncrypted(host, encrypted, cache: kind != 'presence');
          successCount++;
        } catch (error) {
          errors.add(error);
          _scheduleHostReconnect(host);
        }
      }),
      eagerError: false,
    );

    if (successCount > 0) {
      if (kind == 'message' || kind == 'control') {
        _emit('status', <String, dynamic>{
          'state': 'connected',
          'transport': 'multi_https443',
          'publishedRelays': successCount,
        });
      }
      return;
    }

    final canQueue = queueOnFailure && (kind == 'message' || kind == 'control');
    if (canQueue) {
      String? uniqueId;
      if (kind == 'message') {
        final rawMessage = data['message'];
        if (rawMessage is Map) uniqueId = rawMessage['id']?.toString();
      } else {
        uniqueId = data['operationId']?.toString();
      }
      final duplicate =
          uniqueId != null &&
          _outbox.any((item) {
            if (item.kind != kind) return false;
            if (kind == 'message') {
              final rawMessage = item.data['message'];
              return rawMessage is Map &&
                  rawMessage['id']?.toString() == uniqueId;
            }
            return item.data['operationId']?.toString() == uniqueId;
          });
      if (!duplicate) {
        _outbox.add(_PendingEnvelope(kind, Map<String, dynamic>.from(data)));
      }
      _emit('status', const <String, dynamic>{
        'state': 'queued',
        'code': 'relay_unavailable',
      });
    } else {
      _emit('status', <String, dynamic>{
        'state': 'error',
        'code': 'relay_unavailable',
        'debug': errors.isEmpty ? 'no_relay' : errors.first.toString(),
      });
    }
    _scheduleGlobalReconnect();
  }

  Future<void> _publishEncrypted(
    String host,
    String encrypted, {
    required bool cache,
  }) async {
    final bytes = utf8.encode(encrypted);
    final large = bytes.length > 3500;
    final response = await _http
        .post(
          Uri.parse('https://$host/${_topic!}'),
          headers: <String, String>{
            'Content-Type': large
                ? 'application/octet-stream'
                : 'text/plain; charset=utf-8',
            'Title': 'Chernogram',
            'Priority': 'min',
            'Firebase': 'no',
            if (large) 'Filename': 'chernogram-packet.cg',
            if (!cache) 'Cache': 'no',
          },
          body: large ? bytes : encrypted,
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('$host:${response.statusCode}');
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
    return jsonEncode(<String, String>{
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
    if (id.isEmpty) return false;
    final index = _history.indexWhere((item) => item['id']?.toString() == id);
    if (index >= 0) {
      _history[index] = Map<String, dynamic>.from(message);
      return true;
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
      final removed = _peers.keys
          .where((id) => _peers[id]?.isBefore(cutoff) == true)
          .toList();
      for (final id in removed) {
        _peers.remove(id);
        _peerNames.remove(id);
      }
      _emitPresence();
    });
  }

  void _emitPresence() {
    _emit('presence', <String, dynamic>{
      'peers': onlinePeers,
      'members': members,
    });
  }

  void _scheduleHostReconnect(String host) {
    if (_closed || _sockets.containsKey(host)) return;
    _relayRetryTimers.remove(host)?.cancel();
    _relayRetryTimers[host] = Timer(const Duration(seconds: 8), () {
      unawaited(_connectHost(host));
    });
  }

  void _scheduleGlobalReconnect() {
    if (_closed) return;
    _reconnectAttempt++;
    final seconds = _reconnectAttempt <= 1
        ? 2
        : (_reconnectAttempt * _reconnectAttempt).clamp(4, 30).toInt();
    for (final host in relayHosts) {
      if (_sockets.containsKey(host)) continue;
      _relayRetryTimers.remove(host)?.cancel();
      _relayRetryTimers[host] = Timer(Duration(seconds: seconds), () {
        unawaited(_connectHost(host));
      });
    }
  }

  void _emit(String type, [Map<String, dynamic> data = const {}]) {
    if (!_events.isClosed) _events.add(InternetEvent(type, data));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    for (final timer in _relayRetryTimers.values) {
      timer.cancel();
    }
    _relayRetryTimers.clear();
    for (final subscription in _socketSubscriptions.values) {
      await subscription.cancel();
    }
    _socketSubscriptions.clear();
    for (final socket in _sockets.values) {
      await socket.close();
    }
    _sockets.clear();
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
