from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:220]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_block_after(path: str, anchor: str, start: str, end: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    anchor_at = text.find(anchor)
    if anchor_at < 0:
        raise SystemExit(f'Anchor not found in {path}: {anchor!r}')
    start_at = text.find(start, anchor_at)
    if start_at < 0:
        raise SystemExit(f'Start not found in {path}: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End not found in {path}: {end!r}')
    file.write_text(text[:start_at] + new + text[end_at:], encoding='utf-8')


def remove_install_qr(path: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    title = "                  const Text(\n                    'QR для установки',"
    pos = text.find(title)
    if pos < 0:
        raise SystemExit('Profile installation QR block not found')
    start = text.rfind('          Padding(\n', 0, pos)
    next_marker = (
        '          Padding(\n'
        '            padding: const EdgeInsets.symmetric(horizontal: 14),\n'
        '            child: LightGlass(\n'
    )
    end = text.find(next_marker, pos)
    if start < 0 or end < 0:
        raise SystemExit('Unable to isolate profile installation QR block')
    file.write_text(text[:start] + text[end:], encoding='utf-8')


# 0.84 is deliberately a UI/local-data release. Do not touch the working
# InternetRelay, MQTT route selection or WebRTC route logic from 0.83.
replace_once('pubspec.yaml', 'version: 0.83.0+83', 'version: 0.84.0+84')
replace_once(
    'pubspec.yaml',
    '  path_provider: ^2.1.5\n',
    '  path_provider: ^2.1.5\n  permission_handler: ^12.0.1\n',
)

# ---------------------------------------------------------------------------
# Full home/profile UI + responsive desktop navigation.
# ---------------------------------------------------------------------------
replace_once(
    'lib/light/light_chat_app.dart',
    "import 'dart:convert';\n",
    "import 'dart:convert';\nimport 'dart:io';\n",
)
replace_once(
    'lib/light/light_chat_app.dart',
    "import '../brand.dart';\n",
    "import '../brand.dart';\n"
    "import '../chat_media.dart';\n"
    "import '../client_settings.dart';\n"
    "import '../device_product_panels.dart';\n"
    "import '../legacy_v16_features.dart';\n",
)

# The installation QR is useful only when explicitly requested. Remove the
# large always-visible profile card; the share-install sheet still contains it.
remove_install_qr('lib/light/light_chat_app.dart')

replace_once(
    'lib/light/light_chat_app.dart',
    '''      _ProfilePage(
        profile: _profile!,
        packageInfo: _packageInfo,
        darkMode: widget.darkMode,
        onPhoto: _changeProfilePhoto,
        onName: _changeProfileName,
        onTheme: widget.onToggleTheme,
        onShareInstall: () => Share.share(
          'Установить Чернограм: $_androidInstallUrl',
          subject: 'Чернограм',
        ),
        onUpdate: widget.onCheckUpdates,
      ),
''',
    '''      _ProfilePage(
        profile: _profile!,
        tunnels: _chats,
        onTunnelsChanged: (value) {
          if (!mounted) return;
          setState(() {
            _chats = <CgTunnel>[...value];
            _sortChats();
          });
          unawaited(CgStore.saveTunnels(_chats));
          unawaited(_syncMonitor());
        },
        packageInfo: _packageInfo,
        darkMode: widget.darkMode,
        onPhoto: _changeProfilePhoto,
        onName: _changeProfileName,
        onTheme: widget.onToggleTheme,
        onShareInstall: () => showChernogramInstallShare(context, ru: true),
        onUpdate: widget.onCheckUpdates,
      ),
''',
)

# Replace the mobile-only bottom navigation with a responsive desktop shell.
desktop_shell = r'''    final desktop =
        Platform.isWindows && MediaQuery.sizeOf(context).width >= 820;
    if (desktop) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 226,
                  child: LightGlass(
                    borderRadius: BorderRadius.circular(30),
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                          child: Row(
                            children: [
                              const ChernogramLogo(size: 48),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ЧЕРНОГРАМ',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: .5,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'на связи',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _DesktopNavItem(
                          selected: _tab == 0,
                          icon: Icons.chat_bubble_outline_rounded,
                          selectedIcon: Icons.chat_bubble_rounded,
                          title: 'Комнаты',
                          subtitle: '${_chats.length} диалогов',
                          onTap: () => setState(() => _tab = 0),
                        ),
                        const SizedBox(height: 7),
                        _DesktopNavItem(
                          selected: _tab == 1,
                          icon: Icons.person_outline_rounded,
                          selectedIcon: Icons.person_rounded,
                          title: 'Профиль',
                          subtitle: 'Файлы и настройки',
                          onTap: () => setState(() => _tab = 1),
                        ),
                        const Spacer(),
                        Divider(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .09),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          leading: ChernogramAvatar(
                            size: 42,
                            seed: _profile!.id,
                            avatarBase64: _profile!.avatarBase64,
                          ),
                          title: Text(
                            _profile!.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: const Text(
                            'обновления внутри приложения',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10),
                          ),
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: IndexedStack(index: _tab, children: pages),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: LightGlass(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Комнаты',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Профиль',
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
replace_block_after(
    'lib/light/light_chat_app.dart',
    '    final pages = <Widget>[',
    '    return Scaffold(',
    '  @override\n  void dispose() {',
    desktop_shell,
)

# Desktop nav widget.
replace_once(
    'lib/light/light_chat_app.dart',
    'class _PageHeader extends StatelessWidget {\n',
    r'''class _DesktopNavItem extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: .16)
                      : scheme.surfaceContainerHighest.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurface.withValues(alpha: .52),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
''',
)

# Full profile fields.
replace_once(
    'lib/light/light_chat_app.dart',
    '''class _ProfilePage extends StatelessWidget {
  final CgProfile profile;
  final PackageInfo? packageInfo;
''',
    '''class _ProfilePage extends StatelessWidget {
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final ValueChanged<List<CgTunnel>> onTunnelsChanged;
  final PackageInfo? packageInfo;
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''  const _ProfilePage({
    required this.profile,
    required this.packageInfo,
''',
    '''  const _ProfilePage({
    required this.profile,
    required this.tunnels,
    required this.onTunnelsChanged,
    required this.packageInfo,
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    "            subtitle: 'Только основные настройки',\n",
    "            subtitle: 'Файлы, устройство, приватность и обновления',\n",
)

# Storage card before the settings list.
profile_settings_marker = (
    '          Padding(\n'
    '            padding: const EdgeInsets.symmetric(horizontal: 14),\n'
    '            child: LightGlass(\n'
)
replace_block_after(
    'lib/light/light_chat_app.dart',
    'class _ProfilePage extends StatelessWidget {',
    profile_settings_marker,
    profile_settings_marker,
    '''          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: CgDeviceStorageCard(ru: true),
          ),
          const SizedBox(height: 12),
''' + profile_settings_marker,
)

# Add the restored local feature/settings screens before the installation tile.
install_tile = r'''                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.install_mobile_rounded),
'''
restored_tiles = r'''                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.folder_copy_outlined),
                    title: const Text(
                      'Файлы и медиа',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Все локальные вложения, память устройства и плеер',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CgMediaLibraryScreen(
                          ru: true,
                          tunnels: tunnels,
                          onTunnelsChanged: onTunnelsChanged,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text(
                      'Приватность',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Кто может звонить, приглашать и видеть активность',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CgV16PrivacyScreen(ru: true),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.tune_rounded),
                    title: const Text(
                      'Разрешения приложения',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Сообщения, уведомления, микрофон, камера и файлы',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CgV16PermissionsScreen(ru: true),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text(
                      'Всегда на связи',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Фоновое соединение и входящие уведомления',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showBackgroundConnectionSettings(
                      context,
                      ru: true,
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.devices_rounded),
                    title: const Text(
                      'Устройства и сессии',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Это устройство и локальная история сессий',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CgV16SessionsScreen(
                          ru: true,
                          profile: profile,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.phonelink_lock_rounded),
                    title: const Text(
                      'Аккаунт и устройство',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('ID и локальный отпечаток устройства'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDeviceAccountSheet(
                      context,
                      ru: true,
                      profile: profile,
                    ),
                  ),
                  Divider(
                    height: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .08),
                  ),
'''
replace_once(
    'lib/light/light_chat_app.dart',
    install_tile,
    restored_tiles + install_tile,
)
replace_once(
    'lib/light/light_chat_app.dart',
    "                    subtitle: const Text('Проверить новую версию онлайн'),\n",
    "                    subtitle: const Text('Скачать и установить внутри приложения'),\n",
)

# Installation sheet points to the live Room Alpha channel.
replace_once(
    'lib/client_settings.dart',
    "const String cGAndroidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';\n"
    "const String cGWindowsInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/latest';\n",
    "const String cGAndroidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-room-alpha/chernogram-room.apk';\n"
    "const String cGWindowsInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-room-alpha/chernogram-room-windows.zip';\n",
)

# ---------------------------------------------------------------------------
# Chat UX only: desktop back button, owner settings button, Enter-to-send.
# ---------------------------------------------------------------------------
replace_block_after(
    'lib/chat_screen.dart',
    '      appBar: AppBar(',
    '        leadingWidth:',
    '        titleSpacing: 0,',
    r'''        leadingWidth: 50,
        leading: Platform.isWindows
            ? const BackButton()
            : _isGroupChat
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ChernogramAvatar(
                  size: 42,
                  seed: _tunnel.id,
                  avatarBase64: _tunnel.avatarBase64,
                ),
              )
            : const BackButton(),
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''          if (canInvite)
            IconButton(
              tooltip: 'Пригласить',
''',
    '''          if (_isOwner)
            IconButton(
              tooltip: widget.ru ? 'Настройки чата' : 'Chat settings',
              onPressed: _showSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
          if (canInvite)
            IconButton(
              tooltip: 'Пригласить',
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (_) => _sendText(),
''',
    '''                                minLines: 1,
                                maxLines: 5,
                                textInputAction: Platform.isWindows
                                    ? TextInputAction.send
                                    : TextInputAction.newline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (_) {
                                  if (Platform.isWindows) _sendText();
                                },
''',
)

# ---------------------------------------------------------------------------
# Media stays local and is rendered from local paths instead of degrading into
# a filename/link card after the 0.83 streaming transfer completes.
# ---------------------------------------------------------------------------
windows_stats_helper = r'''  static Future<(int free, int total)?> _windowsDriveStats() async {
    if (!Platform.isWindows) return null;
    try {
      final support = await getApplicationSupportDirectory();
      final match = RegExp(r'^([A-Za-z]:)').firstMatch(support.path);
      final drive = match?.group(1) ?? 'C:';
      final script =
          "\$d = Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='$drive'\"; "
          "if (\$d) { Write-Output (\$d.FreeSpace.ToString() + '|' + \$d.Size.ToString()) }";
      final result = await Process.run(
        'powershell.exe',
        <String>['-NoProfile', '-NonInteractive', '-Command', script],
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split(RegExp(r'[\r\n]+')).last;
      final parts = line.split('|');
      if (parts.length != 2) return null;
      final free = int.tryParse(parts[0].trim());
      final total = int.tryParse(parts[1].trim());
      if (free == null || total == null || total <= 0) return null;
      return (free: free, total: total);
    } catch (_) {
      return null;
    }
  }

'''
replace_once(
    'lib/chat_media.dart',
    '  static Future<CgStorageStats> storageStats() async {\n',
    windows_stats_helper + '  static Future<CgStorageStats> storageStats() async {\n',
)
replace_once(
    'lib/chat_media.dart',
    '''  static Future<CgStorageStats> storageStats() async {
    final media = await mediaBytes();
    try {
''',
    '''  static Future<CgStorageStats> storageStats() async {
    final media = await mediaBytes();
    final windows = await _windowsDriveStats();
    if (windows != null) {
      return CgStorageStats(
        freeBytes: windows.free,
        totalBytes: windows.total,
        mediaBytes: media,
      );
    }
    try {
''',
)

# Use the same storage implementation in the profile card, including Windows.
replace_once(
    'lib/device_product_panels.dart',
    "import 'brand.dart';\n",
    "import 'brand.dart';\nimport 'chat_media.dart';\n",
)
replace_block_after(
    'lib/device_product_panels.dart',
    'class _CgDeviceStorageCardState',
    '  Future<void> _load() async {',
    '  String _size(int? bytes) {',
    r'''  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final stats = await CgMediaStore.storageStats();
      if (!mounted) return;
      setState(() {
        _freeBytes = stats.freeBytes >= 0 ? stats.freeBytes : null;
        _totalBytes = stats.totalBytes >= 0 ? stats.totalBytes : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _freeBytes = null;
        _totalBytes = null;
        _loading = false;
      });
    }
  }

''',
)

# In-app image viewer accepts either old inline bytes or the new local file.
replace_once(
    'lib/chat_media.dart',
    '''class CgImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String title;

  const CgImageViewer({super.key, required this.bytes, required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
''',
    '''class CgImageViewer extends StatelessWidget {
  final Uint8List? bytes;
  final File? file;
  final String title;

  const CgImageViewer({
    super.key,
    this.bytes,
    this.file,
    required this.title,
  }) : assert(bytes != null || file != null);

  @override
  Widget build(BuildContext context) => Scaffold(
''',
)
replace_once(
    'lib/chat_media.dart',
    '      child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),\n',
    '''      child: Center(
        child: file != null
            ? Image.file(file!, fit: BoxFit.contain, gaplessPlayback: true)
            : Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true),
      ),
''',
)

# Full inline image rendering from local file paths.
replace_once(
    'lib/chat_media.dart',
    '''    if (attachment.kind == 'image' && bytes != null) {
      return GestureDetector(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => CgImageViewer(bytes: bytes, title: attachment.name),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes,
            width: 270,
            height: 200,
            fit: BoxFit.cover,
''',
    '''    if (attachment.kind == 'image') {
      final localPath = attachment.localPath;
      final localFile = localPath != null && localPath.isNotEmpty
          ? File(localPath)
          : null;
      final hasLocal = localFile?.existsSync() == true;
      if (bytes != null || hasLocal) {
        return GestureDetector(
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => CgImageViewer(
                bytes: bytes,
                file: bytes == null && hasLocal ? localFile : null,
                title: attachment.name,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: bytes != null
                ? Image.memory(
                    bytes,
                    width: 270,
                    height: 200,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                : Image.file(
                    localFile!,
                    width: 270,
                    height: 200,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
        );
      }
    }
    if (false) {
      return GestureDetector(
        onTap: () {},
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes!,
            width: 270,
            height: 200,
            fit: BoxFit.cover,
''',
)
# Remove the dead tail from the old image branch that the structural replacement
# above leaves behind, while keeping the following circle/audio branches.
replace_once(
    'lib/chat_media.dart',
    '''            gaplessPlayback: true,
          ),
        ),
      );
    }
    if (attachment.kind == 'circle') {
''',
    '''            gaplessPlayback: true,
          ),
        ),
      );
    }
    if (attachment.kind == 'circle') {
''',
)

# Media library opens local images inside Chernogram and shows local thumbnails.
replace_once(
    'lib/chat_media.dart',
    '''    if (item.attachment.kind == 'image' && item.attachment.dataBase64 != null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CgImageViewer(
            bytes: base64Decode(item.attachment.dataBase64!),
            title: item.attachment.name,
          ),
        ),
      );
      return;
    }
    await OpenFilex.open(file.path);
''',
    '''    if (item.attachment.kind == 'image') {
      Uint8List? bytes;
      final raw = item.attachment.dataBase64;
      if (raw != null && raw.isNotEmpty) {
        try {
          bytes = base64Decode(raw);
        } catch (_) {}
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CgImageViewer(
            bytes: bytes,
            file: bytes == null ? file : null,
            title: item.attachment.name,
          ),
        ),
      );
      return;
    }
    await OpenFilex.open(file.path);
''',
)
replace_once(
    'lib/chat_media.dart',
    '''    if (attachment.kind == 'image' && attachment.dataBase64 != null) {
      try {
        return ClipRRect(
''',
    '''    if (attachment.kind == 'image' && attachment.dataBase64 != null) {
      try {
        return ClipRRect(
''',
)
# Add local image thumbnail fallback before the generic avatar.
replace_once(
    'lib/chat_media.dart',
    '''    return CircleAvatar(
      child: Icon(
''',
    '''    final localPath = attachment.localPath;
    if (attachment.kind == 'image' &&
        localPath != null &&
        localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      }
    }
    return CircleAvatar(
      child: Icon(
''',
)

# ---------------------------------------------------------------------------
# Local tray/toast notifications for the public-MQTT build. Firebase remains an
# optional wake-up layer; notification initialization no longer depends on it.
# ---------------------------------------------------------------------------
replace_once(
    'lib/push_service.dart',
    "import 'dart:async';\nimport 'dart:ui';\n",
    "import 'dart:async';\nimport 'dart:io';\nimport 'dart:ui';\n",
)

push_initialize = r'''  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final initialization = InitializationSettings(
      android: const AndroidInitializationSettings(
        '@drawable/chernogram_launcher_icon',
      ),
      windows: Platform.isWindows
          ? WindowsInitializationSettings(
              appName: 'Чернограм',
              appUserModelId: 'Chernogram.Chat.Room',
              guid: '1a56cc82-6dc7-4dba-8894-145c3cc9f784',
            )
          : null,
    );
    try {
      await _notifications.initialize(settings: initialization);
    } catch (_) {}

    if (Platform.isAndroid) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(_messageChannel);
      await android?.createNotificationChannel(_callChannel);
      await android?.requestNotificationsPermission();
      await android?.requestFullScreenIntentPermission();
    }

    if (!_firebaseConfigured) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    _token = await messaging.getToken();
    messaging.onTokenRefresh.listen((value) => _token = value);

    FirebaseMessaging.onMessage.listen((message) async {
      final event = CgPushEvent.fromMessage(message);
      _events.add(event);
      if (event.wake == 'call') {
        await showIncomingCallNotification(message.data);
      } else {
        await showMessageNotification(
          title: message.notification?.title ?? 'Чернограм',
          body: message.notification?.body ?? 'Новое сообщение',
          roomKey: event.roomKey,
          id: message.hashCode,
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _events.add(CgPushEvent.fromMessage(message));
    });
    final initial = await messaging.getInitialMessage();
    if (initial != null) _events.add(CgPushEvent.fromMessage(initial));
  }

  static Future<void> showMessageNotification({
    required String title,
    required String body,
    String roomKey = '',
    int? id,
  }) async {
    if (!_initialized) await initialize();
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'chernogram_messages',
        'Сообщения Чернограма',
        channelDescription: 'Новые сообщения и файлы',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        icon: '@drawable/chernogram_launcher_icon',
      ),
      windows: Platform.isWindows
          ? const WindowsNotificationDetails(
              subtitle: 'Чернограм',
            )
          : null,
    );
    try {
      await _notifications.show(
        id: id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
        title: title,
        body: body,
        notificationDetails: details,
        payload: roomKey,
      );
    } catch (_) {}
  }

'''
replace_block_after(
    'lib/push_service.dart',
    'class CgPushService {',
    '  static Future<void> initialize() async {',
    '  static Future<String?> refreshToken() async {',
    push_initialize,
)

# Upgrade call notification to Android + Windows and include caller name.
replace_block_after(
    'lib/push_service.dart',
    '  static Future<void> showIncomingCallNotification(',
    '  static Future<void> showIncomingCallNotification(',
    '\n  }\n}',
    r'''  static Future<void> showIncomingCallNotification(
    Map<String, dynamic> data,
  ) async {
    if (!_initialized) await initialize();
    if (Platform.isAndroid) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(_callChannel);
    }
    final video = data['video'] == true || data['video']?.toString() == 'true';
    final fromName = data['fromName']?.toString().trim();
    final title = video ? 'Видеозвонок' : 'Входящий звонок';
    final body = fromName?.isNotEmpty == true
        ? '$fromName звонит вам'
        : 'Откройте Чернограм, чтобы ответить';
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'chernogram_calls',
        'Звонки Чернограма',
        channelDescription: 'Входящие аудио- и видеозвонки',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: true,
        timeoutAfter: 60000,
        visibility: NotificationVisibility.private,
        icon: '@drawable/chernogram_launcher_icon',
      ),
      windows: Platform.isWindows
          ? const WindowsNotificationDetails(
              scenario: WindowsNotificationScenario.incomingCall,
            )
          : null,
    );
    try {
      await _notifications.show(
        id: data['packetId']?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
        title: title,
        body: body,
        notificationDetails: details,
        payload: data['roomKey']?.toString(),
      );
    } catch (_) {}
  }
''',
)

# App monitor emits the local notification even when the optional Firebase
# configuration is absent (the normal public-MQTT alpha build).
replace_once(
    'lib/app_monitor.dart',
    "import 'dart:convert';\n",
    "import 'dart:convert';\nimport 'dart:io';\n",
)
replace_once(
    'lib/app_monitor.dart',
    "import 'internet_core.dart';\n",
    "import 'internet_core.dart';\nimport 'push_service.dart';\n",
)
replace_once(
    'lib/app_monitor.dart',
    '''      if (playSound && fresh && CgMessageSoundRegistry.claim(message.id)) {
        unawaited(ChernogramSound.playMessage());
      }
''',
    '''      if (playSound && fresh && CgMessageSoundRegistry.claim(message.id)) {
        unawaited(ChernogramSound.playMessage());
        if (!CgPushService.configured || Platform.isWindows) {
          final attachment = message.attachment;
          final body = message.text.trim().isNotEmpty
              ? message.text.trim()
              : attachment != null
              ? 'Файл: ${attachment.name}'
              : 'Новое сообщение';
          unawaited(
            CgPushService.showMessageNotification(
              title: message.authorName.trim().isEmpty
                  ? 'Чернограм'
                  : message.authorName,
              body: body,
              roomKey: tunnelId,
              id: message.id.hashCode,
            ),
          );
        }
      }
''',
)
replace_once(
    'lib/app_monitor.dart',
    '''    final group = action == 'group_call_invite';
    _rememberContact(tunnelId, from, fromName);

    final context = chernogramNavigatorKey.currentContext;
''',
    '''    final group = action == 'group_call_invite';
    _rememberContact(tunnelId, from, fromName);
    if (!CgPushService.configured || Platform.isWindows) {
      unawaited(
        CgPushService.showIncomingCallNotification(<String, dynamic>{
          'packetId': callId,
          'roomKey': tunnelId,
          'video': video,
          'fromName': fromName,
        }),
      );
    }

    final context = chernogramNavigatorKey.currentContext;
''',
)

print('Chernogram full UI/local features patch 0.84 applied')
