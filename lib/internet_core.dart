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
  // Temporary recovery transport. Keep one primary and one hot standby;
  // broadcasting every packet to four public services caused radio load,
  // duplicate cache replays and long UI stalls on Android.
  static const List<String> relayHosts = <String>[
    'ntfy.sh',
    'ntfy.jae.fi',
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
  final List<Map<String, dynamic>> _signalHistory = <Map<String, dynamic>>[];
  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];
  final http.Client _http = http.Client();
  final Map<String, WebSocket> _sockets = <String, WebSocket>{};
  final Map<String, StreamSubscription<dynamic>> _socketSubscriptions =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, Timer> _relayRetryTimers = <String, Timer>{};
  final Set<String> _connectingHosts = <String>{};

  Timer? _presenceTimer;
  Timer? _peerCleanupTimer;
  Timer? _globalRetryTimer;
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
            'name': _peerNames[entry.key] ?? 'пользователь',
            'self': false,
            'seenAt': entry.value.toUtc().toIso8601String(),
          },
        ),
      ];

  Future<void> connect() async {
    if (_closed || _connecting || connected) return;
    _connecting = true;
    _emit('status', const <String, dynamic>{
      'state': 'connecting',
      'transport': 'encrypted_https443',
    });
    try {
      await _prepareCryptoAndTopic();
      final connectHosts = relayHosts.take(2).toList(growable: false);
      final completer = Completer<void>();
      var finished = 0;
      for (final host in connectHosts) {
        unawaited(
          _connectHost(host).then((ok) {
            finished++;
            if (ok && !completer.isCompleted) completer.complete();
            if (finished == connectHosts.length && !completer.isCompleted) {
              completer.complete();
            }
          }),
        );
      }
      await completer.future.timeout(
        const Duration(seconds: 7),
        onTimeout: () {},
      );
      if (_closed) return;
      if (connected) {
        _reconnectAttempt = 0;
        _globalRetryTimer?.cancel();
        _startTimers();
        unawaited(_publishPresence());
        unawaited(_flushOutbox());
        _emit('status', <String, dynamic>{
          'state': 'connected',
          'transport': 'encrypted_https443',
          'relays': _sockets.keys.toList(),
        });
      } else {
        _emit('status', const <String, dynamic>{
          'state': 'offline',
          'code': 'relay_unavailable',
        });
        _scheduleGlobalReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  Future<bool> waitUntilConnected([Duration timeout = const Duration(seconds: 4)]) async {
    if (connected) return true;
    unawaited(connect());
    final deadline = DateTime.now().add(timeout);
    while (!_closed && DateTime.now().isBefore(deadline)) {
      if (connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return connected;
  }

  Future<bool> _connectHost(String host) async {
    if (_closed || _sockets.containsKey(host) || !_connectingHosts.add(host)) {
      return _sockets.containsKey(host);
    }
    try {
      final uri = Uri(
        scheme: 'wss',
        host: host,
        path: '/${_topic!}/ws',
        queryParameters: const <String, String>{'since': '2m'},
      );
      final socket = await WebSocket.connect(uri.toString()).timeout(
        const Duration(milliseconds: 3200),
      );
      if (_closed) {
        await socket.close();
        return false;
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
        'transport': 'encrypted_https443',
        'relays': _sockets.keys.toList(),
      });
      return true;
    } catch (_) {
      _scheduleHostReconnect(host);
      return false;
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
      if (event != 'message') return;
      String? encrypted;
      final attachment = message['attachment'];
      if (attachment is Map) {
        final url = attachment['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final response = await _http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 18));
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
    if (connected) {
      _emit('status', <String, dynamic>{
        'state': 'connected',
        'transport': 'encrypted_https443',
        'relays': _sockets.keys.toList(),
      });
    } else {
      _emit('status', const <String, dynamic>{
        'state': 'offline',
        'transport': 'encrypted_https443',
      });
      _scheduleGlobalReconnect();
    }
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
        DateTime.now().toUtc().difference(sentAt.toUtc()).inSeconds.abs() > 120) {
      return;
    }

    final senderName = envelope['name']?.toString() ?? 'пользователь';
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
          _rememberMessage(_sanitizeMessage(message));
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
          _rememberMessage(_sanitizeMessage(message));
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
    _rememberMessage(_sanitizeMessage(message));
    await _sendEnvelope('message', <String, dynamic>{'message': message});
  }

  Future<void> sendControl(Map<String, dynamic> control) async {
    await _sendEnvelope('control', control);
  }

  Future<void> sendSignal(Map<String, dynamic> signal) async {
    await _sendEnvelope('signal', signal, queueOnFailure: false);
  }

  List<Map<String, dynamic>> replaySignals(String callId) {
    if (callId.isEmpty) return const <Map<String, dynamic>>[];
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    return _signalHistory.where((signal) {
      if (signal['callId']?.toString() != callId) return false;
      final receivedAt = DateTime.tryParse(signal['receivedAt']?.toString() ?? '');
      return receivedAt == null || !receivedAt.toUtc().isBefore(cutoff);
    }).map((signal) => Map<String, dynamic>.from(signal)).toList();
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
      _rememberMessage(_sanitizeMessage(message));
    }
  }

  Map<String, dynamic> _sanitizeMessage(Map<String, dynamic> message) {
    final copy = Map<String, dynamic>.from(message);
    final attachment = copy['attachment'];
    if (attachment is Map) {
      final clean = Map<String, dynamic>.from(attachment)
        ..remove('dataBase64')
        ..remove('localPath')
        ..remove('path');
      copy['attachment'] = clean;
    }
    return copy;
  }

  Future<void> _publishPresence() async {
    await _sendEnvelope(
      'presence',
      <String, dynamic>{
        'online': true,
        'at': DateTime.now().toUtc().toIso8601String(),
      },
      queueOnFailure: false,
    );
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
      'v': 7,
      'packetId': CgIds.random(24),
      'from': profileId,
      'name': nickname,
      'kind': kind,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
    final encrypted = await _encrypt(body);
    final orderedHosts = <String>[
      ..._sockets.keys,
      ...relayHosts.where((host) => !_sockets.containsKey(host)),
    ];
    String? successfulHost;
    Object? lastError;
    final fastPacket = kind == 'signal' ||
        kind == 'presence' ||
        kind == 'control' ||
        (kind == 'message' && encrypted.length <= 3500);
    if (fastPacket) {
      successfulHost = await _publishSignalFast(orderedHosts, encrypted);
    } else {
      for (final host in orderedHosts) {
        try {
          await _publishEncrypted(
            host,
            encrypted,
            cache: kind != 'presence',
            priority: 'default',
          );
          successfulHost = host;
          break;
        } catch (error) {
          lastError = error;
          _scheduleHostReconnect(host);
        }
      }
    }

    if (successfulHost != null) {
      _emit('status', const <String, dynamic>{
        'state': 'connected',
        'transport': 'encrypted_https443',
      });
      String? backup;
      for (final host in orderedHosts) {
        if (host != successfulHost) {
          backup = host;
          break;
        }
      }
      if (backup != null && kind != 'presence' && !fastPacket) {
        unawaited(
          _publishEncrypted(
            backup,
            encrypted,
            cache: true,
            priority: kind == 'signal' ? 'max' : 'high',
          ).catchError((_) {}),
        );
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
      final duplicate = uniqueId != null &&
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
        'state': 'offline',
        'code': 'relay_unavailable',
        'debug': lastError?.toString(),
      });
    }
    _scheduleGlobalReconnect();
  }

  Future<String?> _publishSignalFast(
    List<String> hosts,
    String encrypted,
  ) async {
    final selected = hosts.take(2).toList(growable: false);
    if (selected.isEmpty) return null;
    final completer = Completer<String?>();
    var completed = 0;
    for (final host in selected) {
      unawaited(
        _publishEncrypted(
          host,
          encrypted,
          cache: true,
          priority: 'max',
          timeout: const Duration(milliseconds: 2600),
        ).then((_) {
          if (!completer.isCompleted) completer.complete(host);
        }).catchError((Object error) {
          completed++;
          _scheduleHostReconnect(host);
          if (completed >= selected.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }),
      );
    }
    return completer.future.timeout(
      const Duration(milliseconds: 2800),
      onTimeout: () => null,
    );
  }

  Future<void> _publishEncrypted(
    String host,
    String encrypted, {
    required bool cache,
    String priority = 'default',
    Duration timeout = const Duration(seconds: 4),
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
            'Title': 'message',
            'Priority': priority,
            'Firebase': 'no',
            if (large) 'Filename': 'packet.cg',
            if (!cache) 'Cache': 'no',
          },
          body: large ? bytes : encrypted,
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('$host:${response.statusCode}');
    }
  }

  Future<void> _flushOutbox() async {
    if (_outbox.isEmpty || !connected) return;
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
    _presenceTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_publishPresence());
    });
    _peerCleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 32));
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
    final delay = Duration(seconds: 4 + (_reconnectAttempt * 2).clamp(0, 12).toInt());
    _relayRetryTimers[host] = Timer(delay, () {
      unawaited(_connectHost(host));
    });
  }

  void _scheduleGlobalReconnect() {
    if (_closed || connected || _globalRetryTimer?.isActive == true) return;
    _reconnectAttempt++;
    final seconds = (3 + _reconnectAttempt * 3).clamp(3, 18).toInt();
    _globalRetryTimer = Timer(Duration(seconds: seconds), () {
      _globalRetryTimer = null;
      unawaited(connect());
    });
  }

  void _emit(String type, [Map<String, dynamic> data = const <String, dynamic>{}]) {
    if (!_events.isClosed) _events.add(InternetEvent(type, data));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _globalRetryTimer?.cancel();
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
