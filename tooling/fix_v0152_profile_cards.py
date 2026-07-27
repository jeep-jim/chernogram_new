from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old in source:
        return source.replace(old, new, 1)
    if new in source:
        return source
    raise RuntimeError(f'Expected block was not found: {label}')


def patch_chat_screen() -> bool:
    path = Path('lib/chat_screen.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    source = source.replace(
        """  Map<String, dynamic> _messageMeta() => <String, dynamic>{
        ..._replyMeta(),
        if (widget.profile.avatarBase64?.isNotEmpty == true)
          'authorAvatarBase64': widget.profile.avatarBase64,
      };

""",
        '',
    )
    source = source.replace('meta: _messageMeta(),', 'meta: _replyMeta(),')

    source = replace_once(
        source,
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
        """          _rememberContact(
            raw['authorId']?.toString() ??
                event.data['relaySender']?.toString() ??
                '',
            raw['authorName']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
          );
""",
        'message contact without repeated avatar',
    )

    source = replace_once(
        source,
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
        """          _rememberContact(
            raw['authorId']?.toString() ?? '',
            raw['authorName']?.toString() ??
                raw['author']?.toString() ??
                'user',
          );
""",
        'history contact without repeated avatar',
    )

    source = replace_once(
        source,
        """      _session = session;
      _subscription = session.events.listen(_onInternetEvent);
      setState(() {
""",
        """      _session = session;
      _subscription = session.events.listen(_onInternetEvent);
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': widget.profile.nickname,
          if (widget.profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': widget.profile.avatarBase64,
        }),
      );
      setState(() {
""",
        'send profile card from open chat',
    )

    source = replace_once(
        source,
        """    switch (action) {
      case 'message_delete':
""",
        """    switch (action) {
      case 'profile_card':
        _rememberContact(
          sender,
          data['nickname']?.toString() ??
              data['relaySenderName']?.toString() ??
              'user',
          avatarBase64: data['avatarBase64']?.toString(),
        );
        break;
      case 'message_delete':
""",
        'receive profile card in open chat',
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
        """  ) async {
    if (event.type != 'message' || event.data['message'] is! Map) return;
    final raw = Map<String, dynamic>.from(event.data['message'] as Map);
""",
        """  ) async {
    if (event.type == 'control' &&
        event.data['action']?.toString() == 'profile_card') {
      final contactId = event.data['relaySender']?.toString() ?? '';
      if (contactId.isNotEmpty && contactId != _profile?.id) {
        _rememberContact(
          CgContact(
            id: contactId,
            nickname: event.data['nickname']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
            lastSeenAt: DateTime.now(),
            tunnelIds: <String>[tunnelId],
            avatarBase64: event.data['avatarBase64']?.toString(),
          ),
        );
      }
      return;
    }
    if (event.type != 'message' || event.data['message'] is! Map) return;
    final raw = Map<String, dynamic>.from(event.data['message'] as Map);
""",
        'background profile card',
    )

    source = replace_once(
        source,
        """      _relaySubscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(tunnel.id, event)),
      );
""",
        """      _relaySubscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(tunnel.id, event)),
      );
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': profile.nickname,
          if (profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': profile.avatarBase64,
        }),
      );
""",
        'prewarm profile card',
    )

    source = replace_once(
        source,
        """      _relaySubscriptions[direct.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(direct.id, event)),
      );
""",
        """      _relaySubscriptions[direct.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(direct.id, event)),
      );
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': profile.nickname,
          if (profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': profile.avatarBase64,
        }),
      );
""",
        'direct profile card',
    )

    source = replace_once(
        source,
        """  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
  }
""",
        """  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
    for (final tunnel in _tunnels) {
      final session = InternetRelay.session(tunnel.id);
      if (session == null) continue;
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': profile.nickname,
          if (profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': profile.avatarBase64,
        }),
      );
    }
  }
""",
        'broadcast updated profile',
    )

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def apply_profile_card_fix() -> bool:
    return patch_chat_screen() | patch_v12()
