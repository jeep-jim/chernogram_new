from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


path = Path('lib/light/light_chat_app.dart')
text = path.read_text(encoding='utf-8')

text = replace_once(
    text,
    "import 'light_theme.dart';\n",
    "import 'light_invite_qr.dart';\nimport 'light_theme.dart';\n",
    'invite qr import',
)

text = replace_once(
    text,
    """    final existing = _chats.indexWhere((chat) => chat.id == incoming.id);
    if (existing >= 0) {
      await _openChat(_chats[existing]);
      return;
    }
    setState(() {
      _chats.insert(0, incoming);
      _tab = 1;
    });
    await CgStore.saveTunnels(_chats);
    unawaited(_syncMonitor());
    if (mounted) await _openChat(incoming);
""",
    """    await _acceptIncomingChat(incoming);
""",
    'handle uri accept',
)

insert_anchor = """  Future<void> _dialAction(String action) async {
"""
insert_methods = """  Future<void> _showInviteQr(
    CgTunnel chat, {
    String? contactName,
  }) async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LightInviteQrScreen(
          chat: chat,
          inviteUrl: _inviteUrl(chat),
          onShare: () => _shareInvite(chat, contactName: contactName),
        ),
      ),
    );
  }

  Future<void> _acceptIncomingChat(CgTunnel incoming) async {
    final existing = _chats.indexWhere((chat) => chat.id == incoming.id);
    if (existing >= 0) {
      await _openChat(_chats[existing]);
      return;
    }
    if (!mounted) return;
    setState(() {
      _chats.insert(0, incoming);
      _tab = 1;
    });
    await CgStore.saveTunnels(_chats);
    unawaited(_syncMonitor());
    if (mounted) await _openChat(incoming);
  }

  Future<void> _scanInviteQr() async {
    if (!mounted) return;
    final incoming = await Navigator.push<CgTunnel>(
      context,
      MaterialPageRoute(builder: (_) => const LightInviteScannerScreen()),
    );
    if (incoming == null || !mounted) return;
    await _acceptIncomingChat(incoming);
  }

"""
text = replace_once(
    text,
    insert_anchor,
    insert_methods + insert_anchor,
    'qr methods insertion',
)

text = replace_once(
    text,
    """      await _shareInvite(chat);
      if (mounted) await _openChat(chat);
""",
    """      await _showInviteQr(chat);
      if (mounted) await _openChat(chat);
""",
    'manual invite qr',
)
text = replace_once(
    text,
    """    await _shareInvite(chat, contactName: selected.displayName);
    if (mounted) await _openChat(chat);
""",
    """    await _showInviteQr(chat, contactName: selected.displayName);
    if (mounted) await _openChat(chat);
""",
    'contact invite qr',
)

text = replace_once(
    text,
    """        onInvite: _newChat,
        onOpenChat: _openChat,
""",
    """        onInvite: _newChat,
        onScan: _scanInviteQr,
        onOpenChat: _openChat,
""",
    'contacts page onScan wiring',
)
text = replace_once(
    text,
    """        onCreate: _newChat,
        onDelete: _deleteChat,
""",
    """        onCreate: _newChat,
        onScan: _scanInviteQr,
        onDelete: _deleteChat,
""",
    'chats page onScan wiring',
)

text = replace_once(
    text,
    """  final Future<void> Function() onInvite;
  final Future<void> Function(CgTunnel chat, {String initialAction}) onOpenChat;
""",
    """  final Future<void> Function() onInvite;
  final Future<void> Function() onScan;
  final Future<void> Function(CgTunnel chat, {String initialAction}) onOpenChat;
""",
    'contacts onScan field',
)
text = replace_once(
    text,
    """    required this.onInvite,
    required this.onOpenChat,
""",
    """    required this.onInvite,
    required this.onScan,
    required this.onOpenChat,
""",
    'contacts onScan constructor',
)

text = replace_once(
    text,
    """              trailing: IconButton.filled(
                tooltip: 'Пригласить человека',
                onPressed: widget.onInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
""",
    """              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Сканировать QR',
                    onPressed: widget.onScan,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'Пригласить человека',
                    onPressed: widget.onInvite,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                ],
              ),
""",
    'contacts header actions',
)

text = replace_once(
    text,
    """                            'Выбери контакт телефона и отправь ему защищённую ссылку. После принятия появятся чат и звонки.',
""",
    """                            'Покажи QR или отправь защищённую ссылку. На втором телефоне можно сразу считать QR камерой Чернограма.',
""",
    'contacts invite explanation',
)

text = replace_once(
    text,
    """                    IconButton.filled(
                      onPressed: widget.onInvite,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
""",
    """                    IconButton.filledTonal(
                      tooltip: 'Сканировать QR',
                      onPressed: widget.onScan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Создать приглашение',
                      onPressed: widget.onInvite,
                      icon: const Icon(Icons.qr_code_2_rounded),
                    ),
""",
    'contacts invite card actions',
)

text = replace_once(
    text,
    """  final Future<void> Function() onCreate;
  final Future<void> Function(CgTunnel chat) onDelete;
""",
    """  final Future<void> Function() onCreate;
  final Future<void> Function() onScan;
  final Future<void> Function(CgTunnel chat) onDelete;
""",
    'chats onScan field',
)
text = replace_once(
    text,
    """    required this.onCreate,
    required this.onDelete,
""",
    """    required this.onCreate,
    required this.onScan,
    required this.onDelete,
""",
    'chats onScan constructor',
)

text = replace_once(
    text,
    """            trailing: IconButton.filled(
              tooltip: 'Новый чат',
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add_rounded),
            ),
""",
    """            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Сканировать QR',
                  onPressed: widget.onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Новый чат',
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
""",
    'chats header actions',
)

path.write_text(text, encoding='utf-8')
print('QR pairing added to contacts and chats.')
