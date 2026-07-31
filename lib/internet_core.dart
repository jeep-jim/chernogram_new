import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';

class InternetEvent {
  final String type;
  final Map<String, dynamic> data;

  const InternetEvent(this.type, [this.data = const <String, dynamic>{}]);
}

class _QueuedEnvelope {
  final String packetId;
  final String kind;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int attempts;
  DateTime nextAttemptAt;

  _QueuedEnvelope({
    required this.packetId,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.attempts = 0,
    DateTime? nextAttemptAt,
  }) : nextAttemptAt = nextAttemptAt ?? DateTime.now();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'packetId': packetId,
    'kind': kind,
    'data': data,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
  };

  factory _QueuedEnvelope.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return _QueuedEnvelope(
      packetId: json['packetId']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{},
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      nextAttemptAt:
          DateTime.tryParse(json['nextAttemptAt']?.toString() ?? '')
              ?.toLocal(),
    );
  }
}

class InternetTunnelSession {
  static const List<String> relayHosts = <String>[
    'ntfy.sh',
    'ntfy.jae.fi',
  ];

  static const int _inlineFileChars = 300000;
  static const int _fileChunkChars = 220000;
  static const Duration _packetLifetime = Duration(hours: 24);

  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;

  final StreamController<InternetEvent> _events =
      StreamController<InternetEvent>.broadcast(sync: true);
  final http.Client _http = http.Client();
  final Map<String, WebSocket> _sockets = <String, WebSocket>{};
  final Map<String, StreamSubscription<dynamic>> _socketSubscriptions =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, Timer> _relayRetryTimers = <String, Timer>{};
  final Set<String> _connectingHosts = <String>{};
  final Set<String> _seenPackets = <String>{};
  final Map<String, DateTime> _peers = <String, DateTime>{};
  final Map<String, String> _peerNames = <String, String>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _signalHistory = <Map<String, dynamic>>[];
  final Map<String, _QueuedEnvelope> _outbox = <String, _QueuedEnvelope>{};
  final Map<String, String> _filePayloads = <String, String>{};
  final Map<String, Map<String, dynamic>> _fileMessages =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _pendingFileManifests =
      <String, Map<String, dynamic>>{};
  final Map<String, List<String?>> _pendingFileChunks =
      <String, List<String?>>{};

  Timer? _presenceTimer;
  Timer? _peerCleanupTimer;
  Timer? _globalRetryTimer;
  Timer? _outboxTimer;
  SecretKey? _secretKey;
  String? _topic;
  bool _closed = false;
  bool _connecting = false;
  bool _outboxLoaded = false;
  bool _flushing = false;
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

  String get _outboxKey => 'cg_outbox_v2_${tunnelId}_$profileId';

