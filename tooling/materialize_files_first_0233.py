from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def replace_range(text: str, start: str, end: str, replacement: str, label: str) -> str:
    if replacement.strip() in text:
        return text
    left = text.find(start)
    if left < 0:
        raise RuntimeError(f"{label}: start anchor not found")
    right = text.find(end, left)
    if right < 0:
        raise RuntimeError(f"{label}: end anchor not found")
    return text[:left] + replacement.rstrip() + "\n\n" + text[right:]


def patch_internet_core() -> None:
    path = ROOT / "lib" / "internet_core.dart"
    text = path.read_text(encoding="utf-8")

    old_history = """    final recent = _history.skip(start).toList(growable: false);
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
"""
    new_history = """    final recent = _history.skip(start).toList(growable: false);
    final plain = recent
        .where((message) => message['attachment'] is! Map)
        .toList(growable: false);
    if (plain.isNotEmpty) {
      await _sendEnvelope(
        'history',
        <String, dynamic>{'messages': plain},
        queueOnFailure: false,
      );
    }
    final files = recent
        .where((message) => message['attachment'] is Map)
        .toList(growable: false);
    for (final message in files.take(12)) {
      final id = message['id']?.toString() ?? '';
      final original = _fileMessages[id] ?? message;
      final payload = _filePayloads[id] ?? await _loadFilePayload(original);
      if (payload == null || payload.isEmpty) continue;
      _filePayloads[id] = payload;
      if (payload.length <= _inlineFileChars) {
        final networkMessage = _withFilePayload(original, payload);
        await _sendEnvelope(
          'message',
          <String, dynamic>{'message': networkMessage},
          queueOnFailure: false,
        );
      } else {
        await _sendLargeFileMessage(_withFilePayload(original, payload), payload);
      }
    }
"""
    text = replace_once(text, old_history, new_history, "file history replay")

    old_remember = """  void _rememberLocalFile(Map<String, dynamic> message) {
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
"""
    new_remember = """  void _rememberLocalFile(Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final rawAttachment = message['attachment'];
    if (rawAttachment is! Map) return;
    final attachment = Map<String, dynamic>.from(rawAttachment);
    _fileMessages[id] = Map<String, dynamic>.from(message);
    final payload = attachment['dataBase64']?.toString();
    if (payload != null && payload.isNotEmpty) _filePayloads[id] = payload;
  }

  Future<String?> _loadFilePayload(Map<String, dynamic> message) async {
    final rawAttachment = message['attachment'];
    if (rawAttachment is! Map) return null;
    final attachment = Map<String, dynamic>.from(rawAttachment);
    final inline = attachment['dataBase64']?.toString();
    if (inline != null && inline.isNotEmpty) return inline;
    final localPath = attachment['localPath']?.toString() ??
        attachment['path']?.toString();
    if (localPath == null || localPath.isEmpty) return null;
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;
      return base64Encode(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _withFilePayload(
    Map<String, dynamic> message,
    String payload,
  ) {
    final copy = Map<String, dynamic>.from(message);
    final rawAttachment = copy['attachment'];
    if (rawAttachment is Map) {
      copy['attachment'] = Map<String, dynamic>.from(rawAttachment)
        ..['dataBase64'] = payload;
    }
    return copy;
  }

  String? _filePayloadFor(Map<String, dynamic> message) {
"""
    text = replace_once(text, old_remember, new_remember, "local file recovery")
    path.write_text(text, encoding="utf-8")


