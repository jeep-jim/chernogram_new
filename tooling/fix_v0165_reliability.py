from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write_if_changed(path: str, source: str, original: str) -> bool:
    if source == original:
        return False
    Path(path).write_text(source, encoding='utf-8')
    print(f'Patched {path}')
    return True


def patch_app_monitor() -> bool:
    path = 'lib/app_monitor.dart'
    source = read(path)
    original = source

    if 'static final Set<String> _endedCalls' not in source:
        source = source.replace(
            "  static bool _dialogOpen = false;\n",
            "  static bool _dialogOpen = false;\n"
            "  static final Set<String> _endedCalls = <String>{};\n",
            1,
        )

    start = source.find('  static Future<void> _handleSignal(\n')
    end = source.find('  static void _appendLocalCallEvent({', start)
    if start >= 0 and end > start:
        replacement = r'''  static Future<void> _handleSignal(
    String tunnelId,
    Map<String, dynamic> signal,
  ) async {
    final action = signal['action']?.toString() ?? '';
    final callId = signal['callId']?.toString() ?? '';
    final profile = _profile;
    final tunnel = _tunnels[tunnelId];
    if (profile == null || tunnel == null || callId.isEmpty) return;

    final target = signal['target']?.toString() ?? '';
    if (target.isNotEmpty && target != profile.id) return;

    if (action == 'call_end' ||
        action == 'call_decline' ||
        action == 'group_leave') {
      _endedCalls.add(callId);
      if (_endedCalls.length > 500) _endedCalls.remove(_endedCalls.first);
      return;
    }
    if (action != 'call_invite' && action != 'group_call_invite') return;
    if (_endedCalls.contains(callId)) return;

    final signalAt = DateTime.tryParse(
      signal['receivedAt']?.toString() ?? signal['sentAt']?.toString() ?? '',
    );
    if (signalAt != null &&
        DateTime.now().toUtc().difference(signalAt.toUtc()).inSeconds > 25) {
      return;
    }

    final from = signal['from']?.toString() ??
        signal['relaySender']?.toString() ??
        '';
    if (from.isEmpty || from == profile.id || _dialogOpen) return;

    final context = chernogramNavigatorKey.currentContext;
    final navigator = chernogramNavigatorKey.currentState;
    if (context == null || navigator == null) return;
    if (!CgSignalRegistry.claim(callId)) return;

    final fromName = signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        (_ru ? 'Собеседник' : 'Peer');
    final video = signal['video'] == true;
    final group = action == 'group_call_invite';
    final callerAvatar = signal['avatarBase64']?.toString();
    _rememberContact(tunnelId, from, fromName);

    _dialogOpen = true;
    bool? accepted;
    try {
      await ChernogramSound.startIncomingCall(video: video);
      accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: CgCallAvatar(
            avatarBase64: callerAvatar,
            name: fromName,
            size: 78,
            fallbackIcon: group
                ? Icons.groups_2_rounded
                : video
                    ? Icons.videocam_rounded
                    : Icons.call_rounded,
          ),
          title: Text(
            group
                ? (video
                    ? (_ru ? 'Групповой видеозвонок' : 'Group video call')
                    : (_ru ? 'Групповой звонок' : 'Group call'))
                : (video
                    ? (_ru ? 'Видеозвонок' : 'Video call')
                    : (_ru ? 'Аудиозвонок' : 'Audio call')),
          ),
          content: Text(
            group
                ? (_ru
                    ? '$fromName приглашает в звонок до 6 участников.'
                    : '$fromName invites you to a call for up to 6 participants.')
                : (_ru ? '$fromName звонит вам' : '$fromName is calling you'),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: ChernogramColors.danger,
                shape: const CircleBorder(),
                fixedSize: const Size.square(54),
              ),
              onPressed: () => Navigator.pop(dialogContext, false),
              icon: const Icon(Icons.call_end_rounded),
            ),
            const SizedBox(width: 20),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: ChernogramColors.success,
                shape: const CircleBorder(),
                fixedSize: const Size.square(54),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.call_rounded),
            ),
          ],
        ),
      );
    } catch (_) {
      accepted = false;
    } finally {
      await ChernogramSound.stopIncomingCall();
      _dialogOpen = false;
    }

    final session = _sessions[tunnelId];
    if (accepted != true) {
      if (!group) {
        final decline = session?.sendSignal(<String, dynamic>{
          'action': 'call_decline',
          'callId': callId,
          'from': profile.id,
          'target': from,
        });
        if (decline != null) {
          unawaited(
            decline
                .timeout(const Duration(milliseconds: 800))
                .catchError((_) {}),
          );
        }
      }
      _appendLocalCallEvent(
        tunnelId: tunnelId,
        authorId: from,
        authorName: fromName,
        video: video,
        group: group,
        status: 'missed',
        durationSeconds: 0,
        participants: group ? 1 : 2,
      );
      return;
    }

    if (_endedCalls.contains(callId)) return;
    final outcome = await navigator.push<CgCallOutcome>(
      MaterialPageRoute<CgCallOutcome>(
        builder: (_) => group
            ? ChernogramGroupCallScreen(
                tunnelName: tunnel.displayName,
                tunnelId: tunnel.id,
                secret: tunnel.secret,
                profileId: profile.id,
                nickname: profile.nickname,
                callId: callId,
                isHost: false,
                video: video,
                ru: _ru,
                myAvatarBase64: profile.avatarBase64,
              )
            : ChernogramCallScreen(
                tunnelName: tunnel.displayName,
                tunnelId: tunnel.id,
                secret: tunnel.secret,
                profileId: profile.id,
                nickname: profile.nickname,
                peerId: from,
                peerName: fromName,
                peerAvatarBase64: callerAvatar,
                myAvatarBase64: profile.avatarBase64,
                callId: callId,
                isCaller: false,
                video: video,
                ru: _ru,
              ),
      ),
    );
    if (outcome != null) {
      _appendLocalCallEvent(
        tunnelId: tunnelId,
        authorId: from,
        authorName: fromName,
        video: video,
        group: group,
        status: outcome.status,
        durationSeconds: outcome.durationSeconds,
        participants: group ? 2 : 2,
      );
    }
  }

'''
        source = source[:start] + replacement + source[end:]

    return write_if_changed(path, source, original)


