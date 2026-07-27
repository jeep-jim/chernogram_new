from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        if new in source:
            return source
        raise RuntimeError(f'Expected block was not found: {label}')
    return source.replace(old, new, 1)


def patch_core_models() -> bool:
    path = Path('lib/core_models.dart')
    source = path.read_text(encoding='utf-8')
    original = source
    source = source.replace("'пользователь_${CgIds.random(4).toLowerCase()}'", "'user_${CgIds.random(4).toLowerCase()}'")
    source = source.replace("json['nickname']?.toString() ?? 'пользователь'", "json['nickname']?.toString() ?? 'user'")
    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_v12() -> bool:
    path = Path('lib/v12.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    old_validation = """  if (RegExp(r'[a-z]', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Латиница в никнеймах запрещена. Используйте кириллицу.'
        : 'Latin letters are not allowed. Use Cyrillic.';
  }
  if (!RegExp(r'^[а-яё0-9_.-]+$', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Допустимы кириллица, цифры, точка, дефис и подчёркивание.'
        : 'Use Cyrillic, digits, dot, dash or underscore.';
  }
"""
    new_validation = """  if (RegExp(r'[а-яё]', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Кириллица в никнеймах запрещена. Используйте латиницу.'
        : 'Cyrillic letters are not allowed. Use Latin letters.';
  }
  if (!RegExp(r'^[a-z0-9_.-]+$', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Допустимы латинские буквы, цифры, точка, дефис и подчёркивание.'
        : 'Use Latin letters, digits, dot, dash or underscore.';
  }
"""
    source = replace_once(source, old_validation, new_validation, 'Latin nickname validation')

    direct_helpers = """
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
    class_marker = 'class ChernogramV12 extends StatefulWidget {'
    if '_directPairToken(String left, String right)' not in source:
        source = replace_once(source, class_marker, direct_helpers + class_marker, 'direct chat helpers')

    old_bootstrap = """    final prefs = await SharedPreferences.getInstance();
    final unread = <String, int>{};
"""
    new_bootstrap = """    var profile = values[0] as CgProfile;
    if (_nicknameError(profile.nickname, true) != null) {
      profile = profile.copyWith(
        nickname: 'user_${CgIds.random(4).toLowerCase()}',
      );
      await CgStore.saveProfile(profile);
    }
    final prefs = await SharedPreferences.getInstance();
    final unread = <String, int>{};
"""
    source = replace_once(source, old_bootstrap, new_bootstrap, 'profile nickname migration')
    source = replace_once(
        source,
        '      _profile = values[0] as CgProfile;',
        '      _profile = profile;',
        'bootstrap profile assignment',
    )

    old_background = """    final incoming = await CgMediaStore.cacheIncomingMessage(
      CgMessage.fromJson(raw),
    );
    if (!mounted) return;
"""
    new_background = """    final incoming = await CgMediaStore.cacheIncomingMessage(
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
"""
    source = replace_once(source, old_background, new_background, 'background contact persistence')

    old_contact_end = """    _saveContactsTimer = Timer(const Duration(milliseconds: 350), () {
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
"""
    new_contact_end = """    _saveContactsTimer = Timer(const Duration(milliseconds: 350), () {
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
"""
    source = replace_once(source, old_contact_end, new_contact_end, 'direct contact chat')

    old_visible_start = """  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
"""
    new_visible_start = """  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleTunnels = tunnels
        .where((tunnel) => !tunnel.id.startsWith('dm_') || tunnel.messages.isNotEmpty)
        .toList(growable: false);
    return ListView(
"""
    chats_class_index = source.find('class _V12ChatsHome extends StatelessWidget')
    if chats_class_index >= 0:
        prefix = source[:chats_class_index]
        suffix = source[chats_class_index:]
        suffix = replace_once(suffix, old_visible_start, new_visible_start, 'visible direct chats')
        suffix = suffix.replace("'${tunnels.length}'", "'${visibleTunnels.length}'", 1)
        suffix = suffix.replace('if (tunnels.isEmpty)', 'if (visibleTunnels.isEmpty)', 1)
        suffix = suffix.replace('for (final tunnel in tunnels)', 'for (final tunnel in visibleTunnels)', 1)
        source = prefix + suffix

    old_trailing = """                subtitle: Text(
                  privacyLens ? '••••••••' : _lastSeen(contact.lastSeenAt, ru),
                ),
                trailing: const Icon(Icons.chat_bubble_outline_rounded),
"""
    new_trailing = """                subtitle: Column(
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
"""
    source = replace_once(source, old_trailing, new_trailing, 'contact message button')

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_chat_screen() -> bool:
    path = Path('lib/chat_screen.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    old_reply_end = """  Map<String, dynamic> _replyMeta() {
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
    new_reply_end = old_reply_end + """  Map<String, dynamic> _messageMeta() => <String, dynamic>{
        ..._replyMeta(),
        if (widget.profile.avatarBase64?.isNotEmpty == true)
          'authorAvatarBase64': widget.profile.avatarBase64,
      };

"""
    if '_messageMeta()' not in source:
        source = replace_once(source, old_reply_end, new_reply_end, 'message avatar metadata')
    source = source.replace('meta: _replyMeta(),', 'meta: _messageMeta(),')

    old_message_contact = """          _rememberContact(
            raw['authorId']?.toString() ??
                event.data['relaySender']?.toString() ??
                '',
            raw['authorName']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
          );
"""
    new_message_contact = """          final rawMeta = raw['meta'];
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
"""
    source = replace_once(source, old_message_contact, new_message_contact, 'message contact avatar')

    old_history_contact = """          _rememberContact(
            raw['authorId']?.toString() ?? '',
            raw['authorName']?.toString() ??
                raw['author']?.toString() ??
                'user',
          );
"""
    new_history_contact = """          final rawMeta = raw['meta'];
          _rememberContact(
            raw['authorId']?.toString() ?? '',
            raw['authorName']?.toString() ??
                raw['author']?.toString() ??
                'user',
            avatarBase64: rawMeta is Map
                ? rawMeta['authorAvatarBase64']?.toString()
                : null,
          );
"""
    source = replace_once(source, old_history_contact, new_history_contact, 'history contact avatar')

    old_remember = """  void _rememberContact(String id, String name) {
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
"""
    new_remember = """  void _rememberContact(
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
"""
    source = replace_once(source, old_remember, new_remember, 'remember contact avatar')

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_windows_updater() -> bool:
    path = Path('lib/windows_update_service.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    old_launch = """      final executable = File(Platform.resolvedExecutable);
      final installDirectory = executable.parent.path;
      final executableName = executable.uri.pathSegments.last;
      final script = File(
        '${temp.path}${Platform.pathSeparator}chernogram-install-$safeVersion.ps1',
      );
      await script.writeAsString(_windowsInstallScript, flush: true);

      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-AppProcessId',
          pid.toString(),
          '-ZipPath',
          zipFile.path,
          '-InstallDir',
          installDirectory,
          '-ExeName',
          executableName,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 700));
      closeDialog();
      exit(0);
"""
    new_launch = """      final executable = File(Platform.resolvedExecutable);
      final installDirectory = executable.parent.path;
      final executableName = executable.uri.pathSegments.last;
      final script = File(
        '${temp.path}${Platform.pathSeparator}chernogram-install-$safeVersion.cmd',
      );
      final readyFile = File(
        '${temp.path}${Platform.pathSeparator}chernogram-install-$safeVersion.ready',
      );
      if (await readyFile.exists()) await readyFile.delete();
      await script.writeAsString(_windowsInstallScript, flush: true);

      await Process.start(
        'cmd.exe',
        <String>[
          '/d',
          '/s',
          '/c',
          'call',
          script.path,
          pid.toString(),
          zipFile.path,
          installDirectory,
          executableName,
          readyFile.path,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      var helperReady = false;
      for (var attempt = 0; attempt < 50; attempt++) {
        if (await readyFile.exists()) {
          helperReady = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!helperReady) {
        throw StateError('Windows updater helper did not start');
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
      closeDialog();
      exit(0);
"""
    source = replace_once(source, old_launch, new_launch, 'Windows updater launch')

    script_marker = "  static const String _windowsInstallScript = r'''"
    marker_index = source.find(script_marker)
    if marker_index < 0:
        raise RuntimeError('Windows updater script marker was not found')
    new_script = r'''  static const String _windowsInstallScript = r'''@echo off
setlocal EnableExtensions

set "APP_PID=%~1"
set "ZIP_PATH=%~2"
set "INSTALL_DIR=%~3"
set "EXE_NAME=%~4"
set "READY_PATH=%~5"
set "ORIGINAL_INSTALL=%INSTALL_DIR%"
set "LOG_PATH=%TEMP%\chernogram-update.log"
set "STAGE=%TEMP%\chernogram-stage-%RANDOM%-%RANDOM%"

> "%READY_PATH%" echo ready
> "%LOG_PATH%" echo [%DATE% %TIME%] Windows updater started for PID %APP_PID%

:wait_for_app
tasklist /FI "PID eq %APP_PID%" /NH 2>NUL | findstr /R /C:"[ ]%APP_PID%[ ]" >NUL
if not errorlevel 1 (
  ping 127.0.0.1 -n 2 >NUL
  goto wait_for_app
)
ping 127.0.0.1 -n 2 >NUL

if exist "%STAGE%" rmdir /S /Q "%STAGE%" >NUL 2>&1
mkdir "%STAGE%" >>"%LOG_PATH%" 2>&1
if errorlevel 1 goto fail

where tar.exe >NUL 2>&1
if errorlevel 1 goto fail

tar.exe -xf "%ZIP_PATH%" -C "%STAGE%" >>"%LOG_PATH%" 2>&1
if errorlevel 1 goto fail

set "SOURCE=%STAGE%"
if exist "%SOURCE%\%EXE_NAME%" goto source_ready
if exist "%STAGE%\app\%EXE_NAME%" set "SOURCE=%STAGE%\app"
if exist "%SOURCE%\%EXE_NAME%" goto source_ready
for /R "%STAGE%" %%F in (%EXE_NAME%) do set "SOURCE=%%~dpF"

:source_ready
if not exist "%SOURCE%\%EXE_NAME%" goto fail

for /L %%A in (1,1,30) do (
  robocopy "%SOURCE%" "%INSTALL_DIR%" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >>"%LOG_PATH%" 2>&1
  if errorlevel 8 (
    ping 127.0.0.1 -n 2 >NUL
  ) else (
    goto copied
  )
)
goto fail

:copied
if not exist "%INSTALL_DIR%\%EXE_NAME%" goto fail
del /Q "%ZIP_PATH%" >NUL 2>&1
rmdir /S /Q "%STAGE%" >NUL 2>&1
del /Q "%READY_PATH%" >NUL 2>&1
>>"%LOG_PATH%" echo [%DATE% %TIME%] Update completed
start "" /D "%INSTALL_DIR%" "%INSTALL_DIR%\%EXE_NAME%"
exit /B 0

:fail
>>"%LOG_PATH%" echo [%DATE% %TIME%] Update failed, restarting previous version
if exist "%ORIGINAL_INSTALL%\%EXE_NAME%" start "" /D "%ORIGINAL_INSTALL%" "%ORIGINAL_INSTALL%\%EXE_NAME%"
exit /B 1
''';
}
'''
    source = source[:marker_index] + new_script

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def main() -> None:
    changed = False
    changed |= patch_core_models()
    changed |= patch_v12()
    changed |= patch_chat_screen()
    changed |= patch_windows_updater()
    print('Applied Chernogram 0.15.1 release fixes' if changed else 'Chernogram 0.15.1 release fixes already applied')


if __name__ == '__main__':
    main()
