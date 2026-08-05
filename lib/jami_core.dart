import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';
import 'internet_core.dart';

class CgJamiIdentity {
  final String accountId;
  final String address;
  final String deviceId;
  final String registrationState;

  const CgJamiIdentity({
    required this.accountId,
    required this.address,
    required this.deviceId,
    required this.registrationState,
  });

  factory CgJamiIdentity.fromMap(Map<dynamic, dynamic> map) => CgJamiIdentity(
    accountId: map['accountId']?.toString() ?? '',
    address: map['address']?.toString() ?? '',
    deviceId: map['deviceId']?.toString() ?? '',
    registrationState: map['registrationState']?.toString() ?? '',
  );
}

class CgJamiBridge {
  static const MethodChannel _methods = MethodChannel('chernogram/jami');
  static const EventChannel _nativeEvents = EventChannel(
    'chernogram/jami/events',
  );

  static final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);

  static StreamSubscription<dynamic>? _subscription;
  static Future<CgJamiIdentity?>? _initializing;
  static CgJamiIdentity? _identity;

  static Stream<Map<String, dynamic>> get events => _events.stream;
  static CgJamiIdentity? get identity => _identity;
  static String? get address => _identity?.address.trim().isEmpty == false
      ? _identity!.address.trim()
      : null;
  static bool get supported => Platform.isAndroid;

  static Future<CgJamiIdentity?> initialize(String nickname) {
    if (!supported) return Future<CgJamiIdentity?>.value(null);
    final existing = _identity;
    if (existing != null && existing.address.isNotEmpty) {
      return Future<CgJamiIdentity?>.value(existing);
    }
    return _initializing ??= _initialize(nickname);
  }

  static Future<CgJamiIdentity?> _initialize(String nickname) async {
    _subscription ??= _nativeEvents.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final event = Map<String, dynamic>.from(raw);
        if (event['type'] == 'identity') {
          _identity = CgJamiIdentity.fromMap(event);
        }
        if (!_events.isClosed) _events.add(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_events.isClosed) {
          _events.add(<String, dynamic>{
            'type': 'error',
            'message': error.toString(),
          });
        }
      },
    );
    try {
      final raw = await _methods.invokeMethod<dynamic>('initialize', <String, dynamic>{
        'nickname': nickname,
      });
      if (raw is! Map) return null;
      final identity = CgJamiIdentity.fromMap(raw);
      if (identity.accountId.isEmpty || identity.address.isEmpty) return null;
      _identity = identity;
      return identity;
    } on PlatformException {
      return null;
    } finally {
      _initializing = null;
    }
  }

  static Future<List<String>> send({
    required Iterable<String> peers,
    required String payload,
  }) async {
    if (!supported) return const <String>[];
    final unique = peers
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != address)
        .toSet()
        .toList(growable: false);
    if (unique.isEmpty) return const <String>[];
    final raw = await _methods.invokeMethod<dynamic>('send', <String, dynamic>{
      'peers': unique,
      'payload': payload,
    });
    if (raw is! List) return const <String>[];
    return raw.map((item) => item.toString()).toList(growable: false);
  }

  static Future<Map<String, dynamic>?> exportArchive({
    required String path,
    required String password,
  }) async {
    if (!supported) return null;
    final raw = await _methods.invokeMethod<dynamic>('exportArchive', <String, dynamic>{
      'path': path,
      'password': password,
    });
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }
}

class CgJamiRelay {
  static final Map<String, String> _seeds = <String, String>{};

  static void install() {
    InternetRelay.preferredFactory = open;
  }

  static void seed(String tunnelId, String? peerAddress) {
    final value = peerAddress?.trim() ?? '';
    if (value.isEmpty) return;
    _seeds[tunnelId] = value;
  }

  static Future<InternetTunnelSession> open({
    required String tunnelId,
    required String secret,
    required String profileId,
    required String nickname,
    required List<Map<String, dynamic>> history,
  }) async {
    final session = CgJamiTunnelSession(
      tunnelId: tunnelId,
      secret: secret,
      profileId: profileId,
      nickname: nickname,
      initialPeer: _seeds[tunnelId],
    )..replaceHistory(history);
    unawaited(session.connect());
    return session;
  }
}

class CgJamiTunnelSession extends InternetTunnelSession {
  static const int _chunkChars = 42000;
  static const Duration _peerLifetime = Duration(seconds: 75);

  final String? initialPeer;
  final StreamController<InternetEvent> _jamiEvents =
      StreamController<InternetEvent>.broadcast(sync: true);
  final Set<String> _peers = <String>{};
  final Map<String, String> _peerNames = <String, String>{};
  final Map<String, DateTime> _peerSeen = <String, DateTime>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _signalHistory = <Map<String, dynamic>>[];
  final Map<String, List<String?>> _incomingChunks = <String, List<String?>>{};

  StreamSubscription<Map<String, dynamic>>? _bridgeSubscription;
  Timer? _presenceTimer;
  Timer? _cleanupTimer;
  bool _jamiConnected = false;
  bool _closed = false;
  String? _secretDigest;

