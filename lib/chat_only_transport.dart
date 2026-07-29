import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

class ChatOnlyMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;

  const ChatOnlyMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'senderId': senderId,
    'text': text,
    'sentAt': sentAt.toUtc().toIso8601String(),
  };

  factory ChatOnlyMessage.fromJson(Map<String, dynamic> json) {
    return ChatOnlyMessage(
      id: json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      sentAt:
          DateTime.tryParse(json['sentAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class ChatOnlyTransport {
  static const List<String> _relays = <String>[
    'ntfy.sh',
    'ntfy.jae.fi',
    'ntfy.envs.net',
  ];

  final String roomId;
  final String secret;
  final String deviceId;
  final StreamController<ChatOnlyMessage> _incoming =
      StreamController<ChatOnlyMessage>.broadcast(sync: true);
  final Map<String, WebSocket> _sockets = <String, WebSocket>{};
  final Map<String, StreamSubscription<dynamic>> _subscriptions =
      <String, StreamSubscription<dynamic>>{};
  final Map<String, Timer> _reconnectTimers = <String, Timer>{};
  final Set<String> _connecting = <String>{};
  final Set<String> _seen = <String>{};
  final http.Client _http = http.Client();

  SecretKey? _key;
  String? _topic;
  bool _closed = false;

  ChatOnlyTransport({
    required this.roomId,
    required this.secret,
    required this.deviceId,
  });

  Stream<ChatOnlyMessage> get incoming => _incoming.stream;

  Future<void> start() async {
    await _prepare();
    for (final relay in _relays) {
      unawaited(_connect(relay));
    }
  }

  Future<void> _prepare() async {
    if (_key != null && _topic != null) return;
    final digest = await Sha256().hash(utf8.encode('$roomId:$secret'));
    _key = SecretKey(digest.bytes);
    _topic = 'cg_${base64Url.encode(digest.bytes).replaceAll('=', '')}';
  }

  Future<void> _connect(String relay) async {
    if (_closed || _sockets.containsKey(relay) || !_connecting.add(relay)) {
      return;
    }
    try {
      await _prepare();
      final socket = await WebSocket.connect(
        'wss://$relay/${_topic!}/ws?since=12h',
      ).timeout(const Duration(seconds: 5));
      if (_closed) {
        await socket.close();
        return;
      }
      socket.pingInterval = const Duration(seconds: 20);
      _reconnectTimers.remove(relay)?.cancel();
      await _subscriptions.remove(relay)?.cancel();
      _sockets[relay] = socket;
      _subscriptions[relay] = socket.listen(
        (dynamic raw) => unawaited(_handleRaw(raw)),
        onDone: () => _disconnected(relay),
        onError: (_) => _disconnected(relay),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect(relay);
    } finally {
      _connecting.remove(relay);
    }
  }

  void _disconnected(String relay) {
    if (_closed) return;
    _sockets.remove(relay);
    final subscription = _subscriptions.remove(relay);
    if (subscription != null) unawaited(subscription.cancel());
    _scheduleReconnect(relay);
  }

  void _scheduleReconnect(String relay) {
    if (_closed || _sockets.containsKey(relay)) return;
    _reconnectTimers.remove(relay)?.cancel();
    _reconnectTimers[relay] = Timer(const Duration(seconds: 2), () {
      unawaited(_connect(relay));
    });
  }

  Future<void> _handleRaw(dynamic raw) async {
    try {
      final outer = jsonDecode(raw.toString());
      if (outer is! Map || outer['event']?.toString() != 'message') return;
      String? encrypted = outer['message']?.toString();
      final attachment = outer['attachment'];
      if ((encrypted == null || encrypted.isEmpty) && attachment is Map) {
        final url = attachment['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final response = await _http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            encrypted = utf8.decode(response.bodyBytes, allowMalformed: true);
          }
        }
      }
      if (encrypted == null || encrypted.isEmpty) return;
      final clear = await _decrypt(encrypted);
      if (clear == null || clear['kind']?.toString() != 'chat') return;
      final messageRaw = clear['message'];
      if (messageRaw is! Map) return;
      final message = ChatOnlyMessage.fromJson(
        Map<String, dynamic>.from(messageRaw),
      );
      if (message.id.isEmpty || message.senderId == deviceId) return;
      if (!_seen.add(message.id)) return;
      if (_seen.length > 5000) _seen.remove(_seen.first);
      if (!_incoming.isClosed) _incoming.add(message);
    } catch (_) {
      // A broken relay packet must never affect the chat screen.
    }
  }

  Future<bool> send(ChatOnlyMessage message) async {
    if (_closed) return false;
    await _prepare();
    _seen.add(message.id);
    final encrypted = await _encrypt(<String, dynamic>{
      'v': 1,
      'kind': 'chat',
      'message': message.toJson(),
    });

    final completer = Completer<bool>();
    var finished = 0;
    for (final relay in _relays) {
      unawaited(
        _post(relay, encrypted).then((bool ok) {
          finished++;
          if (ok && !completer.isCompleted) completer.complete(true);
          if (finished == _relays.length && !completer.isCompleted) {
            completer.complete(false);
          }
        }),
      );
    }
    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );
  }

  Future<bool> _post(String relay, String encrypted) async {
    try {
      final response = await _http
          .post(
            Uri.parse('https://$relay/${_topic!}'),
            headers: const <String, String>{
              'Content-Type': 'text/plain; charset=utf-8',
              'Title': 'chat',
              'Priority': 'min',
              'Firebase': 'no',
            },
            body: encrypted,
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      _scheduleReconnect(relay);
      return false;
    }
  }

  Future<String> _encrypt(Map<String, dynamic> payload) async {
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: _key!,
      nonce: nonce,
    );
    return jsonEncode(<String, String>{
      'n': base64Url.encode(box.nonce),
      'c': base64Url.encode(box.cipherText),
      'm': base64Url.encode(box.mac.bytes),
    });
  }

  Future<Map<String, dynamic>?> _decrypt(String encrypted) async {
    try {
      final raw = jsonDecode(encrypted);
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final box = SecretBox(
        base64Url.decode(map['c']?.toString() ?? ''),
        nonce: base64Url.decode(map['n']?.toString() ?? ''),
        mac: Mac(base64Url.decode(map['m']?.toString() ?? '')),
      );
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: _key!,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final socket in _sockets.values) {
      await socket.close();
    }
    _sockets.clear();
    _http.close();
    await _incoming.close();
  }
}

String chatOnlyRandomId([int bytes = 18]) {
  final random = Random.secure();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64Url.encode(values).replaceAll('=', '');
}
