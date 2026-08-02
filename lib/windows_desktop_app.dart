import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_monitor.dart';
import 'brand.dart';
import 'chat_screen.dart';
import 'core_models.dart';

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
  bool _privacyLens = false;
  bool _loading = true;
  String? _selectedTunnelId;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final values = await Future.wait<Object>(<Future<Object>>[
      CgStore.loadOrCreateProfile(),
      CgStore.loadTunnels(),
      CgStore.loadContacts(),
      CgStore.loadPrivacyLens(),
    ]);
    if (!mounted) return;
    final tunnels = values[1] as List<CgTunnel>;
    tunnels.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
    setState(() {
      _profile = values[0] as CgProfile;
      _tunnels = tunnels;
      _contacts = values[2] as List<CgContact>;
      _privacyLens = values[3] as bool;
      _selectedTunnelId = tunnels.isEmpty ? null : tunnels.first.id;
      _loading = false;
    });
    unawaited(_syncMonitor());
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

  DateTime _lastActivity(CgTunnel tunnel) =>
      tunnel.messages.isEmpty ? tunnel.createdAt : tunnel.messages.last.sentAt;

  CgTunnel? get _selectedTunnel {
    final id = _selectedTunnelId;
    if (id == null) return null;
    for (final tunnel in _tunnels) {
      if (tunnel.id == id) return tunnel;
    }
    return null;
  }

  void _selectTunnel(CgTunnel tunnel) {
    if (_selectedTunnelId == tunnel.id) return;
    setState(() => _selectedTunnelId = tunnel.id);
  }

  void _updateTunnel(CgTunnel updated) {
    final copy = <CgTunnel>[..._tunnels];
    final index = copy.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      copy.insert(0, updated);
    } else {
      copy[index] = updated;
    }
    copy.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
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
      final existing = copy[index];
      copy[index] = existing.copyWith(
        nickname: incoming.nickname.trim().isEmpty
            ? existing.nickname
            : incoming.nickname,
        lastSeenAt: incoming.lastSeenAt,
        tunnelIds: <String>{
          ...existing.tunnelIds,
          ...incoming.tunnelIds,
        }.toList(),
        avatarBase64: incoming.avatarBase64 ?? existing.avatarBase64,
      );
    }
    copy.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    if (mounted) setState(() => _contacts = copy);
    unawaited(CgStore.saveContacts(copy));
  }

  Future<void> _createRoom() async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final name = TextEditingController();
    var isPrivate = true;
    final result = await showDialog<({String name, bool isPrivate})>(
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
                    prefixIcon: const Icon(Icons.forum_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: Text(widget.ru ? 'Закрытая' : 'Private'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: const Icon(Icons.public_rounded),
                      label: Text(widget.ru ? 'Открытая' : 'Public'),
                    ),
                  ],
                  selected: <bool>{isPrivate},
                  onSelectionChanged: (value) {
                    setDialogState(() => isPrivate = value.first);
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
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                (name: name.text.trim(), isPrivate: isPrivate),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(widget.ru ? 'Создать' : 'Create'),
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
      isPrivate: result.isPrivate,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
    _updateTunnel(tunnel);
    if (mounted) setState(() => _selectedTunnelId = tunnel.id);
  }

  String? _inviteToken(String raw) {
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
      if (invite != null && invite.isNotEmpty) return invite;
    }
    return value;
  }

  Future<void> _joinRoom() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Подключиться к комнате' : 'Join room'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: widget.ru
                  ? 'Вставьте ссылку приглашения или токен'
                  : 'Paste an invite link or token',
              prefixIcon: const Icon(Icons.link_rounded),
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
    final token = raw == null ? null : _inviteToken(raw);
    if (token == null) return;
    final tunnel = CgTunnel.fromInviteToken(token);
    if (tunnel == null) {
      _showMessage(
        widget.ru
            ? 'Не удалось прочитать приглашение.'
            : 'The invite could not be read.',
      );
      return;
    }
    final existing = _tunnels.indexWhere((item) => item.id == tunnel.id);
    if (existing >= 0) {
      setState(() => _selectedTunnelId = _tunnels[existing].id);
      return;
    }
    _updateTunnel(tunnel);
    if (mounted) setState(() => _selectedTunnelId = tunnel.id);
  }

  Future<void> _forwardMessage(CgMessage source) async {
    if (_tunnels.isEmpty || !mounted) return;
    final target = await showDialog<CgTunnel>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Переслать в комнату' : 'Forward to room'),
        content: SizedBox(
          width: 430,
          height: 420,
          child: ListView.builder(
            itemCount: _tunnels.length,
            itemBuilder: (context, index) {
              final tunnel = _tunnels[index];
              return ListTile(
                leading: ChernogramAvatar(
                  size: 42,
                  seed: tunnel.id,
                  avatarBase64: tunnel.avatarBase64,
                ),
                title: Text(tunnel.displayName),
                onTap: () => Navigator.pop(context, tunnel),
              );
            },
          ),
        ),
      ),
    );
    final profile = _profile;
    if (target == null || profile == null) return;
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
    final updated = target.copyWith(messages: <CgMessage>[
      ...target.messages,
      message,
    ]);
    _updateTunnel(updated);
    await ChernogramAppMonitor.publishMessage(
      profile: profile,
      tunnel: updated,
      message: message,
    );
  }

  Future<File?> _materialize(CgAttachment attachment) async {
    final localPath = attachment.localPath;
    if (localPath != null && await File(localPath).exists()) {
      return File(localPath);
    }
    final raw = attachment.dataBase64;
    if (raw == null || raw.isEmpty) return null;
    final directory = await getTemporaryDirectory();
    final safeName = attachment.name.replaceAll(
      RegExp(r'[^A-Za-zА-Яа-я0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/${attachment.id}_$safeName');
    await file.writeAsBytes(base64Decode(raw), flush: true);
    return file;
  }

  Future<void> _openAttachment(CgAttachment attachment) async {
    final file = await _materialize(attachment);
    if (file == null) {
      _showMessage(
        widget.ru
            ? 'Локальная копия файла пока недоступна.'
            : 'A local copy of this file is not available yet.',
      );
      return;
    }
    await OpenFilex.open(file.path);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    if (message.type == 'call') {
      return widget.ru ? 'Звонок' : 'Call';
    }
    return message.text.trim().isEmpty
        ? (widget.ru ? 'Новое событие' : 'New event')
        : message.text.trim();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _fileIcon(String kind) {
    switch (kind) {
      case 'image':
        return Icons.image_outlined;
      case 'audio':
        return Icons.audio_file_outlined;
      case 'video':
        return Icons.video_file_outlined;
      case 'archive':
        return Icons.folder_zip_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _topBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .96),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const ChernogramLogo(size: 38),
          const SizedBox(width: 11),
          Text(
            'Чернограм',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              widget.ru ? 'Windows • 4 устройства' : 'Windows • 4 devices',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: widget.ru ? 'Подключиться по ссылке' : 'Join by link',
            onPressed: _joinRoom,
            icon: const Icon(Icons.link_rounded),
          ),
          IconButton(
            tooltip: widget.ru ? 'Проверить обновления' : 'Check updates',
            onPressed: widget.onCheckUpdates,
            icon: const Icon(Icons.system_update_alt_rounded),
          ),
          IconButton(
            tooltip: widget.ru ? 'Сменить язык' : 'Change language',
            onPressed: widget.onChangeLanguage,
            icon: const Icon(Icons.language_rounded),
          ),
          IconButton(
            tooltip: widget.ru ? 'Сменить тему' : 'Change theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomsPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final tunnels = _tunnels.where((tunnel) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.ru ? 'Поиск по чатам' : 'Search chats',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _createRoom,
                    icon: const Icon(Icons.add_comment_rounded),
                    label: Text(widget.ru ? 'Комната' : 'Room'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: widget.ru ? 'Вставить приглашение' : 'Paste invite',
                  onPressed: _joinRoom,
                  icon: const Icon(Icons.qr_code_2_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: tunnels.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.ru
                            ? 'Создайте комнату или вставьте приглашение с телефона.'
                            : 'Create a room or paste an invite from a phone.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: tunnels.length,
                    itemBuilder: (context, index) {
                      final tunnel = tunnels[index];
                      final selected = tunnel.id == _selectedTunnelId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: selected
                              ? scheme.primary.withValues(alpha: .14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _selectTunnel(tunnel),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  ChernogramAvatar(
                                    size: 46,
                                    seed: tunnel.id,
                                    avatarBase64: tunnel.avatarBase64,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _privacyLens
                                                    ? '••••••••'
                                                    : tunnel.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              tunnel.isPrivate
                                                  ? Icons.lock_outline_rounded
                                                  : Icons.public_rounded,
                                              size: 14,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _privacyLens ? '••••••••' : _preview(tunnel),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                ChernogramAvatar(
                  size: 40,
                  seed: _profile?.id ?? 'profile',
                  avatarBase64: _profile?.avatarBase64,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _privacyLens
                            ? '••••••'
                            : (_profile?.nickname ?? 'Чернограм'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        widget.ru
                            ? '${_tunnels.length} комнат'
                            : '${_tunnels.length} rooms',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: widget.ru ? 'Скрыть данные' : 'Privacy lens',
                  onPressed: () async {
                    final next = !_privacyLens;
                    await CgStore.savePrivacyLens(next);
                    if (mounted) setState(() => _privacyLens = next);
                  },
                  icon: Icon(
                    _privacyLens
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyChat(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChernogramLogo(size: 92),
              const SizedBox(height: 18),
              Text(
                widget.ru ? 'Выберите комнату' : 'Select a room',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'Слева находятся комнаты, справа сразу отображаются их файлы.'
                    : 'Rooms are on the left and their files appear on the right.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _filesPanel(BuildContext context, CgTunnel? tunnel) {
    final scheme = Theme.of(context).colorScheme;
    final entries = tunnel == null
        ? const <({CgMessage message, CgAttachment attachment})>[]
        : tunnel.messages
            .where((message) => message.attachment != null && !message.deleted)
            .map(
              (message) => (
                message: message,
                attachment: message.attachment!,
              ),
            )
            .toList()
          ..sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_copy_outlined),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.ru ? 'Файлы комнаты' : 'Room files',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${entries.length}'),
                ),
              ],
            ),
          ),
          Expanded(
            child: tunnel == null
                ? Center(
                    child: Text(widget.ru ? 'Комната не выбрана' : 'No room selected'),
                  )
                : entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_open_rounded, size: 54),
                              const SizedBox(height: 12),
                              Text(
                                widget.ru
                                    ? 'В этой комнате пока нет файлов'
                                    : 'This room has no files yet',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.ru
                                    ? 'Отправьте файл кнопкой «+» в центре.'
                                    : 'Send a file with the “+” button in the center.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Material(
                              color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openAttachment(entry.attachment),
                                child: Padding(
                                  padding: const EdgeInsets.all(11),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: scheme.primary.withValues(alpha: .12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _fileIcon(entry.attachment.kind),
                                          color: scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _privacyLens
                                                  ? '••••••••'
                                                  : entry.attachment.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${_formatBytes(entry.attachment.size)} • ${entry.message.authorName}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.open_in_new_rounded, size: 17),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(body: Center(child: ChernogramLogo(size: 132)));
    }
    final selected = _selectedTunnel;
    return Scaffold(
      body: CgChatPatternBackground(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final leftWidth = width < 1180 ? 270.0 : 315.0;
                  final rightWidth = width < 1180 ? 250.0 : 320.0;
                  return Row(
                    children: [
                      SizedBox(width: leftWidth, child: _roomsPanel(context)),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selected == null
                            ? _emptyChat(context)
                            : CgChatScreen(
                                key: ValueKey<String>(
                                  'windows-room-${selected.id}',
                                ),
                                ru: widget.ru,
                                profile: _profile!,
                                tunnel: selected,
                                privacyLens: _privacyLens,
                                onChanged: _updateTunnel,
                                onForward: _forwardMessage,
                                onContactSeen: _rememberContact,
                              ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: rightWidth,
                        child: _filesPanel(context, selected),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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
