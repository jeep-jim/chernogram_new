from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:160]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_block(path: str, start: str, end: str, new_block: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    start_at = text.find(start)
    if start_at < 0:
        raise SystemExit(f'Start marker not found in {path}: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End marker not found in {path}: {end!r}')
    file.write_text(text[:start_at] + new_block + text[end_at:], encoding='utf-8')


# Version and lightweight public-internet transport dependencies.
replace_once('pubspec.yaml', 'version: 0.51.0+74', 'version: 0.81.0+81')
replace_once(
    'pubspec.yaml',
    '  mobile_scanner: ^7.4.0\n',
    '  mobile_scanner: ^7.4.0\n  mqtt_client: ^10.11.11\n  crypto: ^3.0.6\n',
)

# Internet relay fallback: private Impulse Worker when configured, otherwise
# encrypted public MQTT with several independent broker endpoints.
replace_once(
    'lib/internet_core.dart',
    "import 'push_service.dart';\n",
    "import 'push_service.dart';\nimport 'public_mqtt_transport.dart';\n",
)
replace_once(
    'lib/internet_core.dart',
    '  static const int _inlineFileChars = 300000;\n'
    '  static const int _fileChunkChars = 220000;\n',
    '  static const int _inlineFileChars = 48000;\n'
    '  static const int _fileChunkChars = 48000;\n',
)
replace_once(
    'lib/internet_core.dart',
    '  Timer? _outboxTimer;\n',
    '  Timer? _outboxTimer;\n'
    '  CgPublicMqttRelay? _publicRelay;\n'
    '  StreamSubscription<Map<String, dynamic>>? _publicPacketSubscription;\n'
    '  StreamSubscription<Map<String, dynamic>>? _publicStatusSubscription;\n',
)
replace_once(
    'lib/internet_core.dart',
    '  bool get connected => _httpReady || _socket != null;\n',
    '  bool get connected =>\n'
    '      _httpReady || _socket != null || (_publicRelay?.connected ?? false);\n',
)
replace_once(
    'lib/internet_core.dart',
    '    if (_closed || _connecting || (_httpReady && _socket != null)) return;\n',
    '    if (_closed || _connecting || connected) return;\n',
)
replace_once(
    'lib/internet_core.dart',
    "      if (!_configured) {\n"
    "        _emit('status', const <String, dynamic>{\n"
    "          'state': 'error',\n"
    "          'transport': 'impulse_missing',\n"
    "        });\n"
    "        return;\n"
    "      }\n",
    "      if (!_configured) {\n"
    "        await _connectPublicRelay();\n"
    "        return;\n"
    "      }\n",
)

public_connect = '''  Future<void> _connectPublicRelay() async {
    if (_closed || (_publicRelay?.connected ?? false)) return;
    await _prepareCryptoAndRoom();
    await _loadOutbox();

    final relay = _publicRelay ?? CgPublicMqttRelay(
      roomKey: _roomKey!,
      deviceId: profileId,
    );
    _publicRelay = relay;

    await _publicPacketSubscription?.cancel();
    await _publicStatusSubscription?.cancel();
    _publicPacketSubscription = relay.packets.listen(
      (packet) => unawaited(_handleOuterEnvelope(packet, 'public_mqtt')),
    );
    _publicStatusSubscription = relay.statuses.listen((status) {
      _emit('status', status);
      if (status['state'] == 'connected') {
        _reconnectAttempt = 0;
      }
    });

    await relay.connect();
    _startTimers();
    _reconnectAttempt = 0;
    _emit('status', const <String, dynamic>{
      'state': 'connected',
      'transport': 'public_mqtt',
    });
    unawaited(_publishPresence());
    unawaited(_flushOutbox());
  }

'''
replace_once(
    'lib/internet_core.dart',
    '  Future<void> _prepareCryptoAndRoom() async {\n',
    public_connect + '  Future<void> _prepareCryptoAndRoom() async {\n',
)
replace_once(
    'lib/internet_core.dart',
    '  Future<void> pullNow() async {\n    if (_closed || !_configured) return;\n',
    "  Future<void> pullNow() async {\n"
    "    if (_closed) return;\n"
    "    if (!_configured) {\n"
    "      await _connectPublicRelay();\n"
    "      return;\n"
    "    }\n",
)
replace_once(
    'lib/internet_core.dart',
    "  Future<void> _publishPresence() async {\n"
    "    await _registerDevice();\n",
    "  Future<void> _publishPresence() async {\n"
    "    if (_configured) await _registerDevice();\n",
)

transmit = '''  Future<bool> _transmit(_QueuedEnvelope envelope) async {
    if (_closed) return false;
    try {
      await _prepareCryptoAndRoom();
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
      final outer = <String, dynamic>{
        'packetId': envelope.packetId,
        'from': profileId,
        'kind': envelope.kind,
        'wake': _wakeFor(envelope),
        if (_wakeFor(envelope) == 'call')
          'video': envelope.data['video'] == true,
        'ciphertext': encrypted,
        'createdAt': envelope.createdAt.millisecondsSinceEpoch,
      };

      if (!_configured) {
        final relay = _publicRelay;
        if (relay == null || !relay.connected) {
          await _connectPublicRelay();
        }
        final sent = await _publicRelay?.publish(
              outer,
              retain: envelope.kind == 'history',
            ) ??
            false;
        if (sent) {
          _emit('status', const <String, dynamic>{
            'state': 'connected',
            'transport': 'public_mqtt',
          });
        } else {
          _scheduleReconnect();
        }
        return sent;
      }

      if (!_httpReady) await _registerDevice();
      final response = await _http
          .post(
            _endpoint('envelopes'),
            headers: _headers,
            body: jsonEncode(outer),
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
      if (_configured) _httpReady = false;
      _scheduleReconnect();
      return false;
    }
  }

'''
replace_block(
    'lib/internet_core.dart',
    '  Future<bool> _transmit(_QueuedEnvelope envelope) async {',
    '  Future<String> _encrypt(Map<String, dynamic> body) async {',
    transmit,
)
replace_block(
    'lib/internet_core.dart',
    '  void _startTimers() {',
    '  void _emitPresence() {',
    '''  void _startTimers() {
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _peerCleanupTimer?.cancel();
    _outboxTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_configured) {
        if (_socket == null) unawaited(pullNow());
      } else if (!(_publicRelay?.connected ?? false)) {
        unawaited(connect());
      }
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

''',
)
replace_once(
    'lib/internet_core.dart',
    '    await _socketSubscription?.cancel();\n',
    '    await _socketSubscription?.cancel();\n'
    '    await _publicPacketSubscription?.cancel();\n'
    '    await _publicStatusSubscription?.cancel();\n'
    '    await _publicRelay?.close();\n',
)
replace_once(
    'lib/internet_core.dart',
    '    unawaited(_ensurePushListener());\n',
    "    if (_impulseBaseUrl.trim().isNotEmpty) {\n"
    "      unawaited(_ensurePushListener());\n"
    "    }\n",
)
replace_once(
    'lib/internet_core.dart',
    "      await _sendEnvelope('message', <String, dynamic>{'message': message});\n"
    "      return;\n",
    "      await _sendEnvelope('message', <String, dynamic>{'message': message});\n"
    "      unawaited(sendHistory());\n"
    "      return;\n",
)
replace_once(
    'lib/internet_core.dart',
    '    await _sendLargeFileMessage(message, payload);\n',
    '    await _sendLargeFileMessage(message, payload);\n'
    '    unawaited(sendHistory());\n',
)
replace_once(
    'lib/internet_core.dart',
    "    final plain = recent\n"
    "        .where((message) {\n"
    "          final id = message['id']?.toString() ?? '';\n"
    "          return !_filePayloads.containsKey(id);\n"
    "        })\n"
    "        .toList(growable: false);\n",
    '    final plain = recent;\n',
)

# TURN credentials compatible with the published Open Relay static-auth secret.
replace_once(
    'lib/call_service.dart',
    "import 'dart:async';\n",
    "import 'dart:async';\nimport 'dart:convert';\n\nimport 'package:crypto/crypto.dart' as crypto;\n",
)
turn_helper = '''Map<String, dynamic> _chernogramTurnServer() {
  final expires = DateTime.now().toUtc().add(const Duration(hours: 12));
  final username =
      '${expires.millisecondsSinceEpoch ~/ 1000}:chernogram';
  final digest = crypto.Hmac(
    crypto.sha1,
    utf8.encode('openrelayprojectsecret'),
  ).convert(utf8.encode(username));
  return <String, dynamic>{
    'urls': <String>[
      'turn:staticauth.openrelay.metered.ca:80',
      'turn:staticauth.openrelay.metered.ca:80?transport=tcp',
      'turn:staticauth.openrelay.metered.ca:443',
      'turn:staticauth.openrelay.metered.ca:443?transport=tcp',
      'turns:staticauth.openrelay.metered.ca:443?transport=tcp',
    ],
    'username': username,
    'credential': base64Encode(digest.bytes),
  };
}

'''
replace_once(
    'lib/call_service.dart',
    'class CgCallOutcome {\n',
    turn_helper + 'class CgCallOutcome {\n',
)
replace_once(
    'lib/call_service.dart',
    "          <String, dynamic>{\n"
    "            'urls': <String>[\n"
    "              'turn:openrelay.metered.ca:80',\n"
    "              'turn:openrelay.metered.ca:80?transport=tcp',\n"
    "              'turn:openrelay.metered.ca:443',\n"
    "              'turn:openrelay.metered.ca:443?transport=tcp',\n"
    "              'turns:openrelay.metered.ca:443?transport=tcp',\n"
    "            ],\n"
    "            'username': 'openrelayproject',\n"
    "            'credential': 'openrelayproject',\n"
    "          },\n",
    '          _chernogramTurnServer(),\n',
)

# No artificial 20 MB interface limit. The transport chunks attachments; actual
# practical size still depends on device memory and the current network.
replace_once(
    'lib/chat_screen.dart',
    "    const maxBytes = 20 * 1024 * 1024;\n"
    "    if (bytes.length > maxBytes) {\n"
    "      if (!mounted) return;\n"
    "      ScaffoldMessenger.of(context).showSnackBar(\n"
    "        SnackBar(\n"
    "          content: Text(\n"
    "            widget.ru\n"
    "                ? 'Сейчас можно отправить файл до 20 МБ. Большие медиа лучше отправлять короткими фрагментами.'\n"
    "                : 'Files up to 20 MB are supported. Send very large media as shorter clips.',\n"
    "          ),\n"
    "        ),\n"
    "      );\n"
    "      return;\n"
    "    }\n",
    '',
)
replace_once(
    'lib/chat_screen.dart',
    "const String _landingBase =\n"
    "    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';\n"
    "const String _androidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';\n",
    "const String _landingBase =\n"
    "    'https://jeep-jim.github.io/chernogram_new/';\n"
    "const String _androidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-room-alpha/chernogram-room.apk';\n",
)

# Minimal home: only rooms and profile. A room is created immediately and then
# exposes its QR and share link; no contacts permission or fake dialer flow.
replace_once(
    'lib/light/light_chat_app.dart',
    "import 'package:package_info_plus/package_info_plus.dart';\n",
    "import 'package:package_info_plus/package_info_plus.dart';\n"
    "import 'package:qr_flutter/qr_flutter.dart';\n",
)
replace_once(
    'lib/light/light_chat_app.dart',
    "const String _landingBase =\n"
    "    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';\n"
    "const String _androidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';\n",
    "const String _landingBase =\n"
    "    'https://jeep-jim.github.io/chernogram_new/';\n"
    "const String _androidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-room-alpha/chernogram-room.apk';\n",
)
replace_once(
    'lib/light/light_chat_app.dart',
    '      _tab = 1;\n',
    '      _tab = 0;\n',
)
replace_block(
    'lib/light/light_chat_app.dart',
    '  Future<void> _newChat() async {',
    '  Future<void> _changeProfilePhoto() async {',
    '''  Future<void> _newChat() async {
    if (_profile == null || !mounted) return;
    final chat = _newDirectChat('Комната');
    setState(() {
      _chats.insert(0, chat);
      _tab = 0;
    });
    await CgStore.saveTunnels(_chats);
    unawaited(_syncMonitor());
    await _showInviteQr(chat);
    if (mounted) await _openChat(chat);
  }

''',
)
replace_block(
    'lib/light/light_chat_app.dart',
    '    final pages = <Widget>[',
    '    return Scaffold(',
    '''    final pages = <Widget>[
      _ChatsPage(
        profile: _profile!,
        chats: _chats,
        contacts: _knownContacts,
        onOpen: _openChat,
        onCreate: _newChat,
        onScan: _scanInviteQr,
        onDelete: _deleteChat,
      ),
      _ProfilePage(
        profile: _profile!,
        packageInfo: _packageInfo,
        darkMode: widget.darkMode,
        onPhoto: _changeProfilePhoto,
        onName: _changeProfileName,
        onTheme: widget.onToggleTheme,
        onShareInstall: () => Share.share(
          'Установить Чернограм: $_androidInstallUrl',
          subject: 'Чернограм',
        ),
        onUpdate: widget.onCheckUpdates,
      ),
    ];

''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    "            destinations: const <NavigationDestination>[\n"
    "              NavigationDestination(\n"
    "                icon: Icon(Icons.people_outline_rounded),\n"
    "                selectedIcon: Icon(Icons.people_rounded),\n"
    "                label: 'Контакты',\n"
    "              ),\n"
    "              NavigationDestination(\n"
    "                icon: Icon(Icons.chat_bubble_outline_rounded),\n"
    "                selectedIcon: Icon(Icons.chat_bubble_rounded),\n"
    "                label: 'Чаты',\n"
    "              ),\n"
    "              NavigationDestination(\n"
    "                icon: Icon(Icons.person_outline_rounded),\n"
    "                selectedIcon: Icon(Icons.person_rounded),\n"
    "                label: 'Профиль',\n"
    "              ),\n"
    "            ],\n",
    "            destinations: const <NavigationDestination>[\n"
    "              NavigationDestination(\n"
    "                icon: Icon(Icons.chat_bubble_outline_rounded),\n"
    "                selectedIcon: Icon(Icons.chat_bubble_rounded),\n"
    "                label: 'Комнаты',\n"
    "              ),\n"
    "              NavigationDestination(\n"
    "                icon: Icon(Icons.person_outline_rounded),\n"
    "                selectedIcon: Icon(Icons.person_rounded),\n"
    "                label: 'Профиль',\n"
    "              ),\n"
    "            ],\n",
)
replace_once(
    'lib/light/light_chat_app.dart',
    "            title: 'Чаты',\n"
    "            subtitle: '${widget.chats.length} сохранённых диалогов',\n",
    "            title: 'Чернограм',\n"
    "            subtitle: 'Комнаты, звонки и файлы через интернет',\n",
)

install_qr = '''          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: LightGlass(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text(
                    'QR для установки',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Отсканируй обычной камерой Android',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: QrImageView(
                      data: _androidInstallUrl,
                      size: 188,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onShareInstall,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Отправить ссылку'),
                  ),
                ],
              ),
            ),
          ),
'''
replace_once(
    'lib/light/light_chat_app.dart',
    "          Padding(\n"
    "            padding: const EdgeInsets.symmetric(horizontal: 14),\n"
    "            child: LightGlass(\n",
    install_qr +
    "          Padding(\n"
    "            padding: const EdgeInsets.symmetric(horizontal: 14),\n"
    "            child: LightGlass(\n",
)

# Deep-link host now points to the actual GitHub Pages invite page.
replace_once(
    'android/app/src/main/AndroidManifest.xml',
    '                    android:host="githubraw.com"\n'
    '                    android:pathPrefix="/jeep-jim/chernogram_new/main/docs/index.html" />\n',
    '                    android:host="jeep-jim.github.io"\n'
    '                    android:pathPrefix="/chernogram_new" />\n',
)
replace_once(
    'android/app/src/main/AndroidManifest.xml',
    '    <uses-permission android:name="android.permission.READ_CONTACTS" />\n',
    '',
)

print('Minimal room chat 0.81 patches applied')
