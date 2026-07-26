import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class LanTunnelEndpoint {
  final String host;
  final int port;
  final String tunnelId;
  final String secret;

  const LanTunnelEndpoint({
    required this.host,
    required this.port,
    required this.tunnelId,
    required this.secret,
  });

  Uri socketUri({required String peerId, required String nickname}) => Uri(
        scheme: 'ws',
        host: host,
        port: port,
        path: '/ws',
        queryParameters: {
          'tunnel': tunnelId,
          'secret': secret,
          'peer': peerId,
          'name': nickname,
        },
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'tunnelId': tunnelId,
        'secret': secret,
      };

  factory LanTunnelEndpoint.fromJson(Map<String, dynamic> json) {
    return LanTunnelEndpoint(
      host: json['host']?.toString() ?? '',
      port: int.tryParse(json['port']?.toString() ?? '') ?? 0,
      tunnelId: json['tunnelId']?.toString() ?? '',
      secret: json['secret']?.toString() ?? '',
    );
  }

  bool get isValid =>
      host.isNotEmpty && port > 0 && tunnelId.isNotEmpty && secret.isNotEmpty;
}

class LanNetworkInvite {
  final String baseInviteToken;
  final LanTunnelEndpoint endpoint;

  const LanNetworkInvite({
    required this.baseInviteToken,
    required this.endpoint,
  });

  String encode() {
    final payload = jsonEncode({
      'v': 2,
      'kind': 'chernogram-lan',
      'invite': baseInviteToken,
      'endpoint': endpoint.toJson(),
    });
    return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  }

  static LanNetworkInvite? tryDecode(String token) {
    try {
      var normalized = token.trim();
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['kind'] != 'chernogram-lan') return null;
      if (map['endpoint'] is! Map) return null;
      final endpoint = LanTunnelEndpoint.fromJson(
        Map<String, dynamic>.from(map['endpoint'] as Map),
      );
      final invite = map['invite']?.toString() ?? '';
      if (invite.isEmpty || !endpoint.isValid) return null;
      return LanNetworkInvite(baseInviteToken: invite, endpoint: endpoint);
    } catch (_) {
      return null;
    }
  }
}

class LanTunnelDirectory {
  static String _key(String tunnelId) => 'chernogram_lan_endpoint_v1_$tunnelId';

  static Future<void> save(LanTunnelEndpoint endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(endpoint.tunnelId), jsonEncode(endpoint.toJson()));
  }

  static Future<LanTunnelEndpoint?> load(String tunnelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(tunnelId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final endpoint = LanTunnelEndpoint.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return endpoint.isValid ? endpoint : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String tunnelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(tunnelId));
  }
}

class LanTunnelEvent {
  final String type;
  final Map<String, dynamic> data;

  const LanTunnelEvent(this.type, [this.data = const {}]);
}

class LanTunnelSession {
  final String tunnelId;
  final String secret;
  final String peerId;
  final String nickname;
  final bool isHost;

  final StreamController<LanTunnelEvent> _events =
      StreamController<LanTunnelEvent>.broadcast(sync: true);
  final Set<WebSocket> _hostPeers = <WebSocket>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _pendingMessages = {};

  HttpServer? _server;
  WebSocket? _client;
  LanTunnelEndpoint? _endpoint;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connecting = false;
  int _onlinePeers = 1;

  LanTunnelSession._({
    required this.tunnelId,
    required this.secret,
    required this.peerId,
    required this.nickname,
    required this.isHost,
  });

  Stream<LanTunnelEvent> get events => _events.stream;
  LanTunnelEndpoint? get endpoint => _endpoint;
  bool get connected => isHost ? _server != null : _client != null;
  int get onlinePeers => _onlinePeers;

  static Future<LanTunnelSession> startHost({
    required String tunnelId,
    required String secret,
    required String peerId,
    required String nickname,
    required List<Map<String, dynamic>> initialHistory,
  }) async {
    final session = LanTunnelSession._(
      tunnelId: tunnelId,
      secret: secret,
      peerId: peerId,
      nickname: nickname,
      isHost: true,
    );
    session.replaceHistory(initialHistory);
    await session._startServer();
    return session;
  }

  static Future<LanTunnelSession> connect({
    required LanTunnelEndpoint endpoint,
    required String peerId,
    required String nickname,
  }) async {
    final session = LanTunnelSession._(
      tunnelId: endpoint.tunnelId,
      secret: endpoint.secret,
      peerId: peerId,
      nickname: nickname,
      isHost: false,
    );
    session._endpoint = endpoint;
    await session._connectClient();
    return session;
  }

