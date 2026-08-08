from pathlib import Path
import re


def patch(path: str, transform) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    updated = transform(source)
    if updated == source:
        raise RuntimeError(f'No 0.93 change applied to {path}')
    file.write_text(updated, encoding='utf-8')
    print(f'Patched 0.93: {path}')


def push(source: str) -> str:
    source = source.replace("'chernogram_messages_v2'", "'chernogram_messages_v3'")
    source = source.replace(
        "        sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),\n"
        "        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,\n"
        "        additionalFlags: Int32List.fromList(<int>[4]),\n",
        "        playSound: true,\n",
    )
    return source


def sound(source: str) -> str:
    if 'import android.media.ToneGenerator' not in source:
        source = source.replace(
            'import android.media.RingtoneManager\n',
            'import android.media.RingtoneManager\nimport android.media.AudioManager\nimport android.media.ToneGenerator\n',
            1,
        )
    return re.sub(
        r'    private fun playNotificationSound\(\) \{.*?\n    \}',
        '''    private fun playNotificationSound() {
        ToneGenerator(AudioManager.STREAM_NOTIFICATION, 88).also { tone ->
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 160)
            android.os.Handler(mainLooper).postDelayed({ tone.release() }, 240)
        }
    }''',
        source,
        count=1,
        flags=re.S,
    )


def transport(source: str) -> str:
    source = source.replace(
        "          if (transferId.isNotEmpty) {\n"
        "            _pendingFileManifests[transferId] = message;\n"
        "            _emitMessage(message, sender, senderName, source);\n"
        "            unawaited(_tryCompleteFile(transferId, sender, senderName, source));\n",
        "          if (transferId.isNotEmpty) {\n"
        "            _pendingFileManifests[transferId] = message;\n"
        "            _emitMessage(message, sender, senderName, source);\n"
        "            unawaited(_tryCompleteFile(transferId, sender, senderName, source));\n"
        "            _scheduleMissingFileRequest(transferId, message['id']?.toString() ?? '', sender);\n",
        1,
    )
    source = source.replace(
        "      case 'control':\n"
        "        _emit('control', <String, dynamic>{\n",
        "      case 'control':\n"
        "        if (data['action'] == 'file_request' &&\n"
        "            data['target']?.toString() == profileId) {\n"
        "          final messageId = data['messageId']?.toString() ?? '';\n"
        "          final localMessage = _fileMessages[messageId];\n"
        "          if (localMessage != null) unawaited(sendMessage(localMessage));\n"
        "          break;\n"
        "        }\n"
        "        _emit('control', <String, dynamic>{\n",
        1,
    )
    marker = '  Future<void> _receiveFileChunk(\n'
    helper = '''  void _scheduleMissingFileRequest(
    String transferId,
    String messageId,
    String sender,
  ) {
    if (transferId.isEmpty || messageId.isEmpty || sender.isEmpty) return;
    for (final delay in <int>[1, 4, 9, 16]) {
      Timer(Duration(seconds: delay), () {
        if (_closed || !_pendingFileManifests.containsKey(transferId)) return;
        unawaited(_sendEnvelope(
          'control',
          <String, dynamic>{
            'action': 'file_request',
            'transferId': transferId,
            'messageId': messageId,
            'target': sender,
          },
          queueOnFailure: false,
        ));
      });
    }
  }

'''
    if marker not in source:
        raise RuntimeError('File transfer helper anchor missing')
    source = source.replace(marker, helper + marker, 1)
    old = '''    final payload = attachment['dataBase64']?.toString();
    if (payload == null || payload.isEmpty) return;
    _filePayloads[id] = payload;
    _fileMessages[id] = Map<String, dynamic>.from(message);
'''
    new = '''    final payload = attachment['dataBase64']?.toString();
    final path = attachment['localPath']?.toString() ?? attachment['path']?.toString();
    if ((payload == null || payload.isEmpty) && (path == null || path.isEmpty)) return;
    if (payload != null && payload.isNotEmpty) _filePayloads[id] = payload;
    _fileMessages[id] = Map<String, dynamic>.from(message);
'''
    if old not in source:
        raise RuntimeError('Local file registry anchor missing')
    return source.replace(old, new, 1)


