from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old in source:
        return source.replace(old, new, 1)
    if new in source:
        return source
    raise RuntimeError(f'Expected block was not found: {label}')


def patch_core_models() -> bool:
    path = Path('lib/core_models.dart')
    source = path.read_text(encoding='utf-8')
    original = source
    source = source.replace(
        "'пользователь_${CgIds.random(4).toLowerCase()}'",
        "'user_${CgIds.random(4).toLowerCase()}'",
    )
    source = source.replace(
        "json['nickname']?.toString() ?? 'пользователь'",
        "json['nickname']?.toString() ?? 'user'",
    )
    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_v12() -> bool:
    path = Path('lib/v12.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    source = replace_once(
        source,
        """  if (RegExp(r'[a-z]', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Латиница в никнеймах запрещена. Используйте кириллицу.'
        : 'Latin letters are not allowed. Use Cyrillic.';
  }
  if (!RegExp(r'^[а-яё0-9_.-]+$', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Допустимы кириллица, цифры, точка, дефис и подчёркивание.'
        : 'Use Cyrillic, digits, dot, dash or underscore.';
  }
""",
        """  if (RegExp(r'[а-яё]', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Кириллица в никнеймах запрещена. Используйте латиницу.'
        : 'Cyrillic letters are not allowed. Use Latin letters.';
  }
  if (!RegExp(r'^[a-z0-9_.-]+$', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Допустимы латинские буквы, цифры, точка, дефис и подчёркивание.'
        : 'Use Latin letters, digits, dot, dash or underscore.';
  }
""",
        'nickname alphabet validation',
    )

    helpers = """
String _directPairToken(String left, String right) {
  final ids = <String>[left, right]..sort();
  return base64Url
      .encode(utf8.encode('direct-v1:${ids[0]}:${ids[1]}'))
      .replaceAll('=', '');
}

String _directTunnelId(String left, String right) =>
    'dm_${_directPairToken(left, right)}';

String _directTunnelSecret(String left, String right) =>
    'dm-secret-${_directPairToken(left, right)}';

"""
    marker = 'class ChernogramV12 extends StatefulWidget {'
    if '_directPairToken(String left, String right)' not in source:
        source = replace_once(source, marker, helpers + marker, 'direct helpers')

    source = replace_once(
        source,
        """    final prefs = await SharedPreferences.getInstance();
    final unread = <String, int>{};
""",
        """    var profile = values[0] as CgProfile;
    if (_nicknameError(profile.nickname, true) != null) {
      profile = profile.copyWith(
        nickname: 'user_${CgIds.random(4).toLowerCase()}',
      );
      await CgStore.saveProfile(profile);
    }
    final prefs = await SharedPreferences.getInstance();
    final unread = <String, int>{};
""",
        'profile migration',
    )
    source = replace_once(
        source,
        '      _profile = values[0] as CgProfile;',
        '      _profile = profile;',
        'profile assignment',
    )

    source = replace_once(
        source,
        """    final incoming = await CgMediaStore.cacheIncomingMessage(
      CgMessage.fromJson(raw),
    );
    if (!mounted) return;
""",
        """    final incoming = await CgMediaStore.cacheIncomingMessage(
      CgMessage.fromJson(raw),
    );
    if (incoming.authorId.isNotEmpty && incoming.authorId != _profile?.id) {
      _rememberContact(
        CgContact(
          id: incoming.authorId,
          nickname: incoming.authorName.trim().isEmpty ? 'user' : incoming.authorName,
          lastSeenAt: DateTime.now(),
          tunnelIds: <String>[tunnelId],
          avatarBase64: incoming.meta['authorAvatarBase64']?.toString(),
        ),
      );
    }
    if (!mounted) return;
""",
        'background contact persistence',
    )

    source = replace_once(
        source,
        """    _saveContactsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveContactsFast(snapshot));
    });
  }

  Future<void> _openContact(CgContact contact) async {
    for (final tunnelId in contact.tunnelIds) {
      final index = _tunnels.indexWhere((item) => item.id == tunnelId);
      if (index >= 0) {
        await _openTunnel(_tunnels[index]);
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'Чат с этим контактом пока не найден.'
              : 'No chat was found for this contact.',
        ),
      ),
    );
  }
""",
        """    _saveContactsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveContactsFast(snapshot));
    });
    unawaited(_ensureDirectTunnel(incoming));
  }

  Future<CgTunnel> _ensureDirectTunnel(CgContact contact) async {
    final profile = _profile;
    if (profile == null) {
      throw StateError('Profile is not loaded');
    }
    final directId = _directTunnelId(profile.id, contact.id);
    final existingIndex = _tunnels.indexWhere((item) => item.id == directId);
    CgTunnel direct;
    var changed = false;
    if (existingIndex >= 0) {
      final existing = _tunnels[existingIndex];
      direct = existing.copyWith(
        name: contact.nickname,
        avatarBase64: contact.avatarBase64,
      );
      if (direct.name != existing.name ||
          direct.avatarBase64 != existing.avatarBase64) {
        final copy = <CgTunnel>[..._tunnels];
        copy[existingIndex] = direct;
        _tunnels = copy;
        changed = true;
      }
    } else {
      direct = CgTunnel(
        id: directId,
        name: contact.nickname,
        isPrivate: true,
        ownerId: '',
        secret: _directTunnelSecret(profile.id, contact.id),
        createdAt: DateTime.now(),
        avatarBase64: contact.avatarBase64,
        messages: const <CgMessage>[],
      );
      _tunnels = <CgTunnel>[direct, ..._tunnels];
      changed = true;
    }
    if (changed) {
      await _saveTunnelsFast(_tunnels);
      if (mounted) setState(() {});
    }
    if (!_relaySubscriptions.containsKey(direct.id)) {
      final session = await InternetRelay.open(
        tunnelId: direct.id,
        secret: direct.secret,
        profileId: profile.id,
        nickname: profile.nickname,
        history: direct.historyJson(),
      );
      _relaySubscriptions[direct.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(direct.id, event)),
      );
    }
    return direct;
  }

  Future<void> _openContact(CgContact contact) async {
    final direct = await _ensureDirectTunnel(contact);
    if (!mounted) return;
    await _openTunnel(direct);
  }
""",
        'direct contact chat',
    )

    chats_at = source.find('class _V12ChatsHome extends StatelessWidget')
    if chats_at < 0:
        raise RuntimeError('Chats home class not found')
    before = source[:chats_at]
    chats = source[chats_at:]
    chats = replace_once(
        chats,
        """  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
""",
        """  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleTunnels = tunnels
        .where((tunnel) => !tunnel.id.startsWith('dm_') || tunnel.messages.isNotEmpty)
        .toList(growable: false);
    return ListView(
""",
        'hide empty direct chats',
    )
    chats = chats.replace("'${tunnels.length}'", "'${visibleTunnels.length}'", 1)
    chats = chats.replace('if (tunnels.isEmpty)', 'if (visibleTunnels.isEmpty)', 1)
    chats = chats.replace('for (final tunnel in tunnels)', 'for (final tunnel in visibleTunnels)', 1)
    source = before + chats

    source = replace_once(
        source,
        """                subtitle: Text(
                  privacyLens ? '••••••••' : _lastSeen(contact.lastSeenAt, ru),
                ),
                trailing: const Icon(Icons.chat_bubble_outline_rounded),
""",
        """                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      privacyLens ? '••••••••' : _lastSeen(contact.lastSeenAt, ru),
                    ),
                    if (!privacyLens)
                      Text(
                        'ID ${contact.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurface.withValues(alpha: .42),
                        ),
                      ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: ru ? 'Личное сообщение' : 'Private message',
                  onPressed: () => onOpen(contact),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
""",
        'contact action button',
    )

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_chat_screen() -> bool:
    path = Path('lib/chat_screen.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    reply_block = """  Map<String, dynamic> _replyMeta() {
    final reply = _replyingTo;
    if (reply == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'replyToId': reply.id,
      'replyAuthor': reply.authorName,
      'replyText': reply.text,
      'replyAttachmentName': reply.attachment?.name,
    };
  }