  Future<void> connect() async {
    if (_closed || _connecting || connected) return;
    _connecting = true;
    try {
      await _prepareCryptoAndTopic();
      await _loadOutbox();
      final futures = relayHosts.map(_connectHost).toList(growable: false);
      await Future.wait(futures).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <bool>[],
      );
      if (_closed) return;
      if (connected) {
        _reconnectAttempt = 0;
        _globalRetryTimer?.cancel();
        _startTimers();
        unawaited(_publishPresence());
        unawaited(_flushOutbox());
        _emit('status', const <String, dynamic>{
          'state': 'connected',
          'transport': 'encrypted_relay',
        });
      } else {
        _emit('status', const <String, dynamic>{
          'state': 'queued',
          'transport': 'encrypted_relay',
        });
        _scheduleGlobalReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  Future<bool> waitUntilConnected([
    Duration timeout = const Duration(seconds: 4),
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

  Future<bool> _connectHost(String host) async {
    if (_closed || _sockets.containsKey(host) || !_connectingHosts.add(host)) {
      return _sockets.containsKey(host);
    }
    try {
      await _prepareCryptoAndTopic();
      final socket = await WebSocket.connect(
        Uri(
          scheme: 'wss',
          host: host,
          path: '/${_topic!}/ws',
          queryParameters: const <String, String>{'since': '30m'},
        ).toString(),
      ).timeout(const Duration(seconds: 4));
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
        onError: (Object error) => _onHostDisconnected(host),
        onDone: () => _onHostDisconnected(host),
        cancelOnError: true,
      );
      _emit('status', const <String, dynamic>{
        'state': 'connected',
        'transport': 'encrypted_relay',
      });
      unawaited(_flushOutbox());
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
    _topic = 'cg_${base64Url.encode(hash.bytes).replaceAll('=', '')}';
  }

  Future<void> _handleSocketMessage(String host, dynamic raw) async {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      if (message['event']?.toString() != 'message') return;
      String? encrypted;
      final attachment = message['attachment'];
      if (attachment is Map) {
        final url = attachment['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final response = await _http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 20));
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

  void _onHostDisconnected(String host) {
    if (_closed) return;
    _sockets.remove(host);
    final subscription = _socketSubscriptions.remove(host);
    if (subscription != null) unawaited(subscription.cancel());
    _scheduleHostReconnect(host);
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
    if (packetId.isEmpty || sender.isEmpty || sender == profileId) return;

    final duplicate = !_seenPackets.add(packetId);
    if (_seenPackets.length > 10000) _seenPackets.remove(_seenPackets.first);
    final kind = envelope['kind']?.toString() ?? '';
    final rawData = envelope['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (kind == 'ack') {
      if (data['target']?.toString() == profileId) {
        final ackPacketId = data['ackPacketId']?.toString() ?? '';
        if (ackPacketId.isNotEmpty && _outbox.remove(ackPacketId) != null) {
          unawaited(_persistOutbox());
        }
      }
      return;
    }

    unawaited(
      _sendEnvelope(
        'ack',
        <String, dynamic>{
          'ackPacketId': packetId,
          'target': sender,
        },
        queueOnFailure: false,
      ),
    );
    if (duplicate) return;

    final sentAt = DateTime.tryParse(envelope['sentAt']?.toString() ?? '');
    if (kind == 'signal' &&
        sentAt != null &&
        DateTime.now().toUtc().difference(sentAt.toUtc()).inSeconds.abs() >
            120) {
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

    switch (kind) {
      case 'presence':
        break;
      case 'message':
        final rawMessage = data['message'];
        if (rawMessage is Map) {
          final message = Map<String, dynamic>.from(rawMessage);
          final rawMeta = message['meta'];
          final meta = rawMeta is Map
              ? Map<String, dynamic>.from(rawMeta)
              : <String, dynamic>{};
          meta.putIfAbsent('relayAt', () => relayAt.toIso8601String());
          message['meta'] = meta;
          _rememberMessage(_sanitizeMessage(message));
          final transferId = meta['fileTransferId']?.toString() ?? '';
          if (transferId.isNotEmpty) {
            _pendingFileManifests[transferId] = message;
            _emitMessage(message, sender, senderName, relayHost);
            _tryCompleteFile(transferId, sender, senderName, relayHost);
          } else {
            _emitMessage(message, sender, senderName, relayHost);
          }
        }
        break;
      case 'file_chunk':
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
        _tryCompleteFile(transferId, sender, senderName, relayHost);
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

  void _emitMessage(
    Map<String, dynamic> message,
    String sender,
    String senderName,
    String relayHost,
  ) {
    _emit('message', <String, dynamic>{
      'message': message,
      'relaySender': sender,
      'relaySenderName': senderName,
      'relayHost': relayHost,
    });
  }

  void _tryCompleteFile(
    String transferId,
    String sender,
    String senderName,
    String relayHost,
  ) {
    final manifest = _pendingFileManifests[transferId];
    final chunks = _pendingFileChunks[transferId];
    if (manifest == null || chunks == null || chunks.any((item) => item == null)) {
      return;
    }
    final rawAttachment = manifest['attachment'];
    if (rawAttachment is! Map) return;
    final attachment = Map<String, dynamic>.from(rawAttachment);
    attachment['dataBase64'] = chunks.cast<String>().join();
    manifest['attachment'] = attachment;
    final rawMeta = manifest['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};
    meta['fileReady'] = true;
    manifest['meta'] = meta;
    _pendingFileManifests.remove(transferId);
    _pendingFileChunks.remove(transferId);
    _rememberMessage(_sanitizeMessage(manifest));
    _emitMessage(manifest, sender, senderName, relayHost);
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberLocalFile(message);
    _rememberMessage(_sanitizeMessage(message));
    final payload = _filePayloadFor(message);
    if (payload == null || payload.length <= _inlineFileChars) {
      await _sendEnvelope('message', <String, dynamic>{'message': message});
      return;
    }
    await _sendLargeFileMessage(message, payload);
  }

  Future<void> _sendLargeFileMessage(
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
    await _sendEnvelope('message', <String, dynamic>{'message': manifest});

    for (var start = 0; start < count; start += 4) {
      final end = math.min(start + 4, count);
      await Future.wait(
        <Future<void>>[
          for (var index = start; index < end; index++)
            _sendEnvelope('file_chunk', <String, dynamic>{
              'transferId': transferId,
              'messageId': messageId,
              'index': index,
              'count': count,
              'chunk': payload.substring(
                index * _fileChunkChars,
                math.min((index + 1) * _fileChunkChars, payload.length),
              ),
            }),
        ],
      );
    }
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
      final receivedAt = DateTime.tryParse(
        signal['receivedAt']?.toString() ?? '',
      );
      return receivedAt == null || !receivedAt.toUtc().isBefore(cutoff);
    }).map((signal) => Map<String, dynamic>.from(signal)).toList();
  }

  Future<void> sendHistory() async {
    if (_history.isEmpty) return;
    final start = _history.length > 120 ? _history.length - 120 : 0;
    final recent = _history.skip(start).toList(growable: false);
    final plain = recent.where((message) {
      final id = message['id']?.toString() ?? '';
      return !_filePayloads.containsKey(id);
    }).toList(growable: false);
    if (plain.isNotEmpty) {
      await _sendEnvelope(
        'history',
        <String, dynamic>{'messages': plain},
        queueOnFailure: false,
      );
    }
    final files = recent
        .where((message) => _filePayloads.containsKey(message['id']?.toString()))
        .toList(growable: false);
    for (final message in files.take(12)) {
      final id = message['id']?.toString() ?? '';
      final original = _fileMessages[id];
      final payload = _filePayloads[id];
      if (original != null && payload != null) {
        if (payload.length <= _inlineFileChars) {
          await _sendEnvelope(
            'message',
            <String, dynamic>{'message': original},
            queueOnFailure: false,
          );
        } else {
          await _sendLargeFileMessage(original, payload);
        }
      }
    }
  }

  void replaceHistory(List<Map<String, dynamic>> messages) {
    _history.clear();
    for (final message in messages) {
      _rememberLocalFile(message);
      _rememberMessage(_sanitizeMessage(message));
    }
  }

  void _rememberLocalFile(Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final rawAttachment = message['attachment'];
    if (rawAttachment is! Map) return;
    final attachment = Map<String, dynamic>.from(rawAttachment);
    final payload = attachment['dataBase64']?.toString();
    if (payload == null || payload.isEmpty) return;
    _filePayloads[id] = payload;
    _fileMessages[id] = Map<String, dynamic>.from(message);
  }

  String? _filePayloadFor(Map<String, dynamic> message) {
    final rawAttachment = message['attachment'];
    if (rawAttachment is! Map) return null;
    return rawAttachment['dataBase64']?.toString();
  }

  Map<String, dynamic> _sanitizeMessage(Map<String, dynamic> message) {
    final copy = Map<String, dynamic>.from(message);
    final attachment = copy['attachment'];
    if (attachment is Map) {
      copy['attachment'] = Map<String, dynamic>.from(attachment)
        ..remove('dataBase64')
        ..remove('localPath')
        ..remove('path');
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
    String? packetId,
  }) async {
    if (_closed) return;
    final queued = _QueuedEnvelope(
      packetId: packetId ?? CgIds.random(24),
      kind: kind,
      data: Map<String, dynamic>.from(data),
      createdAt: DateTime.now(),
    );
    final reliable = queueOnFailure &&
        (kind == 'message' || kind == 'control' || kind == 'file_chunk');
    if (reliable) {
      _outbox.putIfAbsent(queued.packetId, () => queued);
      unawaited(_persistOutbox());
    }
    final sent = await _transmit(queued);
    if (!sent && reliable) {
      queued.nextAttemptAt = DateTime.now().add(const Duration(seconds: 3));
      _scheduleGlobalReconnect();
    }
  }

  Future<bool> _transmit(_QueuedEnvelope envelope) async {
    if (_closed) return false;
    await _prepareCryptoAndTopic();
    if (!connected) unawaited(connect());
    final body = <String, dynamic>{
      'v': 8,
      'packetId': envelope.packetId,
      'from': profileId,
      'name': nickname,
      'kind': envelope.kind,
      'sentAt': envelope.createdAt.toUtc().toIso8601String(),
      'data': envelope.data,
    };
    final encrypted = await _encrypt(body);
    final hosts = <String>{..._sockets.keys, ...relayHosts}.toList();
    if (hosts.isEmpty) return false;
    final futures = hosts.take(2).map(
      (host) => _publishEncrypted(
        host,
        encrypted,
        cache: envelope.kind != 'presence' && envelope.kind != 'ack',
        priority: envelope.kind == 'signal' ? 'max' : 'high',
      ).then((_) => true).catchError((_) {
        _scheduleHostReconnect(host);
        return false;
      }),
    );
    final results = await Future.wait(futures);
    final success = results.any((item) => item);
    if (success) {
      _emit('status', const <String, dynamic>{
        'state': 'connected',
        'transport': 'encrypted_relay',
      });
    }
    return success;
  }

  Future<void> _publishEncrypted(
    String host,
    String encrypted, {
    required bool cache,
    String priority = 'default',
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
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('$host:${response.statusCode}');
    }
  }

  Future<void> _loadOutbox() async {
    if (_outboxLoaded) return;
    _outboxLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_outboxKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded.whereType<Map>()) {
        final envelope = _QueuedEnvelope.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (envelope.packetId.isNotEmpty && envelope.kind.isNotEmpty) {
          _outbox[envelope.packetId] = envelope;
        }
      }
    } catch (_) {}
  }

  Future<void> _persistOutbox() async {
    if (!_outboxLoaded) return;
    try {
      final now = DateTime.now();
      _outbox.removeWhere(
        (_, item) => now.difference(item.createdAt) > _packetLifetime,
      );
      final persistable = _outbox.values.where((item) {
        try {
          return jsonEncode(item.toJson()).length < 180000;
        } catch (_) {
          return false;
        }
      }).map((item) => item.toJson()).toList(growable: false);
      final prefs = await SharedPreferences.getInstance();
      if (persistable.isEmpty) {
        await prefs.remove(_outboxKey);
      } else {
        await prefs.setString(_outboxKey, jsonEncode(persistable));
      }
    } catch (_) {}
  }

  Future<void> _flushOutbox() async {
    if (_flushing || _closed) return;
    await _loadOutbox();
    if (_outbox.isEmpty) return;
    _flushing = true;
    try {
      final now = DateTime.now();
      final pending = _outbox.values
          .where(
            (item) =>
                !item.nextAttemptAt.isAfter(now) &&
                now.difference(item.createdAt) <= _packetLifetime,
          )
          .take(24)
          .toList(growable: false);
      for (final item in pending) {
        final sent = await _transmit(item);
        item.attempts++;
        final seconds = sent
            ? 8
            : (3 + item.attempts * 2).clamp(3, 30).toInt();
        item.nextAttemptAt = DateTime.now().add(Duration(seconds: seconds));
      }
      unawaited(_persistOutbox());
    } finally {
      _flushing = false;
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
    } else {
      _history.add(Map<String, dynamic>.from(message));
    }
    if (_history.length > 500) {
      _history.removeRange(0, _history.length - 500);
    }
    return true;
  }

  void _startTimers() {
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _outboxTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      unawaited(_publishPresence());
    });
    _peerCleanupTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 45));
      final removed = _peers.keys
          .where((id) => _peers[id]?.isBefore(cutoff) == true)
          .toList();
      for (final id in removed) {
        _peers.remove(id);
        _peerNames.remove(id);
      }
      _emitPresence();
    });
    _outboxTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_flushOutbox());
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
    final seconds = (3 + _reconnectAttempt * 2).clamp(3, 15).toInt();
    _relayRetryTimers[host] = Timer(Duration(seconds: seconds), () {
      unawaited(_connectHost(host));
    });
  }

  void _scheduleGlobalReconnect() {
    if (_closed || connected || _globalRetryTimer?.isActive == true) return;
    _reconnectAttempt++;
    final seconds = (2 + _reconnectAttempt * 2).clamp(2, 16).toInt();
    _globalRetryTimer = Timer(Duration(seconds: seconds), () {
      _globalRetryTimer = null;
      unawaited(connect());
    });
  }

  void _emit(
    String type, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) {
    if (!_events.isClosed) _events.add(InternetEvent(type, data));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _globalRetryTimer?.cancel();
    _outboxTimer?.cancel();
    for (final timer in _relayRetryTimers.values) {
      timer.cancel();
    }
    for (final subscription in _socketSubscriptions.values) {
      await subscription.cancel();
    }
    for (final socket in _sockets.values) {
      await socket.close();
    }
    _relayRetryTimers.clear();
    _socketSubscriptions.clear();
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
    // Normal screens share one session. Closing it from a background monitor
    // used to disconnect an active chat or call. A secret change is handled by
    // open(), which replaces the incompatible session safely.
  }

  static Future<void> shutdownAll() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.close();
    }
  }
}
