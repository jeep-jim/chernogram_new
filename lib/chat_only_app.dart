import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_only_transport.dart';
import 'update_service.dart';

const String _installUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';

class ChatOnlyApp extends StatefulWidget {
  const ChatOnlyApp({super.key});

  @override
  State<ChatOnlyApp> createState() => _ChatOnlyAppState();
}

class _ChatOnlyAppState extends State<ChatOnlyApp> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final AppLinks _links = AppLinks();
  final List<ChatOnlyMessage> _messages = <ChatOnlyMessage>[];
  final Set<String> _pending = <String>{};

  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<ChatOnlyMessage>? _messageSubscription;
  ChatOnlyTransport? _transport;
  Timer? _retryTimer;
  String? _roomId;
  String? _secret;
  String? _deviceId;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('chat_only_device_id');
    deviceId ??= chatOnlyRandomId();
    await prefs.setString('chat_only_device_id', deviceId);

    _deviceId = deviceId;
    _roomId = prefs.getString('chat_only_room_id');
    _secret = prefs.getString('chat_only_secret');
    _loadMessages(prefs.getString('chat_only_messages'));

    final initial = await _links.getInitialLink();
    if (initial != null) await _applyInvite(initial);
    _linkSubscription = _links.uriLinkStream.listen(
      (Uri uri) => unawaited(_applyInvite(uri)),
    );

    if (_roomId != null && _secret != null) await _startTransport();
    _retryTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_retryPending()),
    );

    if (!mounted) return;
    setState(() => _ready = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        unawaited(
          ChernogramUpdater.checkAndPrompt(context, ru: true, manual: false),
        );
      }
    });
  }

  void _loadMessages(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded.whereType<Map>()) {
        final message = ChatOnlyMessage.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (message.id.isNotEmpty && message.text.isNotEmpty) {
          _messages.add(message);
        }
      }
      _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    } catch (_) {
      _messages.clear();
    }
  }

  Future<void> _saveRoom() async {
    final prefs = await SharedPreferences.getInstance();
    if (_roomId == null || _secret == null) {
      await prefs.remove('chat_only_room_id');
      await prefs.remove('chat_only_secret');
      return;
    }
    await prefs.setString('chat_only_room_id', _roomId!);
    await prefs.setString('chat_only_secret', _secret!);
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = _messages.length > 500
        ? _messages.sublist(_messages.length - 500)
        : _messages;
    await prefs.setString(
      'chat_only_messages',
      jsonEncode(recent.map((message) => message.toJson()).toList()),
    );
  }

  Future<void> _startTransport() async {
    final roomId = _roomId;
    final secret = _secret;
    final deviceId = _deviceId;
    if (roomId == null || secret == null || deviceId == null) return;

    await _messageSubscription?.cancel();
    await _transport?.close();
    final transport = ChatOnlyTransport(
      roomId: roomId,
      secret: secret,
      deviceId: deviceId,
    );
    _transport = transport;
    _messageSubscription = transport.incoming.listen(_receive);
    unawaited(transport.start());
  }

  Future<void> _createRoom() async {
    _roomId = chatOnlyRandomId(12);
    _secret = chatOnlyRandomId(32);
    _messages.clear();
    _pending.clear();
    await _saveRoom();
    await _saveMessages();
    await _startTransport();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _applyInvite(Uri uri) async {
    if (uri.scheme != 'chernogram' || uri.host != 'join') return;
    final room = uri.queryParameters['room'];
    final secret = uri.queryParameters['secret'];
    if (room == null || room.isEmpty || secret == null || secret.isEmpty) {
      return;
    }
    if (_roomId == room && _secret == secret) return;
    _roomId = room;
    _secret = secret;
    _messages.clear();
    _pending.clear();
    await _saveRoom();
    await _saveMessages();
    await _startTransport();
    if (mounted) setState(() {});
  }

  Uri? get _inviteUri {
    final room = _roomId;
    final secret = _secret;
    if (room == null || secret == null) return null;
    return Uri(
      scheme: 'chernogram',
      host: 'join',
      queryParameters: <String, String>{'room': room, 'secret': secret},
    );
  }

  Future<void> _shareRoom() async {
    if (_roomId == null || _secret == null) await _createRoom();
    final invite = _inviteUri;
    if (invite == null) return;
    await Share.share(
      'Открой чат в Чернограме: $invite\n\n'
      'Если приложения ещё нет: $_installUrl',
      subject: 'Чат Чернограма',
    );
  }

  void _receive(ChatOnlyMessage message) {
    if (_messages.any((item) => item.id == message.id)) return;
    if (!mounted) return;
    setState(() {
      _messages.add(message);
      _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    });
    unawaited(_saveMessages());
    _scrollToBottom();
  }

  Future<void> _send() async {
    final value = _composer.text.trim();
    final deviceId = _deviceId;
    if (value.isEmpty || deviceId == null) return;
    if (_roomId == null || _secret == null) await _createRoom();

    final message = ChatOnlyMessage(
      id: chatOnlyRandomId(),
      senderId: deviceId,
      text: value,
      sentAt: DateTime.now(),
    );
    _composer.clear();
    if (!mounted) return;
    setState(() {
      _messages.add(message);
      _pending.add(message.id);
    });
    await _saveMessages();
    _scrollToBottom();
    unawaited(_deliver(message));
  }

  Future<void> _deliver(ChatOnlyMessage message) async {
    final transport = _transport;
    if (transport == null) return;
    final sent = await transport.send(message);
    if (sent) _pending.remove(message.id);
  }

  Future<void> _retryPending() async {
    if (_pending.isEmpty || _transport == null) return;
    final messages = _messages
        .where((message) => _pending.contains(message.id))
        .toList(growable: false);
    for (final message in messages) {
      final sent = await _transport!.send(message);
      if (sent) _pending.remove(message.id);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Чернограм',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070A12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF715FFB),
          brightness: Brightness.dark,
          surface: const Color(0xFF111725),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111725),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: !_ready
              ? const Center(child: ChatOnlyLogo(size: 142))
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                      child: Row(
                        children: <Widget>[
                          const ChatOnlyLogo(size: 52),
                          const Spacer(),
                          Expanded(
                            flex: 3,
                            child: FilledButton(
                              onPressed: _createRoom,
                              child: const Text('Создать'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: OutlinedButton(
                              onPressed: _shareRoom,
                              child: const Text('Поделиться'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(child: ChatOnlyLogo(size: 188))
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final mine = message.senderId == _deviceId;
                                return _Bubble(message: message, mine: mine);
                              },
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        6,
                        12,
                        10 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _composer,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'Сообщение',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _send,
                            icon: const Icon(Icons.arrow_upward_rounded),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(52, 52),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_linkSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_transport?.close());
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _Bubble extends StatelessWidget {
  final ChatOnlyMessage message;
  final bool mine;

  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : const Color(0xFF151C2B),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? 20 : 5),
            topRight: Radius.circular(mine ? 5 : 20),
            bottomLeft: const Radius.circular(20),
            bottomRight: const Radius.circular(20),
          ),
        ),
        child: Text(
          message.text,
          style: const TextStyle(fontSize: 16, height: 1.25),
        ),
      ),
    );
  }
}

class ChatOnlyLogo extends StatelessWidget {
  final double size;

  const ChatOnlyLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: const _ChatOnlyLogoPainter(),
  );
}

class _ChatOnlyLogoPainter extends CustomPainter {
  const _ChatOnlyLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0xFFB9A8FF),
        Color(0xFF715FFB),
        Color(0xFF20C7FF),
      ],
    ).createShader(rect);
    const count = 15;
    final stroke = size.width / 47;
    for (var index = 0; index < count; index++) {
      final t = index / (count - 1);
      final nx = t * 2 - 1;
      final ellipse = math.sqrt(math.max(0, 1 - nx * nx));
      final x = size.width * (.14 + t * .72);
      final top = size.height * (.11 + (1 - ellipse) * .12);
      final bottom = size.height * (.48 + ellipse * .37 - nx.abs() * .035);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader;
      final eye = nx.abs() > .17 && nx.abs() < .72;
      if (!eye) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      } else {
        final gapStart = size.height * .37;
        final gapEnd = size.height * .445;
        canvas.drawLine(Offset(x, top), Offset(x, gapStart), paint);
        canvas.drawLine(Offset(x, gapEnd), Offset(x, bottom), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