def patch_v12() -> bool:
    path = 'lib/v12.dart'
    source = read(path)
    original = source

    if "import 'app_monitor.dart';" not in source:
        source = source.replace(
            "import 'agent_screen.dart';\n",
            "import 'agent_screen.dart';\nimport 'app_monitor.dart';\n",
            1,
        )

    if 'Timer? _presenceRefreshTimer;' not in source:
        source = source.replace(
            '  Timer? _saveContactsTimer;\n',
            '  Timer? _saveContactsTimer;\n  Timer? _presenceRefreshTimer;\n',
            1,
        )

    if '_onlineByTunnel' not in source:
        source = source.replace(
            '  Map<String, int> _unreadCounts = <String, int>{};\n',
            '  Map<String, int> _unreadCounts = <String, int>{};\n'
            '  final Map<String, int> _onlineByTunnel = <String, int>{};\n'
            '  final Set<String> _onlineContactIds = <String>{};\n',
            1,
        )

    if 'Future<void> _syncAppMonitor() async' not in source:
        marker = '  Future<void> _prewarmAll() async {\n'
        methods = r'''  void _refreshAllPresence() {
    final nextByTunnel = <String, int>{};
    final nextContacts = <String>{};
    for (final tunnel in _tunnels) {
      final session = InternetRelay.session(tunnel.id);
      if (session == null) continue;
      final peers = session.members.where((member) => member['self'] != true);
      var count = 0;
      for (final member in peers) {
        final id = member['id']?.toString() ?? '';
        if (id.isEmpty || id == _profile?.id) continue;
        count++;
        nextContacts.add(id);
      }
      if (count > 0) nextByTunnel[tunnel.id] = count;
    }
    final tunnelChanged = nextByTunnel.length != _onlineByTunnel.length ||
        nextByTunnel.entries.any(
          (entry) => _onlineByTunnel[entry.key] != entry.value,
        );
    final contactsChanged = nextContacts.length != _onlineContactIds.length ||
        !_onlineContactIds.containsAll(nextContacts);
    if (!tunnelChanged && !contactsChanged) return;
    _onlineByTunnel
      ..clear()
      ..addAll(nextByTunnel);
    _onlineContactIds
      ..clear()
      ..addAll(nextContacts);
    if (mounted) setState(() {});
  }

  Future<void> _syncAppMonitor() async {
    final profile = _profile;
    if (profile == null) return;
    await ChernogramAppMonitor.sync(
      profile: profile,
      tunnels: _tunnels,
      ru: widget.ru,
      onTunnelChanged: _updateTunnel,
      onContactSeen: _rememberContact,
    );
    _refreshAllPresence();
  }

'''
        source = source.replace(marker, methods + marker, 1)

    bootstrap_marker = '    unawaited(_prewarmAll());\n'
    if bootstrap_marker in source and '_presenceRefreshTimer = Timer.periodic' not in source:
        source = source.replace(
            bootstrap_marker,
            bootstrap_marker
            + "    unawaited(_syncAppMonitor());\n"
            + "    _presenceRefreshTimer = Timer.periodic(\n"
            + "      const Duration(seconds: 3),\n"
            + "      (_) => _refreshAllPresence(),\n"
            + "    );\n",
            1,
        )

    listener = """      _relaySubscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(tunnel.id, event)),
      );
"""
    if listener in source and '      _refreshAllPresence();\n' not in source[source.find(listener):source.find(listener)+len(listener)+80]:
        source = source.replace(listener, listener + '      _refreshAllPresence();\n', 1)

    handle_marker = """  ) async {
    if (event.type != 'message' || event.data['message'] is! Map) return;
"""
    if handle_marker in source:
        source = source.replace(
            handle_marker,
            """  ) async {
    if (event.type == 'peer' ||
        event.type == 'presence' ||
        event.type == 'status') {
      _refreshAllPresence();
    }
    if (event.type != 'message' || event.data['message'] is! Map) return;
""",
            1,
        )

    page_chat = """        unreadCounts: _unreadCounts,
        privacyLens: _privacyLens,
"""
    if page_chat in source and 'onlineByTunnel: _onlineByTunnel' not in source[source.find(page_chat)-100:source.find(page_chat)+200]:
        source = source.replace(
            page_chat,
            """        unreadCounts: _unreadCounts,
        onlineByTunnel: _onlineByTunnel,
        privacyLens: _privacyLens,
""",
            1,
        )
    page_contacts = """        contacts: _contacts,
        privacyLens: _privacyLens,
"""
    if page_contacts in source and 'onlineContactIds: _onlineContactIds' not in source[source.find(page_contacts)-100:source.find(page_contacts)+200]:
        source = source.replace(
            page_contacts,
            """        contacts: _contacts,
        onlineContactIds: _onlineContactIds,
        privacyLens: _privacyLens,
""",
            1,
        )

    if 'final Map<String, int> onlineByTunnel;' not in source:
        source = source.replace(
            '  final Map<String, int> unreadCounts;\n  final bool privacyLens;',
            '  final Map<String, int> unreadCounts;\n'
            '  final Map<String, int> onlineByTunnel;\n'
            '  final bool privacyLens;',
            1,
        )
        source = source.replace(
            '    required this.unreadCounts,\n    required this.privacyLens,',
            '    required this.unreadCounts,\n'
            '    required this.onlineByTunnel,\n'
            '    required this.privacyLens,',
            1,
        )

    title_old = """                    Text(widget.privacyLens ? '••••••••' : tunnel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
"""
    title_new = """                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.privacyLens ? '••••••••' : tunnel.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if ((widget.onlineByTunnel[tunnel.id] ?? 0) > 0) ...<Widget>[
                          const SizedBox(width: 7),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C7F2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.onlineByTunnel[tunnel.id]}',
                            style: const TextStyle(
                              color: Color(0xFF22C7F2),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
"""
    if title_old in source:
        source = source.replace(title_old, title_new, 1)

    title_old2 = """                            Text(
                              privacyLens ? '••••••••' : tunnel.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
"""
    title_new2 = """                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    privacyLens ? '••••••••' : tunnel.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if ((onlineByTunnel[tunnel.id] ?? 0) > 0) ...[
                                  const SizedBox(width: 7),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C7F2),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${onlineByTunnel[tunnel.id]}',
                                    style: const TextStyle(
                                      color: Color(0xFF22C7F2),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            ),
"""
    if title_old2 in source:
        source = source.replace(title_old2, title_new2, 1)

    contacts_start = source.find('class _V12ContactsScreen')
    profile_start = source.find('class _V12ProfileScreen', contacts_start)
    if contacts_start >= 0 and profile_start > contacts_start:
        before = source[:contacts_start]
        contacts = source[contacts_start:profile_start]
        after = source[profile_start:]
        if 'final Set<String> onlineContactIds;' not in contacts:
            contacts = contacts.replace(
                '  final List<CgContact> contacts;\n  final bool privacyLens;',
                '  final List<CgContact> contacts;\n'
                '  final Set<String> onlineContactIds;\n'
                '  final bool privacyLens;',
                1,
            )
            contacts = contacts.replace(
                '    required this.contacts,\n    required this.privacyLens,',
                '    required this.contacts,\n'
                '    required this.onlineContactIds,\n'
                '    required this.privacyLens,',
                1,
            )
        if 'margin: const EdgeInsets.only(bottom: 2)' not in contacts:
            contacts = contacts.replace(
                '            Card(\n',
                '            Card(\n              margin: const EdgeInsets.only(bottom: 2),\n',
                1,
            )
        if 'online: onlineContactIds.contains(contact.id)' not in contacts:
            contacts = contacts.replace(
                '                leading: _V12ContactAvatar(contact: contact),',
                '                leading: _V12ContactAvatar(\n'
                '                  contact: contact,\n'
                '                  online: onlineContactIds.contains(contact.id),\n'
                '                ),',
                1,
            )
        contacts = contacts.replace(
            """                subtitle: Text(
                  privacyLens ? '••••••••' : _lastSeen(contact.lastSeenAt, ru),
                ),""",
            """                subtitle: Text(
                  privacyLens
                      ? '••••••••'
                      : onlineContactIds.contains(contact.id)
                          ? (ru ? 'в сети' : 'online')
                          : _lastSeen(contact.lastSeenAt, ru),
                ),""",
            1,
        )
        source = before + contacts + after

    avatar_start = source.find('class _V12ContactAvatar extends StatelessWidget')
    avatar_end = source.find('class _V12ProfileScreen', avatar_start)
    if avatar_start >= 0 and avatar_end > avatar_start:
        avatar = source[avatar_start:avatar_end]
        if 'final bool online;' not in avatar:
            match = re.search(r'class _V12ContactAvatar extends StatelessWidget \{.*?\n\}\n\n', avatar, re.S)
            if match:
                new_avatar = r'''class _V12ContactAvatar extends StatelessWidget {
  final CgContact contact;
  final bool online;

  const _V12ContactAvatar({required this.contact, required this.online});

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (contact.avatarBase64 != null) {
      try {
        avatar = CircleAvatar(
          backgroundImage: MemoryImage(base64Decode(contact.avatarBase64!)),
        );
      } catch (_) {
        avatar = _fallback(context);
      }
    } else {
      avatar = _fallback(context);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (online)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFF22C7F2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    final letter = contact.nickname.trim().isEmpty
        ? '?'
        : contact.nickname.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

'''
                avatar = avatar[:match.start()] + new_avatar + avatar[match.end():]
                source = source[:avatar_start] + avatar + source[avatar_end:]

    update_tail = """    _saveTunnelsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveTunnelsFast(snapshot));
    });
  }

  void _rememberContact"""
    if update_tail in source and 'unawaited(_syncAppMonitor());\n  }\n\n  void _rememberContact' not in source:
        source = source.replace(
            update_tail,
            """    _saveTunnelsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveTunnelsFast(snapshot));
    });
    unawaited(_syncAppMonitor());
    _refreshAllPresence();
  }

  void _rememberContact""",
            1,
        )

    save_profile_old = """  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
  }
"""
    save_profile_new = """  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
    unawaited(_prewarmAll());
    unawaited(_syncAppMonitor());
  }
"""
    if save_profile_old in source:
        source = source.replace(save_profile_old, save_profile_new, 1)

    if '_presenceRefreshTimer?.cancel();' not in source:
        source = source.replace(
            '    _saveContactsTimer?.cancel();\n',
            '    _saveContactsTimer?.cancel();\n'
            '    _presenceRefreshTimer?.cancel();\n'
            '    unawaited(ChernogramAppMonitor.stop());\n',
            1,
        )

    source = source.replace(
        "'Отбой закрывает звонок мгновенно и не ждёт relay-сеть.',",
        "'Входящий звонок теперь принимается на любом экране приложения.',\n"
        "            'Отбой и очистка WebRTC не блокируют интерфейс Android.',",
    )
    source = source.replace(
        "'Hang up closes immediately without waiting for relay.',",
        "'Incoming calls are now handled on every application screen.',\n"
        "            'Hang-up and WebRTC cleanup no longer block Android UI.',",
    )

    return write_if_changed(path, source, original)