def chat(source: str) -> str:
    source = source.replace(
        '''  Map<String, dynamic> _replyMeta() {
    final reply = _replyingTo;
    if (reply == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'replyToId': reply.id,
      'replyAuthor': reply.authorName,
      'replyText': reply.text,
      'replyAttachmentName': reply.attachment?.name,
    };
  }
''',
        '''  Map<String, dynamic> _replyMeta() {
    final reply = _replyingTo;
    return <String, dynamic>{
      if (widget.profile.avatarBase64 != null)
        'authorAvatarBase64': widget.profile.avatarBase64,
      if (reply != null) ...<String, dynamic>{
        'replyToId': reply.id,
        'replyAuthor': reply.authorName,
        'replyText': reply.text,
        'replyAttachmentName': reply.attachment?.name,
      },
    };
  }
''',
        1,
    )
    source = source.replace(
        '  final VoidCallback onLongPress;\n',
        '  final VoidCallback onLongPress;\n  final VoidCallback? onAuthorTap;\n',
        1,
    )
    source = source.replace(
        '    required this.onLongPress,\n',
        '    required this.onLongPress,\n    this.onAuthorTap,\n',
        1,
    )
    source = source.replace('    final showAvatar = groupChat && !mine;', '    final showAvatar = !mine;', 1)
    source = source.replace(
        '''              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChernogramAvatar(
                    size: 27,
                    seed: message.authorId.isEmpty
                        ? message.authorName
                        : message.authorId,
                  ),
''',
        '''              child: InkWell(
                onTap: onAuthorTap,
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChernogramAvatar(
                      size: 27,
                      seed: message.authorId.isEmpty
                          ? message.authorName
                          : message.authorId,
                      avatarBase64: message.meta['authorAvatarBase64']?.toString(),
                    ),
''',
        1,
    )
    source = source.replace(
        '''                  ),
                ],
              ),
            ),
          GestureDetector(
''',
        '''                  ),
                  ],
                ),
              ),
            ),
          GestureDetector(
''',
        1,
    )
    source = source.replace(
        '                            onLongPress: () => _showMessageActions(message),\n',
        '''                            onLongPress: () => _showMessageActions(message),
                            onAuthorTap: mine ? null : () => _showAuthorProfile(message),
''',
        1,
    )
    anchor = '  void _showNotConnected() {\n'
    profile_method = '''  Future<void> _showAuthorProfile(CgMessage message) async {
    final contact = CgContact(
      id: message.authorId,
      nickname: message.authorName,
      lastSeenAt: DateTime.now(),
      tunnelIds: <String>[_tunnel.id],
      avatarBase64: message.meta['authorAvatarBase64']?.toString(),
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ChernogramAvatar(
                size: 82,
                seed: contact.id,
                avatarBase64: contact.avatarBase64,
              ),
              const SizedBox(height: 12),
              Text(contact.nickname, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'private'),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Написать лично'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action != null) await widget.onContactAction?.call(contact, action);
  }

'''
    if anchor not in source:
        raise RuntimeError('Profile sheet anchor missing')
    source = source.replace(anchor, profile_method + anchor, 1)
    source = source.replace(
        '  final ValueChanged<CgContact>? onContactSeen;\n',
        '  final ValueChanged<CgContact>? onContactSeen;\n  final Future<void> Function(CgContact contact, String action)? onContactAction;\n',
        1,
    )
    source = source.replace(
        '    this.onContactSeen,\n',
        '    this.onContactSeen,\n    this.onContactAction,\n',
        1,
    )
    source = source.replace(
        '''  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }
''',
        '''  void _scrollToBottom() {
    void move() {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => move());
    for (final delay in <int>[80, 240, 600]) {
      Timer(Duration(milliseconds: delay), move);
    }
  }
''',
        1,
    )
    return source


def home(source: str) -> str:
    source = source.replace(
        '          onContactSeen: _rememberContact,\n',
        '          onContactSeen: _rememberContact,\n          onContactAction: _openKnownContact,\n',
        1,
    )
    source = source.replace(
        '''  Future<void> _openKnownContact(CgContact contact, String action) async {
    for (final id in contact.tunnelIds) {
''',
        '''  Future<void> _openKnownContact(CgContact contact, String action) async {
    if (action != 'private') {
      for (final id in contact.tunnelIds) {
''',
        1,
    )
    source = source.replace(
        '''        return;
      }
    }
    final chat = _newDirectChat(contact.nickname);
''',
        '''          return;
        }
      }
    }
    final chat = _newDirectChat(contact.nickname);
''',
        1,
    )
    return source


def version(source: str) -> str:
    return re.sub(r'^version: .*$', 'version: 0.93.0+93', source, count=1, flags=re.M)


def settings(source: str) -> str:
    return source.replace('chernogram-android-0.92.apk', 'chernogram-android-0.93.apk').replace(
        'chernogram-windows-0.92.zip', 'chernogram-windows-0.93.zip'
    )


patch('lib/push_service.dart', push)
patch('android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt', sound)
patch('lib/internet_core.dart', transport)
patch('lib/chat_screen.dart', chat)
patch('lib/light/light_chat_app.dart', home)
patch('pubspec.yaml', version)
patch('lib/client_settings.dart', settings)

# Force launcher resolution to the transparent density PNGs on every Android
# version. Adaptive icons necessarily paint a shaped background.
for path in (
    Path('android/app/src/main/res/mipmap-anydpi/ic_launcher.xml'),
    Path('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'),
):
    if path.exists():
        path.unlink()
        print(f'Removed shaped launcher resource: {path}')