"""
    if '_messageMeta()' not in source:
        source = replace_once(
            source,
            reply_block,
            reply_block + """  Map<String, dynamic> _messageMeta() => <String, dynamic>{
        ..._replyMeta(),
        if (widget.profile.avatarBase64?.isNotEmpty == true)
          'authorAvatarBase64': widget.profile.avatarBase64,
      };

""",
            'message profile metadata',
        )
    source = source.replace('meta: _replyMeta(),', 'meta: _messageMeta(),')

    source = replace_once(
        source,
        """          _rememberContact(
            raw['authorId']?.toString() ??
                event.data['relaySender']?.toString() ??
                '',
            raw['authorName']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
          );
""",
        """          final rawMeta = raw['meta'];
          _rememberContact(
            raw['authorId']?.toString() ??
                event.data['relaySender']?.toString() ??
                '',
            raw['authorName']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
            avatarBase64: rawMeta is Map
                ? rawMeta['authorAvatarBase64']?.toString()
                : null,
          );
""",
        'message contact avatar',
    )

    source = replace_once(
        source,
        """          _rememberContact(
            raw['authorId']?.toString() ?? '',
            raw['authorName']?.toString() ??
                raw['author']?.toString() ??
                'user',
          );
""",
        """          final rawMeta = raw['meta'];
          _rememberContact(
            raw['authorId']?.toString() ?? '',
            raw['authorName']?.toString() ??
                raw['author']?.toString() ??
                'user',
            avatarBase64: rawMeta is Map
                ? rawMeta['authorAvatarBase64']?.toString()
                : null,
          );
""",
        'history contact avatar',
    )

    source = replace_once(
        source,
        """  void _rememberContact(String id, String name) {
    if (id.isEmpty || id == widget.profile.id) return;
    widget.onContactSeen?.call(
      CgContact(
        id: id,
        nickname: name.trim().isEmpty ? 'user' : name,
        lastSeenAt: DateTime.now(),
        tunnelIds: [_tunnel.id],
      ),
    );
  }
""",
        """  void _rememberContact(
    String id,
    String name, {
    String? avatarBase64,
  }) {
    if (id.isEmpty || id == widget.profile.id) return;
    widget.onContactSeen?.call(
      CgContact(
        id: id,
        nickname: name.trim().isEmpty ? 'user' : name,
        lastSeenAt: DateTime.now(),
        tunnelIds: [_tunnel.id],
        avatarBase64: avatarBase64,
      ),
    );
  }
""",
        'contact avatar storage',
    )

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def apply_feature_fixes() -> bool:
    changed = False
    changed |= patch_core_models()
    changed |= patch_v12()
    changed |= patch_chat_screen()
    return changed