def patch_chat_screen() -> bool:
    path = 'lib/chat_screen.dart'
    source = read(path)
    original = source

    source = source.replace('  int _onlinePeers = 1;', '  int _onlinePeers = 0;', 1)

    peer_pattern = re.compile(
        r"  String\? get _preferredPeerId \{.*?\n  \}\n\n  String\? get _preferredPeerName",
        re.S,
    )
    peer_match = peer_pattern.search(source)
    if peer_match:
        replacement = r'''  String? get _preferredPeerId {
    final session = _session;
    if (session != null) {
      for (final member in session.members) {
        if (member['self'] == true) continue;
        final id = member['id']?.toString() ?? '';
        if (id.isNotEmpty && id != widget.profile.id) return id;
      }
    }
    for (final message in _tunnel.messages.reversed) {
      final id = message.authorId.trim();
      if (id.isNotEmpty && id != widget.profile.id) return id;
    }
    return null;
  }

  String? get _preferredPeerName'''
        source = source[:peer_match.start()] + replacement + source[peer_match.end():]

    source = source.replace(
        '        _onlinePeers = session.onlinePeers;',
        '        _onlinePeers = (session.onlinePeers - 1).clamp(0, 999).toInt();',
        1,
    )
    source = source.replace(
        """          _onlinePeers =
              int.tryParse(event.data['peers']?.toString() ?? '') ?? 1;
""",
        """          final total =
              int.tryParse(event.data['peers']?.toString() ?? '') ?? 1;
          _onlinePeers = (total - 1).clamp(0, 999).toInt();
""",
        1,
    )

    handle_signal_old = """  void _handleSignal(Map<String, dynamic> signal) {
    final action = signal['action']?.toString() ?? '';
"""
    handle_signal_new = """  void _handleSignal(Map<String, dynamic> signal) {
    final target = signal['target']?.toString() ?? '';
    if (target.isNotEmpty && target != widget.profile.id) return;
    final signalAt = DateTime.tryParse(
      signal['receivedAt']?.toString() ?? signal['sentAt']?.toString() ?? '',
    );
    if (signalAt != null &&
        DateTime.now().toUtc().difference(signalAt.toUtc()).inSeconds > 25) {
      return;
    }
    final action = signal['action']?.toString() ?? '';
"""
    if handle_signal_old in source:
        source = source.replace(handle_signal_old, handle_signal_new, 1)

    status_old = """    if (_networkState == 'connected') {
      return widget.ru ? 'Онлайн • $_onlinePeers' : 'Online • $_onlinePeers';
    }
"""
    status_new = """    if (_networkState == 'connected') {
      if (_onlinePeers > 0) {
        return widget.ru ? 'В сети • $_onlinePeers' : 'Online • $_onlinePeers';
      }
      return widget.ru ? 'Ожидаем собеседника' : 'Waiting for peer';
    }
"""
    if status_old in source:
        source = source.replace(status_old, status_new, 1)

    return write_if_changed(path, source, original)