  CgJamiTunnelSession({
    required super.tunnelId,
    required super.secret,
    required super.profileId,
    required super.nickname,
    this.initialPeer,
  });

  String get _peersKey => 'cg_jami_peers_v1_$tunnelId';

  @override
  Stream<InternetEvent> get events => _jamiEvents.stream;

  @override
  bool get connected => _jamiConnected;

  @override
  int get onlinePeers {
    final cutoff = DateTime.now().subtract(_peerLifetime);
    return 1 + _peerSeen.values.where((time) => time.isAfter(cutoff)).length;
  }

  @override
  String? get roomKey => tunnelId;

  @override
  List<Map<String, dynamic>> get members {
    final cutoff = DateTime.now().subtract(_peerLifetime);
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': profileId,
        'name': nickname,
        'self': true,
        'seenAt': DateTime.now().toUtc().toIso8601String(),
      },
      ..._peerSeen.entries
          .where((entry) => entry.value.isAfter(cutoff))
          .map(
            (entry) => <String, dynamic>{
              'id': entry.key,
              'name': _peerNames[entry.key] ?? 'пользователь',
              'self': false,
              'seenAt': entry.value.toUtc().toIso8601String(),
            },
          ),
    ];
  }

  @override
  Future<void> connect() async {
    if (_closed || _jamiConnected) return;
    final identity = await CgJamiBridge.initialize(nickname);
    if (_closed) return;
    if (identity == null || identity.address.isEmpty) {
      _emit('status', const <String, dynamic>{
        'state': 'error',
        'transport': 'jami_core_unavailable',
      });
      return;
    }
    final digest = await Sha256().hash(utf8.encode('$tunnelId:$secret'));
    _secretDigest = base64Url.encode(digest.bytes).replaceAll('=', '');
    await _loadPeers();
    final seed = initialPeer?.trim() ?? '';
    if (seed.isNotEmpty && seed != identity.address) {
      _peers.add(seed);
      await _persistPeers();
    }
    _bridgeSubscription ??= CgJamiBridge.events.listen(_onBridgeEvent);
    _jamiConnected = true;
    _emit('status', const <String, dynamic>{
      'state': 'connected',
      'transport': 'jami_core',
    });
    _startTimers();
    await _sendEnvelope('presence', <String, dynamic>{
      'online': true,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
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

  Future<void> _loadPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_peersKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final self = CgJamiBridge.address;
      _peers.addAll(
        decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty && item != self),
      );
    } catch (_) {}
  }

  Future<void> _persistPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_peersKey, jsonEncode(_peers.toList()..sort()));
    } catch (_) {}
  }

  void _onBridgeEvent(Map<String, dynamic> event) {
    if (_closed) return;
    final type = event['type']?.toString() ?? '';
    if (type == 'message') {
      final from = event['from']?.toString().trim() ?? '';
      final payload = event['payload']?.toString() ?? '';
      if (from.isEmpty || payload.isEmpty || from == CgJamiBridge.address) return;
      unawaited(_receivePayload(from, payload));
    } else if (type == 'registration') {
      final state = event['state']?.toString() ?? '';
      _jamiConnected = state.isEmpty ||
          state == 'REGISTERED' ||
          state == 'TRYING' ||
          state == 'READY';
      _emit('status', <String, dynamic>{
        'state': _jamiConnected ? 'connected' : 'connecting',
        'transport': 'jami_core',
        'registration': state,
      });
    }
  }

  Future<void> _receivePayload(String fromAddress, String payload) async {
    Map<String, dynamic>? decoded;
    try {
      final raw = jsonDecode(payload);
      if (raw is Map) decoded = Map<String, dynamic>.from(raw);
    } catch (_) {
      return;
    }
    if (decoded == null) return;
    if (decoded['transport'] == 'chernogram-jami-chunk') {
      final packetId = decoded['packetId']?.toString() ?? '';
      final index = int.tryParse(decoded['index']?.toString() ?? '') ?? -1;
      final count = int.tryParse(decoded['count']?.toString() ?? '') ?? 0;
      final chunk = decoded['chunk']?.toString() ?? '';
      if (packetId.isEmpty || index < 0 || count <= 0 || chunk.isEmpty) return;
      final chunks = _incomingChunks.putIfAbsent(
        packetId,
        () => List<String?>.filled(count, null),
      );
      if (chunks.length != count || index >= count) return;
      chunks[index] = chunk;
      if (chunks.any((item) => item == null)) return;
      _incomingChunks.remove(packetId);
      await _receivePayload(fromAddress, chunks.cast<String>().join());
      return;
    }
    await _handleEnvelope(fromAddress, decoded);
  }

  Future<void> _handleEnvelope(
    String fromAddress,
    Map<String, dynamic> body,
  ) async {
    if (body['transport'] != 'chernogram-jami' ||
        body['tunnelId']?.toString() != tunnelId ||
        body['secret']?.toString() != _secretDigest) {
      return;
    }
    final packetId = body['packetId']?.toString() ?? '';
    if (packetId.isEmpty) return;
    final senderId = body['from']?.toString() ?? fromAddress;
    final senderName = body['name']?.toString() ?? 'пользователь';
    final kind = body['kind']?.toString() ?? '';
    final rawData = body['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    final isNewPeer = _peers.add(fromAddress);
    _peerSeen[senderId] = DateTime.now();
    _peerNames[senderId] = senderName;
    if (isNewPeer) unawaited(_persistPeers());
    _emit('peer', <String, dynamic>{
      'id': senderId,
      'name': senderName,
      'jamiAddress': fromAddress,
      'seenAt': DateTime.now().toUtc().toIso8601String(),
    });

    switch (kind) {
      case 'presence':
        _emitPresence();
        break;
      case 'message':
        final rawMessage = data['message'];
        if (rawMessage is Map) {
          final message = Map<String, dynamic>.from(rawMessage);
          _rememberMessage(message);
          _emit('message', <String, dynamic>{
            'message': message,
            'relaySender': senderId,
            'relaySenderName': senderName,
            'relayHost': 'jami_core',
          });
        }
        break;
      case 'history':
        final messages = ((data['messages'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        for (final message in messages) {
          _rememberMessage(message);
        }
        _emit('history', <String, dynamic>{
          'messages': messages,
          'relaySender': senderId,
          'relaySenderName': senderName,
        });
        break;
      case 'control':
        _emit('control', <String, dynamic>{
          ...data,
          'relaySender': senderId,
          'relaySenderName': senderName,
        });
        break;
      case 'signal':
        final signal = <String, dynamic>{
          ...data,
          'relaySender': senderId,
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

  @override
  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberMessage(message);
    await _sendEnvelope('message', <String, dynamic>{'message': message});
  }

  @override
  Future<void> sendControl(Map<String, dynamic> control) async {
    await _sendEnvelope('control', control);
  }

  @override
  Future<void> sendSignal(Map<String, dynamic> signal) async {
    await _sendEnvelope('signal', signal);
  }

  @override
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
        .toList(growable: false);
  }

  @override
  Future<void> sendHistory() async {
    if (_history.isEmpty) return;
    final start = math.max(0, _history.length - 120);
    await _sendEnvelope('history', <String, dynamic>{
      'messages': _history.skip(start).toList(growable: false),
    });
  }

  @override
  void replaceHistory(List<Map<String, dynamic>> messages) {
    _history
      ..clear()
      ..addAll(messages.map((item) => Map<String, dynamic>.from(item)));
    if (_history.length > 500) {
      _history.removeRange(0, _history.length - 500);
    }
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

  Future<void> _sendEnvelope(
    String kind,
    Map<String, dynamic> data,
  ) async {
    if (_closed) return;
    if (!connected) await connect();
    final digest = _secretDigest;
    if (!connected || digest == null || _peers.isEmpty) {
      _emit('status', const <String, dynamic>{
        'state': 'queued',
        'transport': 'jami_core',
      });
      return;
    }
    final packetId = CgIds.random(24);
    final body = jsonEncode(<String, dynamic>{
      'transport': 'chernogram-jami',
      'v': 1,
      'packetId': packetId,
      'tunnelId': tunnelId,
      'secret': digest,
      'from': profileId,
      'name': nickname,
      'fromAddress': CgJamiBridge.address,
      'kind': kind,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
    if (body.length <= _chunkChars) {
      await CgJamiBridge.send(peers: _peers, payload: body);
      return;
    }
    final count = (body.length / _chunkChars).ceil();
    for (var index = 0; index < count; index++) {
      final start = index * _chunkChars;
      final end = math.min(start + _chunkChars, body.length);
      final wrapper = jsonEncode(<String, dynamic>{
        'transport': 'chernogram-jami-chunk',
        'packetId': packetId,
        'index': index,
        'count': count,
        'chunk': body.substring(start, end),
      });
      await CgJamiBridge.send(peers: _peers, payload: wrapper);
    }
  }

  @override
  Future<void> pullNow() async {
    if (!connected) await connect();
    if (connected) {
      await _sendEnvelope('presence', <String, dynamic>{
        'online': true,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  void _startTimers() {
    _presenceTimer?.cancel();
    _cleanupTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(pullNow());
    });
    _cleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final cutoff = DateTime.now().subtract(_peerLifetime);
      _peerSeen.removeWhere((_, time) => time.isBefore(cutoff));
      _emitPresence();
    });
  }

  void _emitPresence() {
    _emit('presence', <String, dynamic>{
      'peers': onlinePeers,
      'members': members,
    });
  }

  void _emit(String type, [Map<String, dynamic> data = const <String, dynamic>{}]) {
    if (!_jamiEvents.isClosed) _jamiEvents.add(InternetEvent(type, data));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _jamiConnected = false;
    _presenceTimer?.cancel();
    _cleanupTimer?.cancel();
    await _bridgeSubscription?.cancel();
    await _jamiEvents.close();
  }
}
