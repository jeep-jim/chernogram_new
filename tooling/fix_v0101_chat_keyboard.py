from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def replace_between(path: str, start: str, end: str, replacement: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    left = source.find(start)
    if left < 0:
        return
    right = source.find(end, left)
    if right < 0:
        return
    file.write_text(source[:left] + replacement + source[right:], encoding='utf-8')


def main() -> None:
    chat_path = 'lib/chat_screen.dart'

    # Keyboard stays closed until the composer is tapped. Opening a chat
    # always lands on the newest messages, and tapping/dragging outside hides it.
    replace(
        chat_path,
        """  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
""",
        """  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'chat-composer');
""",
    )
    replace(
        chat_path,
        """    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connect());
""",
        """    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connect());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _composerFocus.unfocus();
      _scrollToBottom(animate: false);
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _scrollToBottom(animate: false);
      });
    });
""",
    )
    replace(
        chat_path,
        """  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }
""",
        """  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (!animate) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }
""",
    )
    replace(
        chat_path,
        """                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
""",
        """                : ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
""",
    )
    replace(
        chat_path,
        """                      child: TextField(
                        controller: _text,
                        minLines: 1,
""",
        """                      child: TextField(
                        controller: _text,
                        focusNode: _composerFocus,
                        autofocus: false,
                        onTapOutside: (_) => _composerFocus.unfocus(),
                        minLines: 1,
""",
    )
    replace(
        chat_path,
        """    _text.removeListener(_onComposerChanged);
    _text.dispose();
    _scroll.dispose();
""",
        """    _text.removeListener(_onComposerChanged);
    _composerFocus.dispose();
    _text.dispose();
    _scroll.dispose();
""",
    )

    # Every participant can open complete chat information and can leave/delete
    # their local chat. Editing shared parameters remains owner-only.
    replace(
        chat_path,
        """  final ValueChanged<CgTunnel> onChanged;
  final ValueChanged<CgContact>? onContactSeen;
""",
        """  final ValueChanged<CgTunnel> onChanged;
  final Future<void> Function(CgTunnel tunnel)? onDelete;
  final ValueChanged<CgContact>? onContactSeen;
""",
    )
    replace(
        chat_path,
        """    required this.onChanged,
    this.onContactSeen,
""",
        """    required this.onChanged,
    this.onDelete,
    this.onContactSeen,
""",
    )

    settings_block = r'''  Future<void> _leaveAndDeleteChat() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever_rounded,
          color: ChernogramColors.danger,
          size: 40,
        ),
        title: Text(
          widget.ru ? 'Выйти и удалить чат?' : 'Leave and delete chat?',
        ),
        content: Text(
          widget.ru
              ? 'История и все локальные файлы этого чата будут полностью удалены с телефона. У других участников останутся их копии.'
              : 'The history and all local files for this chat are permanently removed from this phone. Other participants keep their copies.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ChernogramColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Удалить полностью' : 'Delete permanently'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _session?.sendControl(<String, dynamic>{
      'operationId': CgIds.random(24),
      'action': 'member_left',
      'memberId': widget.profile.id,
      'memberName': widget.profile.nickname,
    });
    await widget.onDelete?.call(_tunnel);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showSettings() async {
    final name = TextEditingController(text: _tunnel.name);
    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    final fileCount = _tunnel.messages
        .where((message) => !message.deleted && message.attachment != null)
        .length;
    final created = _tunnel.createdAt.toLocal().toString();
    final createdLabel = created.length >= 16 ? created.substring(0, 16) : created;
    final secret = _tunnel.secret;
    final secretLabel = secret.length > 12
        ? '${secret.substring(0, 6)}…${secret.substring(secret.length - 4)}'
        : secret;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .90,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.ru ? 'Настройки чата' : 'Chat settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    readOnly: !_isOwner,
                    decoration: InputDecoration(
                      labelText: widget.ru ? 'Название чата' : 'Chat name',
                      suffixIcon: _isOwner
                          ? const Icon(Icons.edit_outlined)
                          : const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.fingerprint_rounded),
                          title: Text(widget.ru ? 'ID чата' : 'Chat ID'),
                          subtitle: SelectableText(_tunnel.id),
                        ),
                        ListTile(
                          leading: Icon(
                            isPrivate
                                ? Icons.lock_outline_rounded
                                : Icons.public_rounded,
                          ),
                          title: Text(widget.ru ? 'Тип' : 'Type'),
                          subtitle: Text(
                            isPrivate
                                ? (widget.ru ? 'Приватный' : 'Private')
                                : (widget.ru ? 'Открытый' : 'Open'),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.admin_panel_settings_outlined),
                          title: Text(widget.ru ? 'Ваша роль' : 'Your role'),
                          subtitle: Text(
                            _isOwner
                                ? (widget.ru ? 'Владелец' : 'Owner')
                                : (widget.ru ? 'Участник' : 'Member'),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.people_outline_rounded),
                          title: Text(widget.ru ? 'Сейчас онлайн' : 'Online now'),
                          trailing: Text('$_onlinePeers'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: Text(widget.ru ? 'Сообщений' : 'Messages'),
                          trailing: Text('${_tunnel.messages.length}'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.folder_copy_outlined),
                          title: Text(widget.ru ? 'Файлов и медиа' : 'Files and media'),
                          trailing: Text('$fileCount'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.calendar_today_outlined),
                          title: Text(widget.ru ? 'Создан' : 'Created'),
                          subtitle: Text(createdLabel),
                        ),
                        ListTile(
                          leading: const Icon(Icons.enhanced_encryption_outlined),
                          title: Text(widget.ru ? 'Шифрование' : 'Encryption'),
                          subtitle: const Text('AES-256-GCM'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: Text(widget.ru ? 'Ключ туннеля' : 'Tunnel key'),
                          subtitle: SelectableText(secretLabel),
                          trailing: Text('v${_tunnel.revision}'),
                        ),
                      ],
                    ),
                  ),
                  if (_isOwner) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: isPrivate,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        isPrivate
                            ? Icons.visibility_off_outlined
                            : Icons.public,
                      ),
                      title: Text(
                        isPrivate
                            ? (widget.ru ? 'Приватный чат' : 'Private chat')
                            : (widget.ru ? 'Открытый чат' : 'Open chat'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        isPrivate
                            ? (widget.ru
                                ? 'Вход только по секретной ссылке или QR.'
                                : 'Join only with the secret invite or QR.')
                            : (widget.ru
                                ? 'Ссылку можно свободно пересылать.'
                                : 'The invite may be freely forwarded.'),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => isPrivate = value),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: revoke,
                      onChanged: (value) =>
                          setSheetState(() => revoke = value ?? false),
                      title: Text(
                        widget.ru
                            ? 'Отозвать старую ссылку и QR'
                            : 'Revoke the old link and QR',
                      ),
                      subtitle: Text(
                        widget.ru
                            ? 'Подключённые участники автоматически получат новый ключ.'
                            : 'Connected members automatically receive the new key.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'save'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(widget.ru ? 'Сохранить изменения' : 'Save changes'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ChernogramColors.danger,
                        side: BorderSide(
                          color: ChernogramColors.danger.withValues(alpha: .45),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: Text(
                        widget.ru
                            ? 'Выйти и удалить чат полностью'
                            : 'Leave and delete chat permanently',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (action == 'save' && _isOwner) {
      final updated = _tunnel.copyWith(
        name: name.text.trim(),
        isPrivate: isPrivate,
        secret: revoke ? CgIds.random(42) : _tunnel.secret,
        revision: _tunnel.revision + 1,
      );
      name.dispose();
      await _applyOwnerUpdate(updated);
      return;
    }
    name.dispose();
    if (action == 'delete' && mounted) await _leaveAndDeleteChat();
  }

'''
    replace_between(
        chat_path,
        '  Future<void> _showSettings() async {',
        '  Future<void> _startCall(bool video) async {',
        settings_block,
    )

    replace(
        chat_path,
        """              if (_isOwner)
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(widget.ru ? 'Настройки' : 'Settings'),
                  ),
                ),
""",
        """              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: Text(
                    widget.ru ? 'Настройки чата' : 'Chat settings',
                  ),
                ),
              ),
""",
    )

    # Voice/audio and circular video messages sit directly on the chat
    # background instead of being wrapped in a second coloured cloud.
    replace(
        chat_path,
        """    final scheme = Theme.of(context).colorScheme;
    final attachment = message.attachment;
    return Align(
""",
        """    final scheme = Theme.of(context).colorScheme;
    final attachment = message.attachment;
    final transparentMedia = !message.deleted &&
        message.text.isEmpty &&
        attachment != null &&
        <String>{'voice', 'audio', 'circle'}.contains(attachment.kind);
    return Align(
""",
    )
    replace(
        chat_path,
        """          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: mine
                ? scheme.primary.withValues(alpha: .88)
                : scheme.surfaceContainerHighest.withValues(alpha: .88),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(19),
              topRight: const Radius.circular(19),
              bottomLeft: Radius.circular(mine ? 19 : 5),
              bottomRight: Radius.circular(mine ? 5 : 19),
            ),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: .06),
            ),
          ),
""",
        """          padding: transparentMedia
              ? EdgeInsets.zero
              : const EdgeInsets.all(11),
          decoration: transparentMedia
              ? null
              : BoxDecoration(
                  color: mine
                      ? scheme.primary.withValues(alpha: .88)
                      : scheme.surfaceContainerHighest.withValues(alpha: .88),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(19),
                    topRight: const Radius.circular(19),
                    bottomLeft: Radius.circular(mine ? 19 : 5),
                    bottomRight: Radius.circular(mine ? 5 : 19),
                  ),
                  border: Border.all(
                    color: scheme.onSurface.withValues(alpha: .06),
                  ),
                ),
""",
    )
    replace(
        chat_path,
        """                  color: mine
                      ? Colors.white60
                      : scheme.onSurface.withValues(alpha: .42),
""",
        """                  color: transparentMedia
                      ? scheme.onSurface.withValues(alpha: .46)
                      : mine
                          ? Colors.white60
                          : scheme.onSurface.withValues(alpha: .42),
""",
    )

    # Remove all local tunnel files when a user deletes the chat.
    media_path = 'lib/chat_media.dart'
    media_source = Path(media_path).read_text(encoding='utf-8')
    if 'static Future<void> purgeTunnelFiles' not in media_source:
        replace(
            media_path,
            """  static Future<List<CgTunnel>> purgeItem(
""",
            """  static Future<void> purgeTunnelFiles(CgTunnel tunnel) async {
    final ids = <String>{
      for (final message in tunnel.messages)
        if (message.attachment != null) message.attachment!.id,
    };
    if (ids.isEmpty) return;
    final root = await rootDirectory();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final matches = ids.any(
        (id) => name.startsWith('${_safeName(id)}_'),
      );
      if (!matches) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  static Future<List<CgTunnel>> purgeItem(
""",
        )

    # Root chat list owns deletion, persistence and relay shutdown.
    v07_path = 'lib/v07.dart'
    v07_source = Path(v07_path).read_text(encoding='utf-8')
    if "import 'internet_core.dart';" not in v07_source:
        replace(
            v07_path,
            "import 'core_models.dart';\n",
            "import 'core_models.dart';\nimport 'internet_core.dart';\n",
        )

    delete_method = r'''  Future<void> _deleteTunnel(CgTunnel tunnel) async {
    await CgMediaStore.purgeTunnelFiles(tunnel);
    await InternetRelay.close(tunnel.id);
    _tunnels = _tunnels.where((item) => item.id != tunnel.id).toList();
    await CgStore.saveTunnels(_tunnels);
    if (mounted) setState(() {});
    _syncMonitor();
  }

'''
    v07_source = Path(v07_path).read_text(encoding='utf-8')
    if 'Future<void> _deleteTunnel(CgTunnel tunnel)' not in v07_source:
        replace(
            v07_path,
            '  Future<void> _openTunnel(\n',
            delete_method + '  Future<void> _openTunnel(\n',
        )
    replace(
        v07_path,
        """          onChanged: _updateTunnel,
          onContactSeen: _rememberContact,
""",
        """          onChanged: _updateTunnel,
          onDelete: _deleteTunnel,
          onContactSeen: _rememberContact,
""",
    )

    # Requested home positioning text.
    replace(
        v07_path,
        """                ru
                    ? 'Сообщения, файлы и звонки между разными городами и сетями.'
                    : 'Messages, files and calls across cities and networks.',
""",
        """                ru
                    ? 'Сообщения, файлы и звонки без vpn'
                    : 'Messages, files and calls without VPN',
""",
    )

    # Correct system status/navigation bar contrast for both themes.
    replace(
        'lib/main.dart',
        """  Widget build(BuildContext context) {
    final ready = _ru != null;
    return MaterialApp(
""",
        """  Widget build(BuildContext context) {
    final ready = _ru != null;
    SystemChrome.setSystemUIOverlayStyle(
      _darkMode
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: ChernogramColors.background,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFFF2F6FF),
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarDividerColor: Color(0xFFDCE4F2),
            ),
    );
    return MaterialApp(
""",
    )

    print('Applied Chernogram 0.10.1 chat UX, settings, deletion and light system bars')


if __name__ == '__main__':
    main()