def patch_call_service() -> bool:
    path = 'lib/call_service.dart'
    source = read(path)
    original = source

    if 'int _prepareEpoch = 0;' not in source:
        source = source.replace(
            '  DateTime _lastRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);\n',
            '  DateTime _lastRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);\n'
            '  int _prepareEpoch = 0;\n',
            1,
        )

    if 'bool _prepareCancelled(int epoch)' not in source:
        source = source.replace(
            '  String get _profileId => widget.profileId ?? \'\';\n',
            "  String get _profileId => widget.profileId ?? '';\n\n"
            "  bool _prepareCancelled(int epoch) =>\n"
            "      _ended || !mounted || epoch != _prepareEpoch;\n",
            1,
        )

    source = source.replace(
        '  Future<void> _prepare() async {\n    try {',
        '  Future<void> _prepare() async {\n'
        '    final epoch = ++_prepareEpoch;\n'
        '    try {',
        1,
    )

    source = source.replace("'iceCandidatePoolSize': 8,", "'iceCandidatePoolSize': 2,", 1)

    media_marker = """      });

      final peer = await createPeerConnection(<String, dynamic>{
"""
    if media_marker in source and 'if (_prepareCancelled(epoch)) {\n        for (final track in stream.getTracks())' not in source:
        source = source.replace(
            media_marker,
            """      });
      if (_prepareCancelled(epoch)) {
        for (final track in stream.getTracks()) {
          try {
            track.stop();
          } catch (_) {}
        }
        await stream.dispose();
        return;
      }

      final peer = await createPeerConnection(<String, dynamic>{
""",
            1,
        )

    peer_marker = """      });

      peer.onIceCandidate = (candidate) {
"""
    if peer_marker in source and 'if (_prepareCancelled(epoch)) {\n        await peer.close();' not in source:
        source = source.replace(
            peer_marker,
            """      });
      if (_prepareCancelled(epoch)) {
        await peer.close();
        for (final track in stream.getTracks()) {
          try {
            track.stop();
          } catch (_) {}
        }
        await stream.dispose();
        return;
      }

      peer.onIceCandidate = (candidate) {
""",
            1,
        )

    source = source.replace(
        '    } catch (error) {\n      if (mounted) {',
        '    } catch (error) {\n      if (mounted && !_ended && epoch == _prepareEpoch) {',
        1,
    )

    recover_marker = """    if (widget.isCaller) {
      await _makeOffer(iceRestart: true);
    } else {
"""
    if recover_marker in source and 'await _peer?.restartIce();' not in source:
        source = source.replace(
            recover_marker,
            """    try {
      await _peer?.restartIce();
    } catch (_) {}
    if (widget.isCaller) {
      await _makeOffer(iceRestart: true);
    } else {
""",
            1,
        )

    hangup_pattern = re.compile(
        r"  Future<void> _hangUp\(\) async \{.*?\n  \}\n\n  void _finish",
        re.S,
    )
    hangup_match = hangup_pattern.search(source)
    if hangup_match:
        hangup = r'''  Future<void> _hangUp() async {
    if (_ended) return;
    final status = _connectedAt == null ? 'cancelled' : 'completed';
    final session = _session;
    final peerId = _peerId;
    Future<void>? endSignal;
    if (session != null) {
      endSignal = session.sendSignal(<String, dynamic>{
        'action': 'call_end',
        'callId': _callId,
        'from': _profileId,
        'video': widget.video,
        if (peerId != null && peerId.isNotEmpty) 'target': peerId,
      });
    }
    _finish(status);
    if (endSignal != null) {
      unawaited(
        endSignal
            .timeout(const Duration(milliseconds: 700))
            .catchError((_) {}),
      );
    }
  }

  void _finish'''
        source = source[:hangup_match.start()] + hangup + source[hangup_match.end():]

    finish_marker = """    _ended = true;
    final duration = _connectedAt == null
"""
    if finish_marker in source:
        source = source.replace(
            finish_marker,
            """    _ended = true;
    _prepareEpoch++;
    _durationTimer?.cancel();
    _inviteTimer?.cancel();
    _readyTimer?.cancel();
    _offerTimer?.cancel();
    _watchdog?.cancel();
    final duration = _connectedAt == null
""",
            1,
        )

    dispose_marker = """  void dispose() {
    _ended = true;
"""
    if dispose_marker in source and '_prepareEpoch++;\n    _durationTimer?.cancel();' not in source[source.find(dispose_marker):source.find(dispose_marker)+180]:
        source = source.replace(
            dispose_marker,
            """  void dispose() {
    _ended = true;
    _prepareEpoch++;
""",
            1,
        )

    source = source.replace(
        """    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
""",
        """    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
""",
        1,
    )

    return write_if_changed(path, source, original)


