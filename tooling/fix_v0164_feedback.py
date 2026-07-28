from pathlib import Path
import re


INSTALL_URL = (
    'https://github.com/jeep-jim/chernogram_new/'
    'releases/download/latest-apk/chernogram.apk'
)


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write_if_changed(path: str, source: str, original: str) -> bool:
    if source == original:
        return False
    Path(path).write_text(source, encoding='utf-8')
    print(f'Patched {path}')
    return True


def patch_main() -> bool:
    path = 'lib/main.dart'
    source = read(path)
    original = source

    old = """      systemNavigationBarColor: ChernogramColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),"""
    new = """      systemNavigationBarColor: ChernogramColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: ChernogramColors.background,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),"""
    if old in source and 'systemNavigationBarDividerColor' not in source[:2000]:
        source = source.replace(old, new, 1)

    old = """              systemNavigationBarColor: ChernogramColors.background,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,"""
    new = """              systemNavigationBarColor: ChernogramColors.background,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarDividerColor: ChernogramColors.background,
              systemNavigationBarContrastEnforced: false,"""
    if old in source:
        source = source.replace(old, new, 1)

    return write_if_changed(path, source, original)


def patch_android_styles() -> bool:
    changed = False
    for path in (
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
    ):
        source = read(path)
        original = source
        if 'android:enforceNavigationBarContrast' not in source:
            source = source.replace(
                '        <item name="android:navigationBarColor">#080808</item>\n',
                '        <item name="android:navigationBarColor">#080808</item>\n'
                '        <item name="android:navigationBarDividerColor">#080808</item>\n'
                '        <item name="android:enforceNavigationBarContrast">false</item>\n',
            )
        changed |= write_if_changed(path, source, original)
    return changed


def patch_call_service() -> bool:
    path = 'lib/call_service.dart'
    source = read(path)
    original = source

    old = """  Future<void> _hangUp() async {
    if (_ended) return;
    await _sendSignal(<String, dynamic>{'action': 'call_end'});
    _finish(_connectedAt == null ? 'cancelled' : 'completed');
  }
"""
    new = """  Future<void> _hangUp() async {
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
      try {
        await endSignal.timeout(const Duration(milliseconds: 700));
      } catch (_) {
        // The call screen is already closed. Network cleanup is best effort.
      }
    }
  }
"""
    if old in source:
        source = source.replace(old, new, 1)

    old = """    _ended = true;
    final duration = _connectedAt == null"""
    new = """    _ended = true;
    _durationTimer?.cancel();
    _inviteTimer?.cancel();
    _readyTimer?.cancel();
    _offerTimer?.cancel();
    _watchdog?.cancel();
    final duration = _connectedAt == null"""
    if old in source and '_watchdog?.cancel();\n    final duration' not in source:
        source = source.replace(old, new, 1)

    return write_if_changed(path, source, original)


def patch_chat_screen() -> bool:
    path = 'lib/chat_screen.dart'
    source = read(path)
    original = source

    if 'const String _androidInstallUrl' not in source:
        source = source.replace(
            """const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';
""",
            """const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';
const String _androidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';
""",
            1,
        )

    source = source.replace("'$_landingBase?v=15&invite=", "'$_landingBase?v=35&invite=")

    marker = """              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Открой чат в Чернограме: $_deepInvite\\n\\nЕсли приложение не открылось: $_inviteUrl'
                        : 'Open the Chernogram chat: $_deepInvite\\n\\nIf the app did not open: $_inviteUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(widget.ru ? 'Отправить ссылку' : 'Share invite'),
                ),
              ),
"""
    if 'Поделиться ссылкой на установку' not in source and marker in source:
        source = source.replace(
            marker,
            marker
            + """              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Установить Чернограм для Android:\\n$_androidInstallUrl'
                        : 'Install Chernogram for Android:\\n$_androidInstallUrl',
                  ),
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: Text(
                    widget.ru
                        ? 'Поделиться ссылкой на установку'
                        : 'Share installation link',
                  ),
                ),
              ),
""",
            1,
        )

    return write_if_changed(path, source, original)


