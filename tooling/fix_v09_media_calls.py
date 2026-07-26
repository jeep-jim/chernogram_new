from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    # Chat media, voice messages and circle videos.
    chat = Path('lib/chat_screen.dart')
    source = chat.read_text(encoding='utf-8')
    if "import 'dart:io';" not in source:
        replace(
            'lib/chat_screen.dart',
            "import 'dart:convert';\n",
            "import 'dart:convert';\nimport 'dart:io';\n",
        )
    source = chat.read_text(encoding='utf-8')
    if "import 'chat_media.dart';" not in source:
        replace(
            'lib/chat_screen.dart',
            "import 'call_service.dart';\n",
            "import 'call_service.dart';\nimport 'chat_media.dart';\n",
        )

    replace(
        'lib/chat_screen.dart',
        "  final Set<String> _handledCalls = <String>{};\n",
        "",
    )
    replace(
        'lib/chat_screen.dart',
        "  bool _sendingFile = false;\n",
        "  bool _sendingFile = false;\n  bool _hasText = false;\n",
    )
    replace(
        'lib/chat_screen.dart',
        "    _tunnel = widget.tunnel;\n    unawaited(_connect());",
        "    _tunnel = widget.tunnel;\n    _text.addListener(_onComposerChanged);\n    unawaited(_connect());",
    )

    composer_listener = """
  void _onComposerChanged() {
    final next = _text.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }

"""
    source = chat.read_text(encoding='utf-8')
    if 'void _onComposerChanged()' not in source:
        replace(
            'lib/chat_screen.dart',
            "  Future<void> _connect() async {",
            composer_listener + "  Future<void> _connect() async {",
        )

    replace(
        'lib/chat_screen.dart',
        """      final incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final index = messages.indexWhere((message) => message.id == incoming.id);
      if (index < 0) {
        messages.add(incoming);
""",
        """      var incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final index = messages.indexWhere((message) => message.id == incoming.id);
      final existing = index < 0 ? null : messages[index];
      incoming = CgMediaStore.preserveLocalPurge(existing, incoming);
      if (index < 0) {
        messages.add(incoming);
""",
    )

    replace(
        'lib/chat_screen.dart',
        "    const maxBytes = 8 * 1024 * 1024;",
        "    const maxBytes = 20 * 1024 * 1024;",
    )
    replace(
        'lib/chat_screen.dart',
        """                ? 'Сейчас можно отправить файл до 8 МБ. Для более крупных файлов готовится прямой P2P-канал.'
                : 'Files up to 8 MB are supported now. A direct P2P channel is being prepared for larger files.',
""",
        """                ? 'Сейчас можно отправить файл до 20 МБ. Большие медиа лучше отправлять короткими фрагментами.'
                : 'Files up to 20 MB are supported. Send very large media as shorter clips.',
""",
    )
    replace(
        'lib/chat_screen.dart',
        """      final attachment = CgAttachment(
        id: CgIds.random(20),
        name: file.name,
        size: bytes.length,
        kind: _attachmentKind(file.name),
        dataBase64: base64Encode(bytes),
        localPath: file.path,
      );
      final message = CgMessage(
        id: CgIds.random(24),
        authorId: widget.profile.id,
        authorName: widget.profile.nickname,
        text: '',
        sentAt: DateTime.now(),
        type: 'attachment',
        attachment: attachment,
      );
      _appendLocal(message);
      await _session?.sendMessage(message.toJson());
""",
        """      final id = CgIds.random(20);
      final local = await CgMediaStore.persistBytes(
        attachmentId: id,
        name: file.name,
        bytes: bytes,
      );
      final attachment = CgAttachment(
        id: id,
        name: file.name,
        size: bytes.length,
        kind: _attachmentKind(file.name),
        dataBase64: base64Encode(bytes),
        localPath: local.path,
      );
      await _sendAttachment(attachment);
""",
    )

    media_methods = """
  Future<void> _sendAttachment(CgAttachment attachment) async {
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: attachment,
    );
    _appendLocal(message);
    await _session?.sendMessage(message.toJson());
  }

  Future<void> _sendVoice(File file, Duration duration) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final id = CgIds.random(20);
    final local = await CgMediaStore.persistBytes(
      attachmentId: id,
      name: 'voice.m4a',
      bytes: bytes,
    );
    await _sendAttachment(
      CgAttachment(
        id: id,
        name: 'Голосовое ${duration.inSeconds} сек.m4a',
        size: bytes.length,
        kind: 'voice',
        dataBase64: base64Encode(bytes),
        localPath: local.path,
      ),
    );
  }

  Future<void> _recordCircle() async {
    final attachment = await Navigator.push<CgAttachment>(
      context,
      MaterialPageRoute(
        builder: (_) => CgCircleRecorderScreen(ru: widget.ru),
      ),
    );
    if (attachment != null) await _sendAttachment(attachment);
  }

"""
    source = chat.read_text(encoding='utf-8')
    if 'Future<void> _sendAttachment(CgAttachment attachment)' not in source:
        replace(
            'lib/chat_screen.dart',
            "  Future<void> _showAttachmentMenu() async {",
            media_methods + "  Future<void> _showAttachmentMenu() async {",
        )

    circle_action = """
                  _AttachmentAction(
                    icon: Icons.radio_button_checked_rounded,
                    label: widget.ru ? 'Кружок' : 'Circle',
                    onTap: () {
                      Navigator.pop(context);
                      _recordCircle();
                    },
                  ),
"""
    source = chat.read_text(encoding='utf-8')
    if "label: widget.ru ? 'Кружок' : 'Circle'" not in source:
        replace(
            'lib/chat_screen.dart',
            """                  _AttachmentAction(
                    icon: Icons.headphones_outlined,
""",
            circle_action
            + """                  _AttachmentAction(
                    icon: Icons.headphones_outlined,
""",
        )

    replace(
        'lib/chat_screen.dart',
        """                  _AttachmentPreview(
                    attachment: attachment,
                    hidden: privacyLens,
                  ),
""",
        """                  CgInlineAttachment(
                    attachment: attachment,
                    hidden: privacyLens,
                  ),
""",
    )

    replace(
        'lib/chat_screen.dart',
        """                    IconButton.filled(
                      onPressed: _sendText,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
""",
        """                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _hasText
                          ? IconButton.filled(
                              key: const ValueKey('send'),
                              onPressed: _sendText,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            )
                          : CgVoiceRecordButton(
                              key: const ValueKey('voice'),
                              ru: widget.ru,
                              enabled: _networkState == 'connected',
                              onRecorded: _sendVoice,
                            ),
                    ),
""",
    )

    replace(
        'lib/chat_screen.dart',
        """    await _session?.sendSignal({
      'action': 'call_accept',
      'callId': callId,
      'from': widget.profile.id,
      'target': fromId,
    });
    if (!mounted) return;
""",
        """    if (!mounted) return;
""",
    )
    replace(
        'lib/chat_screen.dart',
        """          peerName: fromName,
          callId: callId,
""",
        """          peerId: fromId,
          peerName: fromName,
          callId: callId,
""",
    )
    replace(
        'lib/chat_screen.dart',
        """  void dispose() {
    unawaited(ChernogramSound.stopIncomingCall());
    unawaited(_subscription?.cancel());
    _text.dispose();
""",
        """  void dispose() {
    unawaited(ChernogramSound.stopIncomingCall());
    unawaited(_subscription?.cancel());
    _text.removeListener(_onComposerChanged);
    _text.dispose();
""",
    )

    # Global media folder beside Privacy Lens.
    v07 = Path('lib/v07.dart')
    v07_source = v07.read_text(encoding='utf-8')
    if "import 'chat_media.dart';" not in v07_source:
        replace(
            'lib/v07.dart',
            "import 'chat_screen.dart';\n",
            "import 'chat_media.dart';\nimport 'chat_screen.dart';\n",
        )

    media_library_method = """
  Future<void> _openMediaLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMediaLibraryScreen(
          ru: widget.ru,
          tunnels: _tunnels,
          onTunnelsChanged: (updated) {
            _tunnels = updated;
            if (mounted) setState(() {});
            unawaited(CgStore.saveTunnels(_tunnels));
            _syncMonitor();
          },
        ),
      ),
    );
  }

"""
    v07_source = v07.read_text(encoding='utf-8')
    if 'Future<void> _openMediaLibrary()' not in v07_source:
        replace(
            'lib/v07.dart',
            "  Future<void> _saveProfile(CgProfile profile) async {",
            media_library_method + "  Future<void> _saveProfile(CgProfile profile) async {",
        )

    folder_button = """          GlassIconButton(
            icon: Icons.folder_copy_outlined,
            tooltip: widget.ru ? 'Файлы и медиа' : 'Files and media',
            onPressed: _openMediaLibrary,
          ),
          const SizedBox(width: 6),
"""
    v07_source = v07.read_text(encoding='utf-8')
    if "tooltip: widget.ru ? 'Файлы и медиа'" not in v07_source:
        replace(
            'lib/v07.dart',
            """        actions: [
          GlassIconButton(
            icon: _privacyLens
""",
            """        actions: [
"""
            + folder_button
            + """          GlassIconButton(
            icon: _privacyLens
""",
        )

    # App-wide monitor keeps local purges and does not race the call screen.
    monitor = Path('lib/app_monitor.dart')
    monitor_source = monitor.read_text(encoding='utf-8')
    if "import 'chat_media.dart';" not in monitor_source:
        replace(
            'lib/app_monitor.dart',
            "import 'call_service.dart';\n",
            "import 'call_service.dart';\nimport 'chat_media.dart';\n",
        )
    replace(
        'lib/app_monitor.dart',
        """    final message = CgMessage.fromJson(raw);
    if (message.id.isEmpty) return;

    final messages = <CgMessage>[...tunnel.messages];
    final index = messages.indexWhere((item) => item.id == message.id);
""",
        """    var message = CgMessage.fromJson(raw);
    if (message.id.isEmpty) return;

    final messages = <CgMessage>[...tunnel.messages];
    final index = messages.indexWhere((item) => item.id == message.id);
    message = CgMediaStore.preserveLocalPurge(
      index < 0 ? null : messages[index],
      message,
    );
""",
    )
    replace(
        'lib/app_monitor.dart',
        """    if (!group) {
      await session?.sendSignal(<String, dynamic>{
        'action': 'call_accept',
        'callId': callId,
        'from': profile.id,
        'target': from,
      });
    }
    final navigator = chernogramNavigatorKey.currentState;
""",
        """    final navigator = chernogramNavigatorKey.currentState;
""",
    )
    replace(
        'lib/app_monitor.dart',
        """                nickname: profile.nickname,
                peerName: fromName,
                callId: callId,
""",
        """                nickname: profile.nickname,
                peerId: from,
                peerName: fromName,
                callId: callId,
""",
    )

    # Replay recent call signals so an offer cannot be lost while the user
    # accepts the incoming call dialog.
    core = Path('lib/internet_core.dart')
    core_source = core.read_text(encoding='utf-8')
    if '_signalBacklog' not in core_source:
        replace(
            'lib/internet_core.dart',
            "  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];\n",
            "  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];\n  final Map<String, List<Map<String, dynamic>>> _signalBacklog =\n      <String, List<Map<String, dynamic>>>{};\n",
        )

    replay_method = """
  List<Map<String, dynamic>> replaySignals(String callId) {
    final signals = _signalBacklog[callId] ?? const <Map<String, dynamic>>[];
    return signals.map(Map<String, dynamic>.from).toList();
  }

  void _rememberSignal(Map<String, dynamic> signal) {
    final callId = signal['callId']?.toString() ?? '';
    if (callId.isEmpty) return;
    final list = _signalBacklog.putIfAbsent(
      callId,
      () => <Map<String, dynamic>>[],
    );
    final signature = '${signal['action']}|${signal['from']}|${signal['sdp']?.hashCode}|${signal['candidate']?.hashCode}';
    if (list.any((item) => item['_signature'] == signature)) return;
    list.add(<String, dynamic>{...signal, '_signature': signature});
    if (list.length > 160) list.removeRange(0, list.length - 160);
    if (_signalBacklog.length > 80) {
      _signalBacklog.remove(_signalBacklog.keys.first);
    }
  }

"""
    core_source = core.read_text(encoding='utf-8')
    if 'List<Map<String, dynamic>> replaySignals' not in core_source:
        replace(
            'lib/internet_core.dart',
            "  Future<void> connect() async {",
            replay_method + "  Future<void> connect() async {",
        )
    replace(
        'lib/internet_core.dart',
        """      case 'signal':
        _emit('signal', <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
""",
        """      case 'signal':
        final signal = <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        };
        _rememberSignal(signal);
        _emit('signal', signal);
        break;
""",
    )

    # Android storage meter and SDK required by camera/video_player.
    replace(
        'android/app/build.gradle.kts',
        '        minSdk = 23',
        '        minSdk = 24',
    )
    activity = Path(
        'android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt'
    )
    activity_source = activity.read_text(encoding='utf-8')
    if 'import android.os.StatFs' not in activity_source:
        replace(
            str(activity),
            'import android.os.Build\n',
            'import android.os.Build\nimport android.os.Environment\nimport android.os.StatFs\n',
        )
    activity_source = activity.read_text(encoding='utf-8')
    if 'chernogram/storage' not in activity_source:
        replace(
            str(activity),
            """        ).setMethodCallHandler { call, result ->
            when (call.method) {
""",
            """        ).setMethodCallHandler { call, result ->
            when (call.method) {
""",
        )
        replace(
            str(activity),
            """        }
    }

    private fun playNotificationSound() {
""",
            """        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/storage"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getStorageStats") {
                val stat = StatFs(Environment.getDataDirectory().path)
                result.success(
                    mapOf(
                        "freeBytes" to stat.availableBytes,
                        "totalBytes" to stat.totalBytes
                    )
                )
            } else {
                result.notImplemented()
            }
        }
    }

    private fun playNotificationSound() {
""",
        )

    print('Applied Chernogram 0.9 media library, voice, circles and WebRTC replay fixes')


if __name__ == '__main__':
    main()