  void replaceHistory(List<Map<String, dynamic>> messages) {
    _history
      ..clear()
      ..addAll(_dedupeMessages(messages));
  }

  Future<void> _startServer() async {
    final address = await _bestLanAddress();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    _server = server;
    _endpoint = LanTunnelEndpoint(
      host: address,
      port: server.port,
      tunnelId: tunnelId,
      secret: secret,
    );
    await LanTunnelDirectory.save(_endpoint!);
    _emit('status', {'state': 'hosting', 'host': address, 'port': server.port});
    server.listen((request) {
      unawaited(_handleRequest(request));
    });
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_disposed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final query = request.uri.queryParameters;
    final valid = request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request) &&
        query['tunnel'] == tunnelId &&
        query['secret'] == secret;
    if (!valid) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 15);
    _hostPeers.add(socket);
    _updatePresence();
    _send(socket, {
      'type': 'history',
      'messages': _history,
      'peers': _onlinePeers,
    });

    socket.listen(
      (raw) => _handleHostMessage(socket, raw),
      onError: (_) => _removeHostPeer(socket),
      onDone: () => _removeHostPeer(socket),
      cancelOnError: true,
    );
  }

  void _handleHostMessage(WebSocket socket, dynamic raw) {
    final packet = _decodePacket(raw);
    if (packet == null) return;
    switch (packet['type']) {
      case 'message':
        if (packet['message'] is Map) {
          _acceptMessage(Map<String, dynamic>.from(packet['message'] as Map));
        }
        break;
      case 'signal':
        final signal = packet['signal'];
        if (signal is Map) {
          final outgoing = {
            'type': 'signal',
            'signal': Map<String, dynamic>.from(signal),
          };
          _broadcast(outgoing, except: socket);
          _emit('signal', Map<String, dynamic>.from(signal));
        }
        break;
      case 'ping':
        _send(socket, {'type': 'pong'});
        break;
    }
  }

  void _removeHostPeer(WebSocket socket) {
    _hostPeers.remove(socket);
    _updatePresence();
  }

  Future<void> _connectClient() async {
    if (_disposed || _connecting || _endpoint == null) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    try {
      final socket = await WebSocket.connect(
        _endpoint!.socketUri(peerId: peerId, nickname: nickname).toString(),
      ).timeout(const Duration(seconds: 10));
      if (_disposed) {
        await socket.close();
        return;
      }
      socket.pingInterval = const Duration(seconds: 15);
      _client = socket;
      _emit('status', {'state': 'connected'});
      socket.listen(
        _handleClientMessage,
        onError: (Object error) => _clientDisconnected(error.toString()),
        onDone: () => _clientDisconnected('connection closed'),
        cancelOnError: true,
      );
      for (final message in _pendingMessages.values.toList()) {
        _send(socket, {'type': 'message', 'message': message});
      }
    } catch (error) {
      _emit('status', {'state': 'error', 'error': error.toString()});
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleClientMessage(dynamic raw) {
    final packet = _decodePacket(raw);
    if (packet == null) return;
    switch (packet['type']) {
      case 'history':
        final messages = ((packet['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        replaceHistory(messages);
        _onlinePeers = int.tryParse(packet['peers']?.toString() ?? '') ?? 1;
        _emit('history', {'messages': _history});
        _emit('presence', {'peers': _onlinePeers});
        break;
      case 'message':
        if (packet['message'] is Map) {
          final message = Map<String, dynamic>.from(packet['message'] as Map);
          final id = message['id']?.toString();
          if (id != null) _pendingMessages.remove(id);
          _remember(message);
          _emit('message', {'message': message});
        }
        break;
      case 'presence':
        _onlinePeers = int.tryParse(packet['peers']?.toString() ?? '') ?? 1;
        _emit('presence', {'peers': _onlinePeers});
        break;
      case 'signal':
        if (packet['signal'] is Map) {
          _emit('signal', Map<String, dynamic>.from(packet['signal'] as Map));
        }
        break;
      case 'pong':
        break;
    }
  }

  void _clientDisconnected(String reason) {
    _client = null;
    _onlinePeers = 1;
    _emit('presence', {'peers': _onlinePeers});
    _emit('status', {'state': 'disconnected', 'error': reason});
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || isHost) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_connectClient().catchError((_) {}));
    });
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (_disposed) return;
    if (isHost) {
      _acceptMessage(message);
      return;
    }
    final socket = _client;
    if (socket == null) {
      final id = message['id']?.toString() ?? '';
      if (id.isNotEmpty) _pendingMessages[id] = Map<String, dynamic>.from(message);
      _emit('status', {'state': 'queued'});
      return;
    }
    _send(socket, {'type': 'message', 'message': message});
  }

  Future<void> sendSignal(Map<String, dynamic> signal) async {
    if (_disposed) return;
    if (isHost) {
      _broadcast({'type': 'signal', 'signal': signal});
      _emit('signal', signal);
      return;
    }
    final socket = _client;
    if (socket == null) throw StateError('LAN tunnel is not connected');
    _send(socket, {'type': 'signal', 'signal': signal});
  }

  void _acceptMessage(Map<String, dynamic> message) {
    if (!_remember(message)) return;
    final packet = {'type': 'message', 'message': message};
    _broadcast(packet);
    _emit('message', {'message': message});
  }

  bool _remember(Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return false;
    if (_history.any((item) => item['id']?.toString() == id)) return false;
    _history.add(Map<String, dynamic>.from(message));
    if (_history.length > 500) {
      _history.removeRange(0, _history.length - 500);
    }
    return true;
  }

  void _updatePresence() {
    _onlinePeers = _hostPeers.length + 1;
    final packet = {'type': 'presence', 'peers': _onlinePeers};
    _broadcast(packet);
    _emit('presence', {'peers': _onlinePeers});
  }

  void _broadcast(Map<String, dynamic> packet, {WebSocket? except}) {
    final dead = <WebSocket>[];
    for (final socket in _hostPeers) {
      if (identical(socket, except)) continue;
      try {
        _send(socket, packet);
      } catch (_) {
        dead.add(socket);
      }
    }
    for (final socket in dead) {
      _hostPeers.remove(socket);
    }
  }

  void _send(WebSocket socket, Map<String, dynamic> packet) {
    socket.add(jsonEncode(packet));
  }

  Map<String, dynamic>? _decodePacket(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _emit(String type, [Map<String, dynamic> data = const {}]) {
    if (!_events.isClosed) _events.add(LanTunnelEvent(type, data));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    for (final socket in _hostPeers.toList()) {
      await socket.close();
    }
    _hostPeers.clear();
    final client = _client;
    if (client != null) await client.close();
    final server = _server;
    if (server != null) await server.close(force: true);
    await _events.close();
  }

  static List<Map<String, dynamic>> _dedupeMessages(
    List<Map<String, dynamic>> source,
  ) {
    final ids = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final item in source) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty || !ids.add(id)) continue;
      result.add(Map<String, dynamic>.from(item));
    }
    return result;
  }

  static Future<String> _bestLanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) addresses.add(address.address);
      }
    }
    if (addresses.isEmpty) {
      throw StateError('No local IPv4 address. Connect both phones to one Wi-Fi.');
    }
    addresses.sort((a, b) {
      final aPrivate = _isPrivateIpv4(a) ? 0 : 1;
      final bPrivate = _isPrivateIpv4(b) ? 0 : 1;
      return aPrivate.compareTo(bPrivate);
    });
    return addresses.first;
  }

  static bool _isPrivateIpv4(String value) {
    if (value.startsWith('10.') || value.startsWith('192.168.')) return true;
    if (!value.startsWith('172.')) return false;
    final parts = value.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }
}