def patch_app_monitor() -> None:
    path = ROOT / "lib" / "app_monitor.dart"
    text = path.read_text(encoding="utf-8")
    text = text.replace("final monitored = recent.take(8)", "final monitored = recent.take(6)")
    text = text.replace("      unawaited(InternetRelay.close(tunnelId));\n", "")

    old_ensure = """  static Future<void> _ensureTunnel(CgTunnel tunnel) async {
    final profile = _profile;
    if (profile == null) return;
    final session = await InternetRelay.open(
      tunnelId: tunnel.id,
      secret: tunnel.secret,
      profileId: profile.id,
      nickname: profile.nickname,
      history: tunnel.messages.map((message) => message.toJson()).toList(),
    );
    if (identical(_sessions[tunnel.id], session) &&
        _subscriptions.containsKey(tunnel.id)) {
      return;
    }
    await _subscriptions.remove(tunnel.id)?.cancel();
    _sessions[tunnel.id] = session;
    _subscriptions[tunnel.id] = session.events.listen(
      (event) => _onEvent(tunnel.id, event),
    );
  }
"""
    new_ensure = """  static Future<void> _ensureTunnel(CgTunnel tunnel) async {
    final profile = _profile;
    if (profile == null) return;
    try {
      final session = await InternetRelay.open(
        tunnelId: tunnel.id,
        secret: tunnel.secret,
        profileId: profile.id,
        nickname: profile.nickname,
        history: tunnel.messages.map((message) => message.toJson()).toList(),
      );
      if (identical(_sessions[tunnel.id], session) &&
          _subscriptions.containsKey(tunnel.id)) {
        return;
      }
      await _subscriptions.remove(tunnel.id)?.cancel();
      _sessions[tunnel.id] = session;
      _subscriptions[tunnel.id] = session.events.listen(
        (event) => _onEvent(tunnel.id, event),
      );
    } catch (_) {
      // Background monitoring must never block navigation or message input.
    }
  }
"""
    text = replace_once(text, old_ensure, new_ensure, "safe background monitor")

    old_publish = """  static Future<void> publishMessage({
    required CgProfile profile,
    required CgTunnel tunnel,
    required CgMessage message,
  }) async {
    _profile ??= profile;
    _tunnels[tunnel.id] = tunnel;
    await _ensureTunnel(tunnel);
    final session = _sessions[tunnel.id];
    if (session == null) {
      throw StateError('Room transport is unavailable');
    }
    session.replaceHistory(
      tunnel.messages.map((item) => item.toJson()).toList(),
    );
    await session.sendMessage(message.toJson());
  }
"""
    new_publish = """  static Future<void> publishMessage({
    required CgProfile profile,
    required CgTunnel tunnel,
    required CgMessage message,
  }) async {
    _profile ??= profile;
    _tunnels[tunnel.id] = tunnel;
    try {
      await _ensureTunnel(tunnel);
      final session = _sessions[tunnel.id] ?? InternetRelay.session(tunnel.id);
      if (session == null) return;
      session.replaceHistory(
        tunnel.messages.map((item) => item.toJson()).toList(),
      );
      unawaited(session.sendMessage(message.toJson()));
    } catch (_) {
      // The message is already persisted locally and will be replayed later.
    }
  }
"""
    text = replace_once(text, old_publish, new_publish, "non-blocking publish")
    text = replace_once(
        text,
        """    _sessions.clear();
    _tunnels.clear();
    await ChernogramSound.stopIncomingCall();
""",
        """    _sessions.clear();
    _tunnels.clear();
    await InternetRelay.shutdownAll();
    await ChernogramSound.stopIncomingCall();
""",
        "monitor shutdown",
    )
    path.write_text(text, encoding="utf-8")