def patch_internet_core() -> bool:
    path = 'lib/internet_core.dart'
    source = read(path)
    original = source

    signal_marker = """          'relaySenderName': senderName,
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
"""
    if signal_marker in source and "'sentAt': envelope['sentAt']" not in source:
        source = source.replace(
            signal_marker,
            """          'relaySenderName': senderName,
          'sentAt': envelope['sentAt'],
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
""",
            1,
        )

    source = source.replace(
        "priority: kind == 'presence' ? 'min' : 'default',",
        "priority: 'default',",
    )
    source = source.replace(
        'Timer.periodic(const Duration(seconds: 35)',
        'Timer.periodic(const Duration(seconds: 8)',
        1,
    )
    source = source.replace(
        'Timer.periodic(const Duration(seconds: 25)',
        'Timer.periodic(const Duration(seconds: 8)',
        1,
    )
    source = source.replace(
        'DateTime.now().subtract(const Duration(seconds: 100))',
        'DateTime.now().subtract(const Duration(seconds: 28))',
        1,
    )

    return write_if_changed(path, source, original)


def patch_background_service() -> bool:
    path = 'lib/background_realtime_service.dart'
    source = read(path)
    original = source

    call_profile_marker = """    final currentProfile = profile;
    if (currentProfile == null || await appIsForeground()) return;
    final action = signal['action']?.toString() ?? '';
"""
    if call_profile_marker in source:
        source = source.replace(
            call_profile_marker,
            """    final currentProfile = profile;
    if (currentProfile == null || await appIsForeground()) return;
    final target = signal['target']?.toString() ?? '';
    if (target.isNotEmpty && target != currentProfile.id) return;
    final signalAt = DateTime.tryParse(
      signal['receivedAt']?.toString() ?? signal['sentAt']?.toString() ?? '',
    );
    if (signalAt != null &&
        DateTime.now().toUtc().difference(signalAt.toUtc()).inSeconds > 25) {
      return;
    }
    final action = signal['action']?.toString() ?? '';
""",
            1,
        )

    listener_old = """      subscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(handleEvent(tunnel.id, tunnel, event)),
      );
"""
    listener_new = """      subscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(
          handleEvent(tunnel.id, tunnel, event).catchError((_) {}),
        ),
      );
"""
    if listener_old in source:
        source = source.replace(listener_old, listener_new, 1)

    timer_old = "  Timer.periodic(const Duration(seconds: 20), (_) => unawaited(syncSessions()));\n"
    timer_new = """  Timer.periodic(const Duration(seconds: 20), (_) {
    unawaited(syncSessions().catchError((_) {}));
  });
"""
    if timer_old in source:
        source = source.replace(timer_old, timer_new, 1)

    return write_if_changed(path, source, original)