class LanTunnelNetwork {
  static final Map<String, LanTunnelSession> _sessions = {};

  static LanTunnelSession? session(String tunnelId) => _sessions[tunnelId];

  static Future<LanTunnelSession> host({
    required String tunnelId,
    required String secret,
    required String peerId,
    required String nickname,
    required List<Map<String, dynamic>> history,
  }) async {
    final existing = _sessions[tunnelId];
    if (existing != null && existing.isHost) {
      existing.replaceHistory(history);
      return existing;
    }
    if (existing != null) await existing.dispose();
    final session = await LanTunnelSession.startHost(
      tunnelId: tunnelId,
      secret: secret,
      peerId: peerId,
      nickname: nickname,
      initialHistory: history,
    );
    _sessions[tunnelId] = session;
    return session;
  }

  static Future<LanTunnelSession> join({
    required LanTunnelEndpoint endpoint,
    required String peerId,
    required String nickname,
  }) async {
    final existing = _sessions[endpoint.tunnelId];
    if (existing != null && !existing.isHost) return existing;
    if (existing != null) await existing.dispose();
    final session = await LanTunnelSession.connect(
      endpoint: endpoint,
      peerId: peerId,
      nickname: nickname,
    );
    _sessions[endpoint.tunnelId] = session;
    return session;
  }

  static Future<void> close(String tunnelId) async {
    final session = _sessions.remove(tunnelId);
    if (session != null) await session.dispose();
  }
}