def patch_chat_screen() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")

    old_send = """  void _sendMessageBackground(CgMessage message) {
    final session = _session;
    if (session == null) {
      unawaited(_connect().then((_) => _session?.sendMessage(message.toJson())));
      return;
    }
    unawaited(
      session.sendMessage(message.toJson()).timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      ),
    );
  }
"""
    new_send = """  void _sendMessageBackground(CgMessage message) {
    final session = _session;
    if (session != null) {
      unawaited(session.sendMessage(message.toJson()));
      return;
    }
    unawaited(
      _connect().then((_) {
        final ready = _session;
        if (ready != null) unawaited(ready.sendMessage(message.toJson()));
      }),
    );
  }
"""
    text = replace_once(text, old_send, new_send, "instant message send")

    old_connect = """      setState(() {
        _networkState = session.connected ? 'connected' : 'connecting';
        _onlinePeers = session.onlinePeers;
      });
      unawaited(session.sendHistory());
    } catch (_) {
      if (!mounted) return;
      setState(() => _networkState = 'error');
    }
"""
    new_connect = """      setState(() {
        _networkState = session.connected ? 'connected' : 'queued';
        _onlinePeers = session.onlinePeers;
      });
      unawaited(session.sendHistory());
    } catch (_) {
      // Input remains available; the transport retries from its durable outbox.
    }
"""
    text = replace_once(text, old_connect, new_connect, "silent connect")

    old_merge = """  void _mergeMessages(List<Map<String, dynamic>> raw) {
    final messages = <CgMessage>[..._tunnel.messages];
    var changed = false;
    for (final item in raw) {
      var incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final index = messages.indexWhere((message) => message.id == incoming.id);
      final existing = index < 0 ? null : messages[index];
      incoming = CgMediaStore.preserveLocalPurge(existing, incoming);
      if (index < 0) {
        messages.add(incoming);
        changed = true;
        continue;
      }
      if (jsonEncode(messages[index].toJson()) !=
          jsonEncode(incoming.toJson())) {
        messages[index] = incoming;
        changed = true;
      }
    }
    if (!changed) return;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    _scrollToBottom();
  }
"""
    new_merge = """  void _mergeMessages(List<Map<String, dynamic>> raw) {
    unawaited(_mergeMessagesAsync(raw));
  }

  Future<void> _mergeMessagesAsync(List<Map<String, dynamic>> raw) async {
    final messages = <CgMessage>[..._tunnel.messages];
    var changed = false;
    for (final item in raw) {
      var incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final attachment = incoming.attachment;
      if (attachment?.dataBase64?.isNotEmpty == true) {
        try {
          final bytes = base64Decode(attachment!.dataBase64!);
          final file = await CgMediaStore.persistBytes(
            attachmentId: attachment.id,
            name: attachment.name,
            bytes: bytes,
          );
          incoming = incoming.copyWith(
            attachment: CgAttachment(
              id: attachment.id,
              name: attachment.name,
              size: attachment.size,
              kind: attachment.kind,
              localPath: file.path,
            ),
            meta: <String, dynamic>{...incoming.meta, 'fileReady': true},
          );
        } catch (_) {}
      }
      final index = messages.indexWhere((message) => message.id == incoming.id);
      final existing = index < 0 ? null : messages[index];
      incoming = CgMediaStore.preserveLocalPurge(existing, incoming);
      if (index < 0) {
        messages.add(incoming);
        changed = true;
        continue;
      }
      if (jsonEncode(messages[index].toJson()) !=
          jsonEncode(incoming.toJson())) {
        messages[index] = incoming;
        changed = true;
      }
    }
    if (!changed || !mounted) return;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    _scrollToBottom();
  }
"""
    text = replace_once(text, old_merge, new_merge, "file materialization")

    old_attachment = """  Future<void> _sendAttachment(CgAttachment attachment) async {
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: attachment,
      meta: _replyMeta(),
    );
    setState(() => _replyingTo = null);
    _appendLocal(message);
    _sendMessageBackground(message);
  }
"""
    new_attachment = """  Future<void> _sendAttachment(CgAttachment attachment) async {
    final id = CgIds.random(24);
    final meta = _replyMeta();
    final localAttachment = CgAttachment(
      id: attachment.id,
      name: attachment.name,
      size: attachment.size,
      kind: attachment.kind,
      localPath: attachment.localPath,
    );
    final localMessage = CgMessage(
      id: id,
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: localAttachment,
      meta: <String, dynamic>{...meta, 'fileReady': true},
    );
    final networkMessage = CgMessage(
      id: id,
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: localMessage.sentAt,
      type: 'attachment',
      attachment: attachment,
      meta: meta,
    );
    setState(() => _replyingTo = null);
    _appendLocal(localMessage);
    _sendMessageBackground(networkMessage);
  }
"""
    text = replace_once(text, old_attachment, new_attachment, "lean local files")

    for guard in (
        """    if (_networkState != 'connected') {
      _showNotConnected();
      return;
    }
""",
    ):
        text = text.replace(guard, "")

    status_start = "  String get _statusText {\n"
    status_end = "  @override\n  void dispose()"
    status = """  String get _statusText => _onlinePeers > 1
      ? (widget.ru ? 'Онлайн • $_onlinePeers' : 'Online • $_onlinePeers')
      : (widget.ru ? 'Чат готов' : 'Chat ready');
"""
    text = replace_range(text, status_start, status_end, status, "neutral status")

    banner_start = """            if (_networkState != 'connected')
              Padding(
"""
    banner_end = """            if (_selectedMessageIds.isNotEmpty)
"""
    if banner_start in text:
        left = text.index(banner_start)
        right = text.index(banner_end, left)
        text = text[:left] + text[right:]

    text = text.replace("enabled: _networkState == 'connected'", "enabled: true")
    path.write_text(text, encoding="utf-8")


def patch_android_shell() -> None:
    path = ROOT / "lib" / "android_data_first.dart"
    text = path.read_text(encoding="utf-8")
    text = text.replace("import 'agent_screen.dart';\n", "")

    agent_start = """      _ProfileAction(
        icon: Icons.auto_awesome_rounded,
        title: ru ? 'Агент и автоматизация' : 'Agent and automation',
"""
    if agent_start in text:
        left = text.index(agent_start)
        next_marker = """      _ProfileAction(
        icon: Icons.install_mobile_rounded,
"""
        right = text.index(next_marker, left)
        text = text[:left] + text[right:]

    text = text.replace(
        "Общие файлы индексируются внутри открытых комнат, к которым подключён пользователь.",
        "Общие файлы находятся в едином поиске после подключения к открытой комнате по ссылке.",
    )
    text = text.replace(
        "Shared files are indexed inside public rooms joined by the user.",
        "Shared files appear in one search after joining a public room by link.",
    )
    text = text.replace(
        "Файл пока доступен только на устройстве отправителя.",
        "Файл ещё загружается. Он откроется автоматически после получения всех частей.",
    )
    text = text.replace(
        "The file is currently available only on the sender device.",
        "The file is still downloading and will open after all chunks arrive.",
    )
    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_internet_core()
    patch_app_monitor()
    patch_chat_screen()
    patch_android_shell()
    print("Chernogram 0.23.3 files-first source materialized")


if __name__ == "__main__":
    main()
