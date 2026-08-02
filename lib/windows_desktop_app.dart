import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_monitor.dart';
import 'brand.dart';
import 'chat_media.dart';
import 'chat_screen.dart';
import 'client_settings.dart';
import 'core_models.dart';
import 'device_pairing.dart';

class ChernogramWindowsDesktop extends StatefulWidget {
  final bool ru;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;

  const ChernogramWindowsDesktop({
    super.key,
    required this.ru,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramWindowsDesktop> createState() =>
      _ChernogramWindowsDesktopState();
}

class _ChernogramWindowsDesktopState
    extends State<ChernogramWindowsDesktop> {
  final TextEditingController _search = TextEditingController();

  CgProfile? _profile;
  List<CgTunnel> _tunnels = <CgTunnel>[];
  List<CgContact> _contacts = <CgContact>[];
  String? _selectedTunnelId;
  bool _privacyLens = false;
  bool _loading = true;
  bool _rightPanel = true;
  String? _loadError;
  int _rightTab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final values = await Future.wait<Object>(<Future<Object>>[
        CgStore.loadOrCreateProfile(),
        CgStore.loadTunnels(),
        CgStore.loadContacts(),
        CgStore.loadPrivacyLens(),
      ]).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final tunnels = values[1] as List<CgTunnel>;
      tunnels.sort((a, b) => _activity(b).compareTo(_activity(a)));
      setState(() {
        _profile = values[0] as CgProfile;
        _tunnels = tunnels;
        _contacts = values[2] as List<CgContact>;
        _privacyLens = values[3] as bool;
        _selectedTunnelId = tunnels.isEmpty ? null : tunnels.first.id;
        _loading = false;
      });
      unawaited(_syncMonitor());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  DateTime _activity(CgTunnel tunnel) =>
      tunnel.messages.isEmpty ? tunnel.createdAt : tunnel.messages.last.sentAt;

  CgTunnel? get _selected {
    final id = _selectedTunnelId;
    if (id == null) return null;
    for (final tunnel in _tunnels) {
      if (tunnel.id == id) return tunnel;
    }
    return null;
  }

  Future<void> _syncMonitor() async {
    final profile = _profile;
    if (profile == null) return;
    await ChernogramAppMonitor.sync(
      profile: profile,
      tunnels: _tunnels,
      ru: widget.ru,
      onTunnelChanged: _updateTunnel,
      onContactSeen: _rememberContact,
    );
  }

  void _updateTunnel(CgTunnel updated) {
    final copy = <CgTunnel>[..._tunnels];
    final index = copy.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      copy.insert(0, updated);
    } else {
      copy[index] = updated;
    }
    copy.sort((a, b) => _activity(b).compareTo(_activity(a)));
    if (mounted) {
      setState(() {
        _tunnels = copy;
        _selectedTunnelId ??= updated.id;
      });
    }
    unawaited(CgStore.saveTunnels(copy));
    unawaited(_syncMonitor());
  }

  void _rememberContact(CgContact incoming) {
    if (incoming.id.isEmpty || incoming.id == _profile?.id) return;
    final copy = <CgContact>[..._contacts];
    final index = copy.indexWhere((item) => item.id == incoming.id);
    if (index < 0) {
      copy.insert(0, incoming);
    } else {
      final old = copy[index];
      copy[index] = old.copyWith(
        nickname: incoming.nickname.trim().isEmpty
            ? old.nickname
            : incoming.nickname,
        lastSeenAt: incoming.lastSeenAt,
        tunnelIds: <String>{...old.tunnelIds, ...incoming.tunnelIds}.toList(),
        avatarBase64: incoming.avatarBase64 ?? old.avatarBase64,
      );
    }
    copy.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    if (mounted) setState(() => _contacts = copy);
    unawaited(CgStore.saveContacts(copy));
  }

  bool _roomOnline(CgTunnel tunnel) {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 55));
    return _contacts.any(
      (contact) =>
          contact.tunnelIds.contains(tunnel.id) &&
          contact.lastSeenAt.isAfter(cutoff),
    );
  }

  String _preview(CgTunnel tunnel) {
    if (tunnel.messages.isEmpty) {
      return widget.ru ? 'Комната готова' : 'Room is ready';
    }
    final message = tunnel.messages.last;
    if (message.deleted) {
      return widget.ru ? 'Сообщение удалено' : 'Message deleted';
    }
    if (message.attachment != null) return message.attachment!.name;
    if (message.type == 'call') return widget.ru ? 'Звонок' : 'Call';
    return message.text.trim().isEmpty
        ? (widget.ru ? 'Новое событие' : 'New event')
        : message.text.trim();
  }

  Future<void> _createRoom() async {
    final profile = _profile;
    if (profile == null) return;
    final name = TextEditingController();
    var private = true;
    final result = await showDialog<({String name, bool private})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.ru ? 'Новая комната' : 'New room'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.ru ? 'Название' : 'Name',
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: Text(widget.ru ? 'Закрытая' : 'Private'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.public_rounded),
                      label: Text(widget.ru ? 'Открытая' : 'Public'),
                    ),
                  ],
                  selected: <bool>{private},
                  onSelectionChanged: (value) {
                    setDialogState(() => private = value.first);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.ru ? 'Отмена' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (name: name.text.trim(), private: private),
              ),
              child: Text(widget.ru ? 'Создать' : 'Create'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (result == null) return;
    final tunnel = CgTunnel(
      id: CgIds.random(18),
      name: result.name,
      isPrivate: result.private,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
    _updateTunnel(tunnel);
    setState(() => _selectedTunnelId = tunnel.id);
  }

  String? _token(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null) {
      if (uri.scheme == 'chernogram' &&
          uri.host == 'join' &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      final invite = uri.queryParameters['invite'];
      if (invite?.isNotEmpty == true) return invite;
    }
    return value;
  }

  Future<void> _joinToken(String raw) async {
    final token = _token(raw);
    if (token == null) return;
    final tunnel = CgTunnel.fromInviteToken(token);
    if (tunnel == null) {
      _toast(widget.ru ? 'Приглашение не распознано.' : 'Invite not recognized.');
      return;
    }
    final index = _tunnels.indexWhere((item) => item.id == tunnel.id);
    if (index >= 0) {
      setState(() => _selectedTunnelId = _tunnels[index].id);
      return;
    }
    _updateTunnel(tunnel);
    setState(() => _selectedTunnelId = tunnel.id);
  }

  Future<void> _joinByLink() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Подключиться к комнате' : 'Join room'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: widget.ru
                  ? 'Вставьте ссылку приглашения'
                  : 'Paste an invite link',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(widget.ru ? 'Подключиться' : 'Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _joinToken(value);
  }

  Future<void> _pairByQr() async {
    final invite = await showDesktopRoomPairing(context, ru: widget.ru);
    if (invite != null) await _joinToken(invite);
  }

  Future<void> _forward(CgMessage source) async {
    final profile = _profile;
    if (profile == null || _tunnels.isEmpty) return;
    final target = await showDialog<CgTunnel>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Переслать' : 'Forward'),
        content: SizedBox(
          width: 430,
          height: 430,
          child: ListView.builder(
            itemCount: _tunnels.length,
            itemBuilder: (context, index) {
              final tunnel = _tunnels[index];
              return ListTile(
                leading: ChernogramAvatar(size: 42, seed: tunnel.id),
                title: Text(tunnel.displayName),
                onTap: () => Navigator.pop(context, tunnel),
              );
            },
          ),
        ),
      ),
    );
    if (target == null) return;
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: profile.id,
      authorName: profile.nickname,
      text: source.text,
      sentAt: DateTime.now(),
      type: source.type,
      attachment: source.attachment,
      meta: <String, dynamic>{
        ...source.meta,
        'forwarded': true,
        'forwardedFrom': source.authorName,
      },
    );
    final updated = target.copyWith(
      messages: <CgMessage>[...target.messages, message],
    );
    _updateTunnel(updated);
    await ChernogramAppMonitor.publishMessage(
      profile: profile,
      tunnel: updated,
      message: message,
    );
  }

  Future<void> _shareFile() async {
    final profile = _profile;
    if (profile == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.length > 20 * 1024 * 1024) {
      _toast(widget.ru ? 'Файл должен быть до 20 МБ.' : 'File must be under 20 MB.');
      return;
    }
    final target = await showDialog<CgTunnel>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Куда отправить файл' : 'Share file to'),
        content: SizedBox(
          width: 460,
          height: 450,
          child: ListView(
            children: [
              for (final tunnel in _tunnels)
                ListTile(
                  leading: Icon(
                    tunnel.isPrivate
                        ? Icons.lock_outline_rounded
                        : Icons.public_rounded,
                  ),
                  title: Text(tunnel.displayName),
                  subtitle: Text(
                    tunnel.isPrivate
                        ? (widget.ru ? 'Закрытый доступ' : 'Private access')
                        : (widget.ru ? 'Общий доступ' : 'Public access'),
                  ),
                  onTap: () => Navigator.pop(context, tunnel),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    final id = CgIds.random(20);
    final file = await CgMediaStore.persistBytes(
      attachmentId: id,
      name: picked.name,
      bytes: bytes,
    );
    final attachment = CgAttachment(
      id: id,
      name: picked.name,
      size: bytes.length,
      kind: _kind(picked.name),
      dataBase64: base64Encode(bytes),
      localPath: file.path,
    );
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: profile.id,
      authorName: profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: attachment,
      meta: <String, dynamic>{'publicFile': !target.isPrivate},
    );
    final updated = target.copyWith(
      messages: <CgMessage>[...target.messages, message],
    );
    _updateTunnel(updated);
    await ChernogramAppMonitor.publishMessage(
      profile: profile,
      tunnel: updated,
      message: message,
    );
  }

  String _kind(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (<String>{'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(ext)) {
      return 'image';
    }
    if (<String>{'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus'}.contains(ext)) {
      return 'audio';
    }
    if (<String>{'mp4', 'mov', 'mkv', 'webm'}.contains(ext)) return 'video';
    if (<String>{'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) return 'archive';
    return 'document';
  }

  Future<void> _allFiles() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMediaLibraryScreen(
          ru: widget.ru,
          tunnels: _tunnels,
          onTunnelsChanged: (value) {
            for (final tunnel in value) {
              _updateTunnel(tunnel);
            }
          },
        ),
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _settings() async {
    final profile = _profile;
    if (profile == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Настройки' : 'Settings'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(widget.ru ? 'Аккаунт и устройство' : 'Account and device'),
                subtitle: Text('ID ${profile.id}'),
                onTap: () {
                  Navigator.pop(context);
                  showDeviceAccountSheet(this.context, ru: widget.ru, profile: profile);
                },
              ),
              ListTile(
                leading: const Icon(Icons.install_mobile_rounded),
                title: Text(widget.ru ? 'Поделиться приложением' : 'Share app'),
                onTap: () {
                  Navigator.pop(context);
                  showChernogramInstallShare(this.context, ru: widget.ru);
                },
              ),
              ListTile(
                leading: Icon(widget.darkMode ? Icons.light_mode : Icons.dark_mode),
                title: Text(widget.ru ? 'Сменить тему' : 'Change theme'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onToggleTheme();
                },
              ),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(widget.ru ? 'English' : 'Русский'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onChangeLanguage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onCheckUpdates();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leftPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final rooms = _tunnels.where((tunnel) {
      if (query.isEmpty) return true;
      return tunnel.displayName.toLowerCase().contains(query) ||
          tunnel.messages.any(
            (message) =>
                message.text.toLowerCase().contains(query) ||
                (message.attachment?.name.toLowerCase().contains(query) ?? false),
          );
    }).toList();
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 62,
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: widget.ru ? 'Меню' : 'Menu',
                  icon: const Icon(Icons.menu_rounded),
                  onSelected: (value) {
                    switch (value) {
                      case 'new':
                        _createRoom();
                      case 'link':
                        _joinByLink();
                      case 'qr':
                        _pairByQr();
                      case 'files':
                        _allFiles();
                      case 'share':
                        showChernogramInstallShare(context, ru: widget.ru);
                      case 'settings':
                        _settings();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'new', child: Text(widget.ru ? 'Новая комната' : 'New room')),
                    PopupMenuItem(value: 'link', child: Text(widget.ru ? 'Вставить приглашение' : 'Paste invite')),
                    PopupMenuItem(value: 'qr', child: Text(widget.ru ? 'Подключить по QR' : 'Connect with QR')),
                    PopupMenuItem(value: 'files', child: Text(widget.ru ? 'Все файлы' : 'All files')),
                    PopupMenuItem(value: 'share', child: Text(widget.ru ? 'Поделиться приложением' : 'Share app')),
                    PopupMenuItem(value: 'settings', child: Text(widget.ru ? 'Настройки' : 'Settings')),
                  ],
                ),
                const ChernogramLogo(size: 34),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Чернограм',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: widget.ru ? 'Подключить по QR' : 'Connect with QR',
                  onPressed: _pairByQr,
                  icon: const Icon(Icons.qr_code_2_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.ru ? 'Поиск' : 'Search',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: rooms.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: FilledButton.icon(
                        onPressed: _createRoom,
                        icon: const Icon(Icons.add_comment_rounded),
                        label: Text(widget.ru ? 'Создать комнату' : 'Create room'),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final tunnel = rooms[index];
                      final selected = tunnel.id == _selectedTunnelId;
                      final online = _roomOnline(tunnel);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Material(
                          color: selected
                              ? scheme.primary.withValues(alpha: .14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => _selectedTunnelId = tunnel.id),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ChernogramAvatar(
                                        size: 50,
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
                                              border: Border.all(color: scheme.surface, width: 2),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _privacyLens ? '••••••' : tunnel.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                            Icon(
                                              tunnel.isPrivate
                                                  ? Icons.lock_outline_rounded
                                                  : Icons.public_rounded,
                                              size: 14,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _privacyLens ? '••••••••' : _preview(tunnel),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: ChernogramAvatar(
              size: 42,
              seed: _profile?.id ?? 'profile',
              avatarBase64: _profile?.avatarBase64,
            ),
            title: Text(
              _privacyLens ? '••••••' : (_profile?.nickname ?? 'Чернограм'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(widget.ru ? 'Профиль и настройки' : 'Profile and settings'),
            trailing: const Icon(Icons.settings_outlined),
            onTap: _settings,
          ),
        ],
      ),
    );
  }

  Widget _rightPanelWidget(BuildContext context, CgTunnel tunnel) {
    final scheme = Theme.of(context).colorScheme;
    final members = _contacts
        .where((contact) => contact.tunnelIds.contains(tunnel.id))
        .toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    final attachments = tunnel.messages
        .where((message) => message.attachment != null && !message.deleted)
        .toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    final visible = attachments.where((message) {
      final kind = message.attachment!.kind;
      if (_rightTab == 0) return true;
      if (_rightTab == 1) return kind == 'image' || kind == 'video' || kind == 'circle';
      return kind != 'image' && kind != 'video' && kind != 'circle';
    }).toList();
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.ru ? 'Информация' : 'Info',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _rightPanel = false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ChernogramAvatar(size: 78, seed: tunnel.id, avatarBase64: tunnel.avatarBase64),
                const SizedBox(height: 10),
                Text(
                  tunnel.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: ChernogramColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${members.where((item) => item.lastSeenAt.isAfter(DateTime.now().subtract(const Duration(seconds: 55)))).length + 1} ${widget.ru ? 'онлайн' : 'online'}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pairByQr,
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: Text(widget.ru ? 'QR' : 'QR'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _shareFile,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(widget.ru ? 'Файл' : 'File'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, label: Text(widget.ru ? 'Все' : 'All')),
                ButtonSegment(value: 1, label: Text(widget.ru ? 'Медиа' : 'Media')),
                ButtonSegment(value: 2, label: Text(widget.ru ? 'Файлы' : 'Files')),
              ],
              selected: <int>{_rightTab},
              onSelectionChanged: (value) => setState(() => _rightTab = value.first),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.ru ? 'В этой комнате пока нет файлов.' : 'No files in this room yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final message = visible[index];
                      final attachment = message.attachment!;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            attachment.kind == 'image'
                                ? Icons.image_outlined
                                : attachment.kind == 'video' || attachment.kind == 'circle'
                                ? Icons.movie_outlined
                                : Icons.description_outlined,
                          ),
                          title: Text(
                            attachment.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            tunnel.isPrivate
                                ? (widget.ru ? 'Закрытый доступ' : 'Private access')
                                : (widget.ru ? 'Общий доступ' : 'Public access'),
                          ),
                          onTap: () => CgMediaStore.open(attachment),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          ExpansionTile(
            leading: const Icon(Icons.group_outlined),
            title: Text('${widget.ru ? 'Участники' : 'Members'} • ${members.length + 1}'),
            children: [
              ListTile(
                leading: ChernogramAvatar(size: 34, seed: _profile?.id ?? 'me'),
                title: Text(_profile?.nickname ?? 'Чернограм'),
                trailing: const Icon(Icons.circle, size: 10, color: ChernogramColors.success),
              ),
              for (final member in members.take(8))
                ListTile(
                  leading: ChernogramAvatar(size: 34, seed: member.id),
                  title: Text(member.nickname),
                  trailing: Icon(
                    Icons.circle,
                    size: 10,
                    color: member.lastSeenAt.isAfter(DateTime.now().subtract(const Duration(seconds: 55)))
                        ? ChernogramColors.success
                        : scheme.outline,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: ChernogramLogo(size: 124)));
    }
    if (_loadError != null || _profile == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 54),
                  const SizedBox(height: 12),
                  Text(
                    widget.ru ? 'Не удалось открыть профиль' : 'Could not open profile',
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(_loadError ?? ''),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _bootstrap,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(widget.ru ? 'Повторить' : 'Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final selected = _selected;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 340, child: _leftPanel(context)),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ChernogramLogo(size: 94),
                        const SizedBox(height: 16),
                        Text(
                          widget.ru ? 'Выберите комнату' : 'Select a room',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _pairByQr,
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: Text(widget.ru ? 'Подключить по QR' : 'Connect with QR'),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      CgChatScreen(
                        key: ValueKey<String>('desktop-${selected.id}'),
                        ru: widget.ru,
                        profile: _profile!,
                        tunnel: selected,
                        privacyLens: _privacyLens,
                        onChanged: _updateTunnel,
                        onForward: _forward,
                        onContactSeen: _rememberContact,
                      ),
                      if (!_rightPanel)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: IconButton.filledTonal(
                            tooltip: widget.ru ? 'Информация и файлы' : 'Info and files',
                            onPressed: () => setState(() => _rightPanel = true),
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                        ),
                    ],
                  ),
          ),
          if (_rightPanel && selected != null) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: 320, child: _rightPanelWidget(context, selected)),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    unawaited(ChernogramAppMonitor.stop());
    super.dispose();
  }
}
