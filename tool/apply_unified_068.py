from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'anchor not found: {label}')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'regex anchor count {count}: {label}')
    return result


# Stable profile identity after reinstall.
path = Path('lib/core_models.dart')
text = path.read_text(encoding='utf-8')
if "import 'device_identity.dart';" not in text:
    text = replace_once(
        text,
        "import 'package:shared_preferences/shared_preferences.dart';\n",
        "import 'package:shared_preferences/shared_preferences.dart';\n\nimport 'device_identity.dart';\n",
        'core identity import',
    )
text = replace_once(
    text,
    "    final profile = CgProfile(\n      id: CgIds.random(12),",
    "    final profile = CgProfile(\n      id: await CgDeviceIdentity.stableProfileId(),",
    'stable profile id',
)
path.write_text(text, encoding='utf-8')


# Android navigation, QR pairing, settings and removal of internal agent/roadmap UI.
path = Path('lib/android_data_first.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import 'agent_screen.dart';\n", '')
if "import 'client_settings.dart';" not in text:
    text = replace_once(
        text,
        "import 'chat_screen.dart';\nimport 'core_models.dart';\n",
        "import 'chat_screen.dart';\nimport 'client_settings.dart';\nimport 'core_models.dart';\nimport 'device_pairing.dart';\n",
        'android helper imports',
    )

text = regex_once(
    text,
    r"  Future<void> _handleUri\(Uri uri\) async \{.*?\n  \}\n",
    """  Future<void> _handleUri(Uri uri) async {
    if (await sendRoomToDesktopPairing(
      context: context,
      ru: widget.ru,
      uri: uri,
      tunnels: _tunnels,
    )) {
      return;
    }
    final token = _tokenFromUri(uri);
    if (token != null) await _joinToken(token);
  }
""",
    'android uri handler',
)

text = regex_once(
    text,
    r"  Future<void> _scanInvite\(\) async \{.*?\n  \}\n",
    """  Future<void> _scanInvite() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => CgInviteQrScanner(ru: widget.ru)),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final uri = Uri.tryParse(raw.trim());
    if (uri != null &&
        await sendRoomToDesktopPairing(
          context: context,
          ru: widget.ru,
          uri: uri,
          tunnels: _tunnels,
        )) {
      return;
    }
    var token = raw.trim();
    if (uri != null) token = _tokenFromUri(uri) ?? token;
    await _joinToken(token);
  }
""",
    'android QR scan handler',
)

# Pass contacts to chat list and show online dots.
text = replace_once(
    text,
    "        tunnels: _tunnels,\n        onOpen: _openTunnel,",
    "        tunnels: _tunnels,\n        contacts: _contacts,\n        onOpen: _openTunnel,",
    'chat contacts argument',
)
text = replace_once(
    text,
    "  final List<CgTunnel> tunnels;\n  final Future<void> Function(CgTunnel tunnel) onOpen;",
    "  final List<CgTunnel> tunnels;\n  final List<CgContact> contacts;\n  final Future<void> Function(CgTunnel tunnel) onOpen;",
    'chat contacts field',
)
text = replace_once(
    text,
    "    required this.tunnels,\n    required this.onOpen,",
    "    required this.tunnels,\n    required this.contacts,\n    required this.onOpen,",
    'chat contacts constructor',
)
text = replace_once(
    text,
    "  String _preview(CgTunnel tunnel) {",
    """  bool _online(CgTunnel tunnel) {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 55));
    return widget.contacts.any(
      (contact) =>
          contact.tunnelIds.contains(tunnel.id) &&
          contact.lastSeenAt.isAfter(cutoff),
    );
  }

  String _preview(CgTunnel tunnel) {""",
    'android online helper',
)
text = replace_once(
    text,
    "                    final group = _isGroup(tunnel);\n                    return Material(",
    "                    final group = _isGroup(tunnel);\n                    final online = _online(tunnel);\n                    return Material(",
    'android online item',
)
text = replace_once(
    text,
    """                              if (group) ...[
                                ChernogramAvatar(
                                  size: 48,
                                  seed: tunnel.id,
                                  avatarBase64: tunnel.avatarBase64,
                                ),
                                const SizedBox(width: 12),
                              ],
""",
    """                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ChernogramAvatar(
                                    size: 48,
                                    seed: tunnel.id,
                                    avatarBase64: tunnel.avatarBase64,
                                  ),
                                  if (online)
                                    Positioned(
                                      right: -1,
                                      bottom: -1,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: ChernogramColors.success,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Theme.of(context).colorScheme.surface,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
""",
    'android room avatar online dot',
)

# Remove agent action from profile.
text = regex_once(
    text,
    r"\n      _ProfileAction\(\n        icon: Icons\.auto_awesome_rounded,\n        title: ru \? 'Агент и автоматизация'.*?\n      \),\n      const SizedBox\(height: 8\),",
    "",
    'remove agent profile action',
)

# Replace plain install link with a QR installation screen.
text = regex_once(
    text,
    r"      _ProfileAction\(\n        icon: Icons\.install_mobile_rounded,\n        title: ru \? 'Отправить приложение'.*?\n      \),",
    """      _ProfileAction(
        icon: Icons.install_mobile_rounded,
        title: ru ? 'Поделиться приложением' : 'Share the app',
        subtitle: ru
            ? 'QR-код и прямая ссылка на актуальную Android-версию.'
            : 'QR code and direct link to the current Android version.',
        onTap: () => showChernogramInstallShare(context, ru: ru),
      ),""",
    'install QR action',
)

account_anchor = """      _ProfileAction(
        icon: Icons.fingerprint_rounded,
        title: ru ? 'Доступ и перенос аккаунта' : 'Access and account transfer',
"""
account_insert = """      _ProfileAction(
        icon: Icons.account_circle_outlined,
        title: ru ? 'Аккаунт и устройство' : 'Account and device',
        subtitle: ru
            ? 'Устойчивый ID устройства и восстановление после переустановки.'
            : 'Stable device ID and reinstall recovery.',
        onTap: () => showDeviceAccountSheet(
          context,
          ru: ru,
          profile: profile,
        ),
      ),
      const SizedBox(height: 8),
      if (Platform.isAndroid) ...[
        _ProfileAction(
          icon: Icons.notifications_active_outlined,
          title: ru ? 'Всегда на связи' : 'Always connected',
          subtitle: ru
              ? 'Сообщения и звонки при свёрнутом или закрытом окне.'
              : 'Messages and calls while the window is minimized or closed.',
          onTap: () => showBackgroundConnectionSettings(context, ru: ru),
        ),
        const SizedBox(height: 8),
      ],
""" + account_anchor
text = replace_once(text, account_anchor, account_insert, 'account and background actions')

text = text.replace("title: ru ? 'Два устройства' : 'Two devices'", "title: ru ? 'Связанные устройства' : 'Linked devices'")
text = text.replace("'Один аккаунт — телефон и компьютер.'", "'Один профиль на телефонах и Windows.'")
text = text.replace("'One account on phone and computer.'", "'One profile across phones and Windows.'")
text = text.replace("ru ? 'Приоритет' : 'Priority'", "ru ? 'О приложении' : 'About'")
text = text.replace(
    "'Быстрые чаты, звонки, видео и передача данных. Агент и функции ИИ удалены из навигации и больше не участвуют в продукте.'",
    "'Чаты, звонки и передача файлов без рекламы и лишних разделов.'",
)
text = text.replace(
    "'Fast chats, calls, video, and data transfer. Agent and AI features are removed from the product flow.'",
    "'Chats, calls, and file exchange without ads or unnecessary sections.'",
)
text = text.replace(
    "'Прелендинг подготовлен. Здесь будет короткое объяснение сервиса: быстрые чаты, звонки и свободная передача данных между устройствами без рекламной ленты и ИИ-агента.'",
    "'Чернограм объединяет быстрые чаты, звонки и передачу данных между устройствами.'",
)
text = text.replace(
    "'The prelanding entry is prepared. It will explain fast chats, calls, and direct data transfer without an advertising feed or AI agent.'",
    "'Chernogram combines fast chats, calls, and direct data transfer between devices.'",
)
path.write_text(text, encoding='utf-8')


# Message actions, reactions, read receipts, online dots and desktop adaptation.
path = Path('lib/chat_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  int _onlinePeers = 1;\n  bool _sendingFile = false;",
    "  int _onlinePeers = 1;\n  final Map<String, String> _onlineMembers = <String, String>{};\n  bool _sendingFile = false;",
    'online member field',
)
text = replace_once(
    text,
    """        final name = event.data['name']?.toString() ?? 'user';
        _rememberContact(id, name);
        if (_announcedPeers.add(id)) {
""",
    """        final name = event.data['name']?.toString() ?? 'user';
        _rememberContact(id, name);
        if (id.isNotEmpty) {
          setState(() => _onlineMembers[id] = name);
        }
        if (_announcedPeers.add(id)) {
""",
    'peer member tracking',
)
text = regex_once(
    text,
    r"      case 'presence':\n        setState\(\(\) \{.*?\n        break;",
    """      case 'presence':
        final rawMembers = (event.data['members'] as List?) ?? const [];
        setState(() {
          _onlinePeers =
              int.tryParse(event.data['peers']?.toString() ?? '') ?? 1;
          _onlineMembers.clear();
          for (final raw in rawMembers.whereType<Map>()) {
            final member = Map<String, dynamic>.from(raw);
            final id = member['id']?.toString() ?? '';
            if (id.isEmpty || id == widget.profile.id) continue;
            _onlineMembers[id] = member['name']?.toString() ?? 'user';
          }
        });
        break;""",
    'presence members',
)
text = replace_once(
    text,
    """    _persist();
    _scrollToBottom();
  }

  Future<void> _handleControl""",
    """    _persist();
    _scrollToBottom();
    _sendReadReceipt();
  }

  void _sendReadReceipt() {
    for (final message in _tunnel.messages.reversed) {
      if (message.deleted || message.authorId == widget.profile.id) continue;
      _sendControlBackground(<String, dynamic>{
        'operationId': CgIds.random(24),
        'action': 'read_receipt',
        'messageId': message.id,
      });
      return;
    }
  }

  Future<void> _handleControl""",
    'send read receipt',
)
text = replace_once(
    text,
    """      case 'tunnel_update':
""",
    """      case 'read_receipt':
        final messageId = data['messageId']?.toString() ?? '';
        if (messageId.isEmpty || sender.isEmpty) return;
        final messages = <CgMessage>[..._tunnel.messages];
        final target = messages.indexWhere((message) => message.id == messageId);
        if (target < 0) return;
        var changed = false;
        for (var index = 0; index <= target; index++) {
          final message = messages[index];
          if (message.authorId != widget.profile.id) continue;
          final readBy = ((message.meta['readBy'] as List?) ?? const <dynamic>[])
              .map((item) => item.toString())
              .toSet();
          if (!readBy.add(sender)) continue;
          messages[index] = message.copyWith(
            meta: <String, dynamic>{...message.meta, 'readBy': readBy.toList()},
          );
          changed = true;
        }
        if (changed) {
          setState(() => _tunnel = _tunnel.copyWith(messages: messages));
          _persist();
        }
        break;
      case 'tunnel_update':
""",
    'read receipt control',
)

reaction_picker = """
  Future<void> _showReactionPicker(CgMessage message) async {
    if (message.deleted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: ['👍', '❤️', '😂', '🔥', '👏', '🤝']
                .map(
                  (emoji) => InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.pop(context, emoji),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (selected != null) await _toggleReaction(message, selected);
  }

"""
text = replace_once(
    text,
    "  Future<void> _showMessageActions(CgMessage message) async {",
    reaction_picker + "  Future<void> _showMessageActions(CgMessage message) async {",
    'quick reaction picker',
)
text = replace_once(
    text,
    """              if (message.authorId == widget.profile.id)
                ListTile(
""",
    """              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: Text(widget.ru ? 'Выбрать' : 'Select'),
                onTap: () => Navigator.pop(context, '__select__'),
              ),
              if (message.authorId == widget.profile.id)
                ListTile(
""",
    'message select action',
)
text = replace_once(
    text,
    """    if (selected == '__delete__') {
      await _deleteMessage(message);
""",
    """    if (selected == '__delete__') {
      await _deleteMessage(message);
    } else if (selected == '__select__') {
      _toggleMessageSelection(message);
""",
    'message select handler',
)
text = replace_once(
    text,
    """                        final bubble = DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: selected
                                ? Border.all(color: scheme.primary, width: 2)
                                : null,
                          ),
                          child: _MessageBubble(
                            message: message,
                            mine: mine,
                            groupChat: _isGroupChat,
                            privacyLens: widget.privacyLens,
                            ru: widget.ru,
                            onLongPress: () => _toggleMessageSelection(message),
                          ),
                        );
""",
    """                        final bubble = Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 34),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: selected
                                      ? Border.all(color: scheme.primary, width: 2)
                                      : null,
                                ),
                                child: _MessageBubble(
                                  message: message,
                                  mine: mine,
                                  groupChat: _isGroupChat,
                                  privacyLens: widget.privacyLens,
                                  ru: widget.ru,
                                  delivered: _networkState == 'connected',
                                  read: ((message.meta['readBy'] as List?) ??
                                          const <dynamic>[])
                                      .isNotEmpty,
                                  onLongPress: () => _showMessageActions(message),
                                ),
                              ),
                            ),
                            if (!message.deleted)
                              Positioned(
                                left: 0,
                                bottom: 10,
                                child: SizedBox.square(
                                  dimension: 32,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    tooltip: widget.ru ? 'Реакция' : 'Reaction',
                                    onPressed: () => _showReactionPicker(message),
                                    icon: const Icon(
                                      Icons.add_reaction_outlined,
                                      size: 19,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
""",
    'message reaction button and long press',
)
text = replace_once(
    text,
    """  final bool ru;
  final VoidCallback onLongPress;

  const _MessageBubble({
""",
    """  final bool ru;
  final bool delivered;
  final bool read;
  final VoidCallback onLongPress;

  const _MessageBubble({
""",
    'message bubble receipt fields',
)
text = replace_once(
    text,
    """    required this.ru,
    required this.onLongPress,
  });
""",
    """    required this.ru,
    required this.delivered,
    required this.read,
    required this.onLongPress,
  });
""",
    'message bubble receipt constructor',
)
text = replace_once(
    text,
    """          Text(
            _formatTime(message.sentAt),
""",
    """          if (mine) ...[
            Icon(
              read
                  ? Icons.done_all_rounded
                  : delivered
                  ? Icons.done_rounded
                  : Icons.schedule_rounded,
              size: 14,
              color: read
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: .42),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            _formatTime(message.sentAt),
""",
    'receipt icon in info row',
)
text = replace_once(
    text,
    """      return widget.ru ? 'Онлайн • $_onlinePeers' : 'Online • $_onlinePeers';
""",
    """      final dots = List<String>.filled(
        _onlinePeers.clamp(1, 4).toInt(),
        '●',
      ).join(' ');
      return widget.ru
          ? '$dots  Онлайн • $_onlinePeers'
          : '$dots  Online • $_onlinePeers';
""",
    'online dots status',
)
text = replace_once(
    text,
    """            : const BackButton(),
""",
    """            : Platform.isWindows
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ChernogramAvatar(
                  size: 42,
                  seed: _tunnel.id,
                  avatarBase64: _tunnel.avatarBase64,
                ),
              )
            : const BackButton(),
""",
    'desktop no back button',
)
path.write_text(text, encoding='utf-8')


# Circular videos: immediate inline circular playback, no rectangular file cloud.
path = Path('lib/chat_media.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    if (CgMediaStore.isAudio(attachment)) {
""",
    """    if (attachment.kind == 'circle') {
      return _CgInlineCircle(fileFuture: _ensure());
    }
    if (CgMediaStore.isAudio(attachment)) {
""",
    'inline circle branch',
)
circle_class = r'''
class _CgInlineCircle extends StatefulWidget {
  final Future<File?> fileFuture;

  const _CgInlineCircle({required this.fileFuture});

  @override
  State<_CgInlineCircle> createState() => _CgInlineCircleState();
}

class _CgInlineCircleState extends State<_CgInlineCircle> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final file = await widget.fileFuture;
    if (file == null || !await file.exists()) return;
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(0);
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _ready = true;
    });
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return GestureDetector(
      onTap: _toggle,
      child: SizedBox.square(
        dimension: 176,
        child: ClipOval(
          child: ColoredBox(
            color: Colors.black,
            child: !_ready || controller == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      if (!controller.value.isPlaying)
                        const Center(
                          child: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

'''
text = replace_once(
    text,
    "class CgMediaLibraryScreen extends StatefulWidget {",
    circle_class + "class CgMediaLibraryScreen extends StatefulWidget {",
    'inline circle class',
)
path.write_text(text, encoding='utf-8')


# Read receipts also update rooms monitored outside an open chat.
path = Path('lib/app_monitor.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    } else if (action == 'tunnel_update' && sender == tunnel.ownerId) {
""",
    """    } else if (action == 'read_receipt') {
      final id = data['messageId']?.toString() ?? '';
      final target = tunnel.messages.indexWhere((message) => message.id == id);
      if (target < 0 || sender.isEmpty) return;
      final messages = <CgMessage>[...tunnel.messages];
      var changed = false;
      for (var index = 0; index <= target; index++) {
        final message = messages[index];
        if (message.authorId != profile.id) continue;
        final readBy = ((message.meta['readBy'] as List?) ?? const <dynamic>[])
            .map((item) => item.toString())
            .toSet();
        if (!readBy.add(sender)) continue;
        messages[index] = message.copyWith(
          meta: <String, dynamic>{...message.meta, 'readBy': readBy.toList()},
        );
        changed = true;
      }
      if (changed) {
        final updated = tunnel.copyWith(messages: messages);
        _tunnels[tunnelId] = updated;
        _onTunnelChanged?.call(updated);
      }
    } else if (action == 'tunnel_update' && sender == tunnel.ownerId) {
""",
    'monitor read receipts',
)
path.write_text(text, encoding='utf-8')

print('Unified Android/Windows build 68 patches applied successfully.')