def patch_v12() -> bool:
    path = 'lib/v12.dart'
    source = read(path)
    original = source

    if "import 'package:qr_flutter/qr_flutter.dart';" not in source:
        source = source.replace(
            "import 'package:package_info_plus/package_info_plus.dart';\n",
            "import 'package:package_info_plus/package_info_plus.dart';\n"
            "import 'package:qr_flutter/qr_flutter.dart';\n"
            "import 'package:share_plus/share_plus.dart';\n",
            1,
        )

    if 'const String _androidInstallUrl' not in source:
        source = source.replace(
            'String _encodeStoredJson(Object value) => jsonEncode(value);',
            "const String _androidInstallUrl =\n"
            "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';\n\n"
            'String _encodeStoredJson(Object value) => jsonEncode(value);',
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

    if 'void _refreshPresence([String? tunnelId])' not in source:
        marker = '  Future<void> _prewarmAll() async {\n'
        method = """  void _refreshPresence([String? tunnelId]) {
    var changed = false;
    if (tunnelId != null) {
      final session = InternetRelay.session(tunnelId);
      final online = session == null
          ? 0
          : session.members.where((member) => member['self'] != true).length;
      if (_onlineByTunnel[tunnelId] != online) {
        _onlineByTunnel[tunnelId] = online;
        changed = true;
      }
    }

    final activeTunnelIds = _tunnels.map((item) => item.id).toSet();
    for (final id in _onlineByTunnel.keys
        .where((id) => !activeTunnelIds.contains(id))
        .toList()) {
      _onlineByTunnel.remove(id);
      changed = true;
    }

    final onlineContactIds = <String>{};
    for (final tunnel in _tunnels) {
      final session = InternetRelay.session(tunnel.id);
      if (session == null) continue;
      for (final member in session.members) {
        if (member['self'] == true) continue;
        final id = member['id']?.toString() ?? '';
        if (id.isNotEmpty) onlineContactIds.add(id);
      }
    }
    final contactsChanged =
        onlineContactIds.length != _onlineContactIds.length ||
        !_onlineContactIds.containsAll(onlineContactIds);
    if (contactsChanged) {
      _onlineContactIds
        ..clear()
        ..addAll(onlineContactIds);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

"""
        source = source.replace(marker, method + marker, 1)

    old = """      _relaySubscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(tunnel.id, event)),
      );
"""
    new = old + '      _refreshPresence(tunnel.id);\n'
    if old in source and '_refreshPresence(tunnel.id);' not in source:
        source = source.replace(old, new, 1)

    old = """  ) async {
    if (event.type != 'message' || event.data['message'] is! Map) return;
"""
    new = """  ) async {
    if (event.type == 'presence' ||
        event.type == 'peer' ||
        event.type == 'status') {
      _refreshPresence(tunnelId);
    }
    if (event.type != 'message' || event.data['message'] is! Map) return;
"""
    if old in source:
        source = source.replace(old, new, 1)

    old = """    await InternetRelay.close(tunnel.id);
    await _saveTunnelsFast(_tunnels);
"""
    new = """    await InternetRelay.close(tunnel.id);
    _onlineByTunnel.remove(tunnel.id);
    _refreshPresence();
    await _saveTunnelsFast(_tunnels);
"""
    if old in source:
        source = source.replace(old, new, 1)

    if 'onlineByTunnel: _onlineByTunnel' not in source:
        source = source.replace(
            '        unreadCounts: _unreadCounts,\n        privacyLens: _privacyLens,',
            '        unreadCounts: _unreadCounts,\n'
            '        onlineByTunnel: _onlineByTunnel,\n'
            '        privacyLens: _privacyLens,',
            1,
        )
    if 'onlineContactIds: _onlineContactIds' not in source:
        source = source.replace(
            '        contacts: _contacts,\n        privacyLens: _privacyLens,',
            '        contacts: _contacts,\n'
            '        onlineContactIds: _onlineContactIds,\n'
            '        privacyLens: _privacyLens,',
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

    old_title = """                            Text(
                              privacyLens ? '••••••••' : tunnel.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
"""
    new_title = """                            Row(
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
                                    width: 7,
                                    height: 7,
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
    if old_title in source:
        source = source.replace(old_title, new_title, 1)

    contacts_at = source.find('class _V12ContactsScreen')
    profile_at = source.find('class _V12ProfileScreen', contacts_at)
    if contacts_at >= 0 and profile_at > contacts_at:
        before = source[:contacts_at]
        contacts = source[contacts_at:profile_at]
        after = source[profile_at:]
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
                '            Card(\n'
                '              margin: const EdgeInsets.only(bottom: 2),\n',
            )
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

    old_avatar = """class _V12ContactAvatar extends StatelessWidget {
  final CgContact contact;

  const _V12ContactAvatar({required this.contact});

  @override
  Widget build(BuildContext context) {
    if (contact.avatarBase64 != null) {
      try {
        return CircleAvatar(
          backgroundImage: MemoryImage(base64Decode(contact.avatarBase64!)),
        );
      } catch (_) {}
    }
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
"""
    new_avatar = """class _V12ContactAvatar extends StatelessWidget {
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
"""
    if old_avatar in source:
        source = source.replace(old_avatar, new_avatar, 1)

    if 'Future<void> _showBuildInfo() async' not in source:
        marker = """  Future<void> _pickAvatar() async {
"""
        method = """  Future<void> _showBuildInfo() async {
    if (!mounted) return;
    final notes = widget.ru
        ? <String>[
            'Убрана светлая полоса Android в тёмной теме.',
            'Отбой закрывает звонок мгновенно и не ждёт relay-сеть.',
            'В чатах показано число собеседников онлайн.',
            'В контактах добавлены точки «в сети» и точный отступ 2 пикселя.',
            'Добавлены QR и отправка постоянной ссылки установки Android.',
          ]
        : <String>[
            'Removed the light Android divider in dark mode.',
            'Hang up closes immediately without waiting for relay.',
            'Chats show the number of online peers.',
            'Contacts show online dots and use an exact 2-pixel gap.',
            'Added a QR code and permanent Android installation link.',
          ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Сборка Чернограма' : 'Chernogram build',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                _version,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(Icons.circle, size: 7, color: Color(0xFF22C7F2)),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text(note)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: QrImageView(data: _androidInstallUrl, size: 190),
              ),
              const SizedBox(height: 12),
              SelectableText(
                _androidInstallUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Установить Чернограм для Android:\\n$_androidInstallUrl'
                        : 'Install Chernogram for Android:\\n$_androidInstallUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(
                    widget.ru
                        ? 'Отправить ссылку на установку'
                        : 'Share installation link',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

"""
        source = source.replace(marker, method + marker, 1)

    old_version = """      if (_version.isNotEmpty)
        Center(
          child: Text(
            '${widget.ru ? 'Версия' : 'Version'} $_version',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .48),
            ),
          ),
        ),
"""
    new_version = """      if (_version.isNotEmpty)
        Center(
          child: InkWell(
            onTap: _showBuildInfo,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '${widget.ru ? 'Версия' : 'Version'} $_version',
                style: TextStyle(
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58),
                ),
              ),
            ),
          ),
        ),
"""
    if old_version in source:
        source = source.replace(old_version, new_version, 1)

    return write_if_changed(path, source, original)


def patch_metadata() -> bool:
    changed = False

    path = 'pubspec.yaml'
    source = read(path)
    original = source
    source = re.sub(r'^version:\s*0\.16\.3\+34\s*$', 'version: 0.16.4+35', source, count=1, flags=re.M)
    changed |= write_if_changed(path, source, original)

    path = 'docs/index.html'
    source = read(path)
    original = source
    source = source.replace('chernogram.apk?v=15', 'chernogram.apk?v=35')
    changed |= write_if_changed(path, source, original)

    path = 'roadmap.md'
    source = read(path)
    original = source
    if '`0.16.4+35`' not in source:
        source = source.rstrip() + (
            '\n- `0.16.4+35` — исправлены зависание Android при отбое и светлая системная полоса; '
            'добавлены онлайн-индикаторы, точный отступ 2 пикселя именно в контактах, '
            'описание сборки, QR и постоянная ссылка установки.\n'
        )
    changed |= write_if_changed(path, source, original)

    return changed


def main() -> None:
    changed = False
    changed |= patch_main()
    changed |= patch_android_styles()
    changed |= patch_call_service()
    changed |= patch_chat_screen()
    changed |= patch_v12()
    changed |= patch_metadata()
    print('Chernogram 0.16.4 feedback fixes applied' if changed else 'Chernogram 0.16.4 feedback fixes already applied')


if __name__ == '__main__':
    main()
