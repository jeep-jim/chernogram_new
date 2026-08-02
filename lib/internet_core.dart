import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';
import 'push_service.dart';

const String _impulseBaseUrl = String.fromEnvironment('IMPULSE_BASE_URL');

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
      nextAttemptAt: DateTime.tryParse(
        json['nextAttemptAt']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

class InternetTunnelSession {
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

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  Timer? _presenceTimer;
  Timer? _peerCleanupTimer;
  Timer? _outboxTimer;
  SecretKey? _secretKey;
  String? _roomKey;
  String? _authToken;
  bool _closed = false;
  bool _connecting = false;
  bool _httpReady = false;
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
  bool get connected => _httpReady || _socket != null;
  int get onlinePeers => _peers.length + 1;
  String? get roomKey => _roomKey;

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

  String get _outboxKey => 'cg_impulse_outbox_v1_${tunnelId}_$profileId';

  bool get _configured => _impulseBaseUrl.trim().isNotEmpty;

  Uri _endpoint(String action, {Map<String, String>? query}) {
    final base = Uri.parse(_impulseBaseUrl.trim());
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$prefix/v1/rooms/${_roomKey!}/$action',
      queryParameters: query,
    );
  }

  Map<String, String> get _headers => <String, String>{
    'authorization': 'Bearer ${_authToken!}',
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  };

  Future<void> connect() async {
    if (_closed || _connecting || connected) return;
    _connecting = true;
    try {
      if (!_configured) {
        _emit('status', const <String, dynamic>{
          'state': 'error',
          'transport': 'impulse_missing',
        });
        return;
      }
      await _prepareCryptoAndRoom();
      await _loadOutbox();
      await CgPushService.initialize();
      await _registerDevice();
      await _connectSocket();
      await pullNow();
      _startTimers();
      _reconnectAttempt = 0;
      _emit('status', const <String, dynamic>{
        'state': 'connected',
        'transport': 'impulse_worker',
      });
      unawaited(_publishPresence());
      unawaited(_flushOutbox());
    } catch (_) {
      _httpReady = false;
      _emit('status', const <String, dynamic>{
        'state': 'queued',
        'transport': 'impulse_worker',
      });
      _scheduleReconnect();
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

  Future<void> _prepareCryptoAndRoom() async {
    if (_secretKey != null && _roomKey != null && _authToken != null) return;
    final content = await Sha256().hash(
      utf8.encode('content:$tunnelId:$secret'),
    );
    final room = await Sha256().hash(utf8.encode('room:$tunnelId:$secret'));
    final auth = await Sha256().hash(utf8.encode('auth:$tunnelId:$secret'));
    _secretKey = SecretKey(content.bytes);
    _roomKey = base64Url.encode(room.bytes).replaceAll('=', '');
    _authToken = base64Url.encode(auth.bytes).replaceAll('=', '');
  }

  Future<void> _registerDevice() async {
    await _prepareCryptoAndRoom();
    final token = CgPushService.token ?? await CgPushService.refreshToken();
    final response = await _http
        .post(
          _endpoint('register'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'deviceId': profileId,
            'name': nickname,
            if (token != null && token.isNotEmpty) 'fcmToken': token,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Impulse register: ${response.statusCode}');
    }
    _httpReady = true;
  }

  Future<void> _connectSocket() async {
    await _prepareCryptoAndRoom();
    await _socketSubscription?.cancel();
    final old = _socket;
    _socket = null;
    if (old != null) {
      try {
        await old.close();
      } catch (_) {}
    }

    final httpUri = _endpoint(
      'ws',
      query: <String, String>{'device': profileId, 'name': nickname},
    );
    final wsUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    );
    final socket = await WebSocket.connect(
      wsUri.toString(),
      headers: <String, dynamic>{'authorization': 'Bearer ${_authToken!}'},
    ).timeout(const Duration(seconds: 7));
    socket.pingInterval = const Duration(seconds: 25);
    _socket = socket;
    _socketSubscription = socket.listen(
      (raw) => unawaited(_handleSocket(raw)),
      onError: (_) => _onSocketClosed(),
      onDone: _onSocketClosed,
      cancelOnError: true,
    );
  }

  Future<void> _handleSocket(dynamic raw) async {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      if (map['type']?.toString() != 'envelope' || map['envelope'] is! Map) {
        return;
      }
      await _handleOuterEnvelope(
        Map<String, dynamic>.from(map['envelope'] as Map),
        'impulse_ws',
      );
    } catch (_) {}
  }

  void _onSocketClosed() {
    if (_closed) return;
    _socket = null;
    unawaited(_socketSubscription?.cancel());
    _socketSubscription = null;
    _scheduleReconnect();
  }

  Future<void> pullNow() async {
    if (_closed || !_configured) return;
    try {
      await _prepareCryptoAndRoom();
      if (!_httpReady) await _registerDevice();
      final response = await _http
          .get(
            _endpoint('pull', query: <String, String>{'device': profileId}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Impulse pull: ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final envelopes = decoded is Map
          ? ((decoded['envelopes'] as List?) ?? const <dynamic>[])
          : const <dynamic>[];
      for (final item in envelopes.whereType<Map>()) {
        await _handleOuterEnvelope(
          Map<String, dynamic>.from(item),
          'impulse_pull',
        );
      }
      _httpReady = true;
      _emit('status', const <String, dynamic>{
        'state': 'connected',
        'transport': 'impulse_worker',
      });
    } catch (_) {
      _httpReady = false;
      _scheduleReconnect();
    }
  }

  Future<void> _handleOuterEnvelope(
    Map<String, dynamic> outer,
    String source,
  ) async {
    final packetId = outer['packetId']?.toString() ?? '';
    final encrypted = outer['ciphertext']?.toString() ?? '';
    if (packetId.isEmpty || encrypted.isEmpty) return;
    final body = await _decrypt(encrypted);
    if (body == null) return;
    final bodyPacketId = body['packetId']?.toString() ?? '';
    if (bodyPacketId != packetId) return;

    final duplicate = !_seenPackets.add(packetId);
    if (_seenPackets.length > 10000) _seenPackets.remove(_seenPackets.first);
    unawaited(_ack(<String>[packetId]));
    if (duplicate) return;

    final sender = body['from']?.toString() ?? '';
    if (sender.isEmpty || sender == profileId) return;
    final kind = body['kind']?.toString() ?? '';
    final rawData = body['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    final sentAt = DateTime.tryParse(body['sentAt']?.toString() ?? '');
    if (kind == 'signal' &&
        sentAt != null &&
        DateTime.now().toUtc().difference(sentAt.toUtc()).inSeconds.abs() >
            180) {
      return;
    }

    final senderName = body['name']?.toString() ?? 'пользователь';
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
          meta.putIfAbsent(
            'relayAt',
            () => DateTime.now().toUtc().toIso8601String(),
          );
          message['meta'] = meta;
          _rememberMessage(_sanitizeMessage(message));
          final transferId = meta['fileTransferId']?.toString() ?? '';
          if (transferId.isNotEmpty) {
            _pendingFileManifests[transferId] = message;
            _emitMessage(message, sender, senderName, source);
            _tryCompleteFile(transferId, sender, senderName, source);
          } else {
            _emitMessage(message, sender, senderName, source);
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
        _tryCompleteFile(transferId, sender, senderName, source);
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
          'sentAt': body['sentAt'],
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
        };
        _signalHistory.add(signal);
        if (_signalHistory.length > 300) {
          _signalHistory.removeRange(0, _signalHistory.length - 300);
        }
        _emit('signal', signal);
        break;
    }
  }

  Future<void> _ack(List<String> packetIds) async {
    if (packetIds.isEmpty || _closed || !_configured) return;
    try {
      await _http
          .post(
            _endpoint('ack'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'packetIds': packetIds}),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
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

  void _tryCompleteFile(
    String transferId,
    String sender,
    String senderName,
    String source,
  ) {
    final manifest = _pendingFileManifests[transferId];
    final chunks = _pendingFileChunks[transferId];
    if (manifest == null ||
        chunks == null ||
        chunks.any((item) => item == null)) {
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
    _emitMessage(manifest, sender, senderName, source);
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
      await Future.wait(<Future<void>>[
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
      ]);
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
    return _signalHistory
        .where((signal) {
          if (signal['callId']?.toString() != callId) return false;
          final receivedAt = DateTime.tryParse(
            signal['receivedAt']?.toString() ?? '',
          );
          return receivedAt == null || !receivedAt.toUtc().isBefore(cutoff);
        })
        .map((signal) => Map<String, dynamic>.from(signal))
        .toList();
  }

  Future<void> sendHistory() async {
    if (_history.isEmpty) return;
    final start = _history.length > 120 ? _history.length - 120 : 0;
    final recent = _history.skip(start).toList(growable: false);
    final plain = recent
        .where((message) {
          final id = message['id']?.toString() ?? '';
          return !_filePayloads.containsKey(id);
        })
        .toList(growable: false);
    if (plain.isNotEmpty) {
      await _sendEnvelope('history', <String, dynamic>{
        'messages': plain,
      }, queueOnFailure: false);
    }
  }

  void replaceHistory(List<Map<String, dynamic>> messages) {
    _history.clear();
    for (final message in messages) {
      _rememberLocalFile(message);
      _rememberMessage(_sanitizeMessage(message));
    }
  }

  Future<void> _publishPresence() async {
    await _registerDevice();
    await _sendEnvelope('presence', <String, dynamic>{
      'online': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    }, queueOnFailure: false);
  }

  Future<void> _sendEnvelope(
    String kind,
    Map<String, dynamic> data, {
    bool queueOnFailure = true,
    String? packetId,
  }) async {
    if (_closed) return;
    await _prepareCryptoAndRoom();
    final queued = _QueuedEnvelope(
      packetId: packetId ?? CgIds.random(24),
      kind: kind,
      data: Map<String, dynamic>.from(data),
      createdAt: DateTime.now(),
    );
    final reliable =
        queueOnFailure &&
        (kind == 'message' || kind == 'control' || kind == 'file_chunk');
    if (reliable) {
      _outbox.putIfAbsent(queued.packetId, () => queued);
      unawaited(_persistOutbox());
    }
    final sent = await _transmit(queued);
    if (sent && reliable) {
      _outbox.remove(queued.packetId);
      unawaited(_persistOutbox());
    } else if (!sent && reliable) {
      queued.nextAttemptAt = DateTime.now().add(const Duration(seconds: 3));
      _scheduleReconnect();
    }
  }

  String _wakeFor(_QueuedEnvelope envelope) {
    if (envelope.kind == 'message' || envelope.kind == 'file_chunk') {
      return 'message';
    }
    if (envelope.kind == 'signal') {
      final action = envelope.data['action']?.toString() ?? '';
      if (action == 'call_invite' || action == 'group_call_invite') {
        return 'call';
      }
    }
    return 'none';
  }

  Future<bool> _transmit(_QueuedEnvelope envelope) async {
    if (_closed || !_configured) return false;
    try {
      await _prepareCryptoAndRoom();
      if (!_httpReady) await _registerDevice();
      final body = <String, dynamic>{
        'v': 9,
        'packetId': envelope.packetId,
        'from': profileId,
        'name': nickname,
        'kind': envelope.kind,
        'sentAt': envelope.createdAt.toUtc().toIso8601String(),
        'data': envelope.data,
      };
      final encrypted = await _encrypt(body);
      final response = await _http
          .post(
            _endpoint('envelopes'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'packetId': envelope.packetId,
              'from': profileId,
              'kind': envelope.kind,
              'wake': _wakeFor(envelope),
              if (_wakeFor(envelope) == 'call')
                'video': envelope.data['video'] == true,
              'ciphertext': encrypted,
              'createdAt': envelope.createdAt.millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final success = response.statusCode >= 200 && response.statusCode < 300;
      if (success) {
        _httpReady = true;
        _emit('status', const <String, dynamic>{
          'state': 'connected',
          'transport': 'impulse_worker',
        });
      }
      return success;
    } catch (_) {
      _httpReady = false;
      _scheduleReconnect();
      return false;
    }
  }

  Future<String> _encrypt(Map<String, dynamic> body) async {
    await _prepareCryptoAndRoom();
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
      await _prepareCryptoAndRoom();
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
      final values = _outbox.values
          .where((item) => jsonEncode(item.toJson()).length < 1600000)
          .take(80)
          .map((item) => item.toJson())
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_outboxKey, jsonEncode(values));
    } catch (_) {}
  }

  Future<void> _flushOutbox() async {
    if (_flushing || _closed || _outbox.isEmpty) return;
    _flushing = true;
    try {
      final now = DateTime.now();
      final pending = _outbox.values
          .where((item) => !item.nextAttemptAt.isAfter(now))
          .take(24)
          .toList();
      for (final item in pending) {
        final sent = await _transmit(item);
        item.attempts++;
        if (sent) {
          _outbox.remove(item.packetId);
        } else {
          final seconds = (3 + item.attempts * 2).clamp(3, 30).toInt();
          item.nextAttemptAt = DateTime.now().add(Duration(seconds: seconds));
        }
      }
      await _persistOutbox();
    } finally {
      _flushing = false;
    }
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _outboxTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_socket == null) unawaited(pullNow());
    });
    _presenceTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_publishPresence());
    });
    _peerCleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 55));
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

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer?.isActive == true) return;
    _reconnectAttempt++;
    final seconds = (2 + _reconnectAttempt * 2).clamp(2, 18).toInt();
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
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
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _outboxTimer?.cancel();
    await _socketSubscription?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    _http.close();
    await _events.close();
  }
}

class InternetRelay {
  static final Map<String, InternetTunnelSession> _sessions =
      <String, InternetTunnelSession>{};
  static StreamSubscription<CgPushEvent>? _pushSubscription;

  static InternetTunnelSession? session(String tunnelId) => _sessions[tunnelId];

  static Future<void> _ensurePushListener() async {
    if (_pushSubscription != null) return;
    await CgPushService.initialize();
    _pushSubscription = CgPushService.events.listen((_) {
      for (final session in _sessions.values) {
        unawaited(session.pullNow());
      }
    });
  }

  static Future<InternetTunnelSession> open({
    required String tunnelId,
    required String secret,
    required String profileId,
    required String nickname,
    required List<Map<String, dynamic>> history,
  }) async {
    unawaited(_ensurePushListener());
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
    // Sessions are shared by the chat, call screen and background monitor.
  }

  static Future<void> refreshAll() async {
    await Future.wait(_sessions.values.map((session) => session.pullNow()));
  }

  static Future<void> shutdownAll() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    await _pushSubscription?.cancel();
    _pushSubscription = null;
    for (final session in sessions) {
      await session.close();
    }
  }
}