def patch_metadata() -> bool:
    changed = False

    path = 'pubspec.yaml'
    source = read(path)
    original = source
    source = re.sub(
        r'^version:\s*0\.16\.[0-9]+\+[0-9]+\s*$',
        'version: 0.16.5+36',
        source,
        count=1,
        flags=re.M,
    )
    changed |= write_if_changed(path, source, original)

    path = 'docs/index.html'
    source = read(path)
    original = source
    source = re.sub(r'chernogram\.apk\?v=\d+', 'chernogram.apk?v=36', source)
    changed |= write_if_changed(path, source, original)

    path = 'roadmap.md'
    source = read(path)
    original = source
    if '`0.16.5+36`' not in source:
        source = source.rstrip() + (
            '\n- `0.16.5+36` — восстановлены входящие аудио- и видеозвонки на любом экране; '
            'ускорено реальное присутствие в чатах и контактах; добавлена защита Android от гонок '
            'при закрытии WebRTC и стандартный ICE restart.\n'
        )
    changed |= write_if_changed(path, source, original)

    return changed


def main() -> None:
    changed = False
    changed |= patch_app_monitor()
    changed |= patch_v12()
    changed |= patch_chat_screen()
    changed |= patch_call_service()
    changed |= patch_internet_core()
    changed |= patch_background_service()
    changed |= patch_metadata()
    print(
        'Chernogram 0.16.5 call and presence reliability fixes applied'
        if changed
        else 'Chernogram 0.16.5 reliability fixes already applied'
    )


if __name__ == '__main__':
    main()
