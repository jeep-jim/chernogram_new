import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_screen.dart';
import 'app_monitor.dart';
import 'brand.dart';
import 'chat_media.dart';
import 'chat_screen.dart';
import 'core_models.dart';
import 'internet_core.dart';
import 'music_player.dart';


const String _chernogramLanding =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';

const Set<String> _forbiddenNicknameRoots = <String>{
  'admin',
  'administrator',
  'support',
  'moderator',
  'security',
  'system',
  'official',
  'chernogram',
  'чернограм',
  'админ',
  'администратор',
  'поддержка',
  'модератор',
  'безопасность',
  'система',
  'официальный',
};

String _nicknameKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s._\-]+'), '')
    .replaceAll('0', 'o')
    .replaceAll('1', 'i');

String? _forbiddenNicknameRoot(String value) {
  final key = _nicknameKey(value);
  for (final root in _forbiddenNicknameRoots) {
    if (key.contains(_nicknameKey(root))) return root;
  }
  return null;
}

class ChernogramV07 extends StatefulWidget {
  final bool ru;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;

  const ChernogramV07({
    super.key,
    required this.ru,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramV07> createState() => _ChernogramV07State();
}

class _ChernogramV07State extends State<ChernogramV07> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  CgProfile? _profile;
  List<CgTunnel> _tunnels = <CgTunnel>[];
  List<CgContact> _contacts = <CgContact>[];
  bool _loading = true;
  bool _privacyLens = false;
  int _tab = 0;
  String? _activeTunnelId;
  Map<String, int> _unreadCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final profile = await CgStore.loadOrCreateProfile();
    final tunnels = await CgStore.loadTunnels();
    final contacts = await CgStore.loadContacts();
    final privacy = await CgStore.loadPrivacyLens();
    final prefs = await SharedPreferences.getInstance();
    final unreadRaw = prefs.getString('chernogram_unread_v1');
    final unread = <String, int>{};
    if (unreadRaw != null) {
      try {
        final decoded = jsonDecode(unreadRaw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            unread[entry.key.toString()] =
                int.tryParse(entry.value.toString()) ?? 0;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _tunnels = tunnels;
      _contacts = contacts;
      _privacyLens = privacy;
      _unreadCounts = unread;
      _loading = false;
    });
    _syncMonitor();
    await _listenLinks();
  }


  Future<void> _persistUnread() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chernogram_unread_v1', jsonEncode(_unreadCounts));
  }

  void _markRead(String tunnelId) {
    if ((_unreadCounts[tunnelId] ?? 0) == 0) return;
    _unreadCounts[tunnelId] = 0;
    if (mounted) setState(() {});
    unawaited(_persistUnread());
  }

  Future<void> _listenLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_handleUri(initial));
        });
      }
      _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
        unawaited(_handleUri(uri));
      });
    } catch (_) {}
  }

  String? _tokenFromUri(Uri uri) {
    if (uri.scheme == 'chernogram' &&
        uri.host == 'join' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    final invite = uri.queryParameters['invite'];
    if (invite != null && invite.isNotEmpty) return invite;
    return null;
  }

  Future<void> _handleUri(Uri uri) async {
    final token = _tokenFromUri(uri);
    if (token == null) return;
    await _joinToken(token);
  }

  Future<void> _joinToken(String token) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final tunnel = CgTunnel.fromInviteToken(token);
    if (tunnel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Это не приглашение Чернограма.'
                : 'This is not a Chernogram invite.',
          ),
        ),
      );
      return;
    }
    final existingIndex = _tunnels.indexWhere((item) => item.id == tunnel.id);
    if (existingIndex >= 0) {
      await _openTunnel(_tunnels[existingIndex]);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          tunnel.isPrivate ? Icons.visibility_off_outlined : Icons.public,
          size: 38,
        ),
        title: Text(widget.ru ? 'Подключиться?' : 'Join tunnel?'),
        content: Text(
          '${tunnel.displayName}\n\n${widget.ru ? 'Чат, файлы и звонки работают через интернет между разными сетями.' : 'Chat, files and calls work across different networks.'}',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Подключиться' : 'Join'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _tunnels = [tunnel, ..._tunnels];
      _tab = 0;
    });
    await CgStore.saveTunnels(_tunnels);
    _syncMonitor();
    await _openTunnel(tunnel);
  }

  Future<void> _scanQr() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => CgQrScanner(ru: widget.ru)),
    );
    if (token != null) await _joinToken(token);
  }

  Future<void> _createTunnel() async {
    final profile = _profile;
    if (profile == null) return;
    final result = await showModalBottomSheet<({String name, bool isPrivate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final name = TextEditingController();
        var isPrivate = true;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.ru ? 'Новый чат' : 'New chat',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.ru
                      ? 'Название можно не вводить. Чат создастся сразу и предложит отправить приглашение.'
                      : 'The name is optional. The chat opens immediately and offers an invite.',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .56),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        widget.ru ? 'Название — необязательно' : 'Name — optional',
                    hintText: widget.ru
                        ? 'Например: Семья'
                        : 'For example: Family',
                  ),
                ),
                const SizedBox(height: 10),
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
                        ? (widget.ru ? 'Приватный' : 'Private')
                        : (widget.ru ? 'Открытый' : 'Open'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    isPrivate
                        ? (widget.ru
                            ? 'Вход только по секретной ссылке или QR.'
                            : 'Join only with the secret invite or QR.')
                        : (widget.ru
                            ? 'Ссылку можно свободно пересылать.'
                            : 'The invite can be freely forwarded.'),
                  ),
                  onChanged: (value) =>
                      setSheetState(() => isPrivate = value),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      (name: name.text.trim(), isPrivate: isPrivate),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      widget.ru
                          ? 'Создать и пригласить'
                          : 'Create and invite',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final tunnel = CgTunnel(
      id: CgIds.random(18),
      name: result.name,
      isPrivate: result.isPrivate,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
    setState(() => _tunnels = [tunnel, ..._tunnels]);
    await CgStore.saveTunnels(_tunnels);
    _syncMonitor();
    await _openTunnel(tunnel, autoInvite: true);
  }

  Future<void> _deleteTunnel(CgTunnel tunnel) async {
    await CgMediaStore.purgeTunnelFiles(tunnel);
    await InternetRelay.close(tunnel.id);
    _tunnels = _tunnels.where((item) => item.id != tunnel.id).toList();
    await CgStore.saveTunnels(_tunnels);
    if (mounted) setState(() {});
    _syncMonitor();
  }

  Future<void> _openTunnel(
    CgTunnel tunnel, {
    bool autoInvite = false,
  }) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    _activeTunnelId = tunnel.id;
    _markRead(tunnel.id);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgChatScreen(
          ru: widget.ru,
          profile: profile,
          tunnel: tunnel,
          privacyLens: _privacyLens,
          autoInvite: autoInvite,
          onChanged: _updateTunnel,
          onDelete: _deleteTunnel,
          onForward: (message) => _forwardMessage(message, tunnel.id),
          onContactSeen: _rememberContact,
        ),
      ),
    );
    _activeTunnelId = null;
    _markRead(tunnel.id);
  }

  void _updateTunnel(CgTunnel updated) {
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
    final previous = index < 0 ? null : _tunnels[index];
    if (previous != null && _activeTunnelId != updated.id) {
      final known = previous.messages.map((message) => message.id).toSet();
      final profileId = _profile?.id;
      final incoming = updated.messages.where((message) {
        if (known.contains(message.id) || message.authorId == profileId) return false;
        return DateTime.now().difference(message.sentAt.toLocal()).inMinutes.abs() <= 2;
      }).length;
      if (incoming > 0) {
        _unreadCounts[updated.id] = (_unreadCounts[updated.id] ?? 0) + incoming;
        unawaited(_persistUnread());
      }
    } else if (_activeTunnelId == updated.id) {
      _unreadCounts[updated.id] = 0;
    }
    if (index < 0) {
      _tunnels = [updated, ..._tunnels];
    } else {
      final copy = [..._tunnels];
      copy[index] = updated;
      _tunnels = copy;
    }
    _tunnels.sort((a, b) {
      final aTime =
          a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
      final bTime =
          b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
      return bTime.compareTo(aTime);
    });
    if (mounted) setState(() {});
    unawaited(CgStore.saveTunnels(_tunnels));
    _syncMonitor();
  }


  Future<void> _forwardMessage(CgMessage source, String sourceTunnelId) async {
    if (source.deleted || !mounted) return;
    final targets = _tunnels
        .where((tunnel) => tunnel.id != sourceTunnelId)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Создайте ещё один чат для пересылки.'
                : 'Create another chat to forward this message.',
          ),
        ),
      );
      return;
    }
    final target = await showModalBottomSheet<CgTunnel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
          itemCount: targets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final tunnel = targets[index];
            return Card(
              child: ListTile(
                leading: _TunnelListAvatar(tunnel: tunnel),
                title: Text(
                  tunnel.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(widget.ru ? 'Переслать сюда' : 'Forward here'),
                onTap: () => Navigator.pop(context, tunnel),
              ),
            );
          },
        ),
      ),
    );
    final profile = _profile;
    if (target == null || profile == null) return;
    final forwarded = CgMessage(
      id: CgIds.random(24),
      authorId: profile.id,
      authorName: profile.nickname,
      text: source.text,
      sentAt: DateTime.now(),
      type: source.attachment == null ? 'text' : 'attachment',
      attachment: source.attachment,
      meta: <String, dynamic>{
        ...source.meta,
        'forwardedFrom': source.authorName,
      },
    );
    final updated = target.copyWith(
      messages: <CgMessage>[...target.messages, forwarded],
    );
    _updateTunnel(updated);
    final session = InternetRelay.session(target.id) ??
        await InternetRelay.open(
          tunnelId: target.id,
          secret: target.secret,
          profileId: profile.id,
          nickname: profile.nickname,
          history: updated.messages.map((message) => message.toJson()).toList(),
        );
    await session.sendMessage(forwarded.toJson());
  }

  void _rememberContact(CgContact incoming) {
    if (incoming.id.isEmpty || incoming.id == _profile?.id) return;
    final index = _contacts.indexWhere((item) => item.id == incoming.id);
    if (index < 0) {
      _contacts = [incoming, ..._contacts];
    } else {
      final existing = _contacts[index];
      final tunnelIds = <String>{
        ...existing.tunnelIds,
        ...incoming.tunnelIds,
      }.toList();
      final updated = existing.copyWith(
        nickname: incoming.nickname.trim().isEmpty
            ? existing.nickname
            : incoming.nickname,
        lastSeenAt: incoming.lastSeenAt,
        tunnelIds: tunnelIds,
        avatarBase64: incoming.avatarBase64,
      );
      final copy = [..._contacts];
      copy[index] = updated;
      _contacts = copy;
    }
    _contacts.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    if (mounted) setState(() {});
    unawaited(CgStore.saveContacts(_contacts));
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


  void _syncMonitor() {
    final profile = _profile;
    if (profile == null) return;
    unawaited(
      ChernogramAppMonitor.sync(
        profile: profile,
        tunnels: _tunnels,
        ru: widget.ru,
        onTunnelChanged: _updateTunnel,
        onContactSeen: _rememberContact,
      ),
    );
  }



  Future<void> _openMusicPlayer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMusicPlayerScreen(
          ru: widget.ru,
          tunnels: _tunnels,
        ),
      ),
    );
  }

  Future<void> _openMediaLibrary({String initialFilter = 'all'}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMediaLibraryScreen(
          ru: widget.ru,
          tunnels: _tunnels,
          initialFilter: initialFilter,
          onTunnelsChanged: (updated) {
            _tunnels = updated;
            if (mounted) setState(() {});
            unawaited(CgStore.saveTunnels(_tunnels));
            _syncMonitor();
          },
        ),
      ),
    );
  }


  String _inviteText(CgTunnel tunnel) {
    final deep = 'chernogram://join/${Uri.encodeComponent(tunnel.inviteToken)}';
    final landing = '$_chernogramLanding?v=21&invite=${Uri.encodeQueryComponent(tunnel.inviteToken)}';
    return widget.ru
        ? 'Открой чат в Чернограме: $deep\n\nЕсли приложение не открылось: $landing'
        : 'Open the Chernogram chat: $deep\n\nIf the app did not open: $landing';
  }

  Future<CgTunnel?> _createInviteTunnel(String name) async {
    final profile = _profile;
    if (profile == null) return null;
    final tunnel = CgTunnel(
      id: CgIds.random(18),
      name: name.trim(),
      isPrivate: true,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
    _tunnels = <CgTunnel>[tunnel, ..._tunnels];
    await CgStore.saveTunnels(_tunnels);
    _syncMonitor();
    if (mounted) setState(() {});
    return tunnel;
  }

  Future<void> _inviteFromPhoneBook() async {
    final allowed = await FlutterContacts.requestPermission();
    if (!allowed || !mounted) return;
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (!mounted) return;
    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .76,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final phone = contact.phones.isEmpty
                  ? ''
                  : contact.phones.first.number;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      contact.displayName.trim().isEmpty
                          ? '?'
                          : contact.displayName.trim()[0].toUpperCase(),
                    ),
                  ),
                  title: Text(
                    contact.displayName.trim().isEmpty
                        ? (widget.ru ? 'Без имени' : 'No name')
                        : contact.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: phone.isEmpty ? null : Text(phone),
                  trailing: const Icon(Icons.person_add_alt_1_rounded),
                  onTap: () => Navigator.pop(context, contact),
                ),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null) return;
    final tunnel = await _createInviteTunnel(selected.displayName);
    if (tunnel == null) return;
    await Share.share(_inviteText(tunnel));
    await _openTunnel(tunnel);
  }

  Future<void> _inviteViaMessengers() async {
    final tunnel = await _createInviteTunnel('');
    if (tunnel == null) return;
    await Share.share(_inviteText(tunnel));
    await _openTunnel(tunnel);
  }

  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
    _syncMonitor();
  }

  Future<void> _togglePrivacy() async {
    final next = !_privacyLens;
    await CgStore.savePrivacyLens(next);
    if (mounted) setState(() => _privacyLens = next);
  }

  @override
  void dispose() {
    unawaited(ChernogramAppMonitor.stop());
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(
        body: Center(child: ChernogramLogo(size: 112, withPlate: true)),
      );
    }
    final pages = <Widget>[
      _ChatsHome(
        ru: widget.ru,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        unreadCounts: _unreadCounts,
        onCreate: _createTunnel,
        onScan: _scanQr,
        onOpen: _openTunnel,
      ),
      _ContactsScreen(
        ru: widget.ru,
        contacts: _contacts,
        privacyLens: _privacyLens,
        onOpen: _openContact,
        onInvitePhoneBook: _inviteFromPhoneBook,
        onInviteMessengers: _inviteViaMessengers,
      ),
      CgAgentScreen(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        onCreateTunnel: _createTunnel,
        onTogglePrivacy: _togglePrivacy,
      ),
      _ProfileScreen(
        ru: widget.ru,
        profile: _profile!,
        onSave: _saveProfile,
        onCheckUpdates: widget.onCheckUpdates,
        onChangeLanguage: widget.onChangeLanguage,
      ),
    ];
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: BrandHeader(
          subtitle: widget.ru ? 'ЧАТЫ И ЗВОНКИ' : 'CHATS AND CALLS',
        ),
        actions: [
          GlassIconButton(
            icon: Icons.folder_copy_outlined,
            tooltip: widget.ru ? 'Файлы и медиа' : 'Files and media',
            onPressed: _openMediaLibrary,
          ),
          const SizedBox(width: 10),
          GlassIconButton(
            icon: Icons.queue_music_rounded,
            tooltip: widget.ru ? 'Музыкальный плеер' : 'Music player',
            active: true,
            onPressed: _openMusicPlayer,
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: widget.ru ? 'Меню' : 'Menu',
            onSelected: (value) {
              if (value == 'theme') widget.onToggleTheme();
              if (value == 'language') widget.onChangeLanguage();
              if (value == 'update') widget.onCheckUpdates();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(
                    widget.darkMode ? Icons.light_mode : Icons.dark_mode,
                  ),
                  title: Text(
                    widget.darkMode
                        ? (widget.ru ? 'Светлая тема' : 'Light theme')
                        : (widget.ru ? 'Тёмная тема' : 'Dark theme'),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'language',
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(widget.ru ? 'English' : 'Русский'),
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: const Icon(Icons.system_update_alt_rounded),
                  title: Text(
                    widget.ru
                        ? 'Проверить обновления'
                        : 'Check updates',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum_rounded),
            label: widget.ru ? 'Чаты' : 'Chats',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline_rounded),
            selectedIcon: const Icon(Icons.people_rounded),
            label: widget.ru ? 'Контакты' : 'Contacts',
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: widget.ru ? 'Агент' : 'Agent',
          ),
          NavigationDestination(
            icon: _ProfileNavAvatar(
              profile: _profile!,
              selected: false,
            ),
            selectedIcon: _ProfileNavAvatar(
              profile: _profile!,
              selected: true,
            ),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
        ],
      ),
    );
  }
}


class _ProfileNavAvatar extends StatelessWidget {
  final CgProfile profile;
  final bool selected;

  const _ProfileNavAvatar({required this.profile, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
        width: selected ? 32 : 28,
        height: selected ? 32 : 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: _ProfileAvatar(
          nickname: profile.nickname,
          avatarBase64: profile.avatarBase64,
          size: selected ? 26 : 22,
        ),
      );
}

class _ChatsHome extends StatelessWidget {
  final bool ru;
  final List<CgTunnel> tunnels;
  final bool privacyLens;
  final Map<String, int> unreadCounts;
  final VoidCallback onCreate;
  final VoidCallback onScan;
  final Future<void> Function(CgTunnel tunnel) onOpen;

  const _ChatsHome({
    required this.ru,
    required this.tunnels,
    required this.privacyLens,
    required this.unreadCounts,
    required this.onCreate,
    required this.onScan,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ru ? 'Связь без границ' : 'Connection without borders',
                style:
                    const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                ru
                    ? 'Сообщения, файлы и звонки без vpn'
                    : 'Messages, files and calls without VPN',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .57),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(ru ? 'Новый чат' : 'New chat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('QR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                ru ? 'Чаты' : 'Chats',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${tunnels.length}',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: .45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (tunnels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 50),
            child: Column(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 68,
                  color: scheme.onSurface.withValues(alpha: .18),
                ),
                const SizedBox(height: 12),
                Text(
                  ru ? 'Чатов пока нет' : 'No chats yet',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  ru
                      ? 'Создайте чат или подключитесь по QR.'
                      : 'Create a chat or join with a QR code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .48),
                  ),
                ),
              ],
            ),
          )
        else
          for (final tunnel in tunnels) ...[
            _TunnelTile(
              tunnel: tunnel,
              privacyLens: privacyLens,
              ru: ru,
              unreadCount: unreadCounts[tunnel.id] ?? 0,
              onTap: () => onOpen(tunnel),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _TunnelTile extends StatelessWidget {
  final CgTunnel tunnel;
  final bool privacyLens;
  final bool ru;
  final int unreadCount;
  final VoidCallback onTap;

  const _TunnelTile({
    required this.tunnel,
    required this.privacyLens,
    required this.ru,
    required this.unreadCount,
    required this.onTap,
  });

  String _lastText(CgMessage? message) {
    if (message == null) return ru ? 'Готов к приглашению' : 'Ready to invite';
    if (message.deleted) return ru ? 'Сообщение удалено' : 'Message deleted';
    if (message.type == 'call') {
      final video = message.meta['video'] == true;
      final group = message.meta['group'] == true;
      if (group) {
        return video
            ? (ru ? 'Групповой видеозвонок' : 'Group video call')
            : (ru ? 'Групповой звонок' : 'Group call');
      }
      return video
          ? (ru ? 'Видеозвонок' : 'Video call')
          : (ru ? 'Аудиозвонок' : 'Audio call');
    }
    if (message.attachment != null) {
      return ru
          ? 'Вложение: ${message.attachment!.name}'
          : 'Attachment: ${message.attachment!.name}';
    }
    return message.text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = tunnel.messages.isEmpty ? null : tunnel.messages.last;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _TunnelListAvatar(tunnel: tunnel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            privacyLens ? '••••••••' : tunnel.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Icon(
                          tunnel.isPrivate
                              ? Icons.visibility_off_outlined
                              : Icons.public,
                          size: 16,
                          color: tunnel.isPrivate
                              ? scheme.primary
                              : scheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      privacyLens ? '••••••••••••' : _lastText(last),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .50),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TunnelListAvatar extends StatelessWidget {
  final CgTunnel tunnel;

  const _TunnelListAvatar({required this.tunnel});

  @override
  Widget build(BuildContext context) {
    final raw = tunnel.avatarBase64;
    if (raw != null) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.memory(
            base64Decode(raw),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: tunnel.isPrivate
              ? const [Color(0xFF7C5CFF), Color(0xFF344982)]
              : const [Color(0xFF18B8FF), Color(0xFF4865E8)],
        ),
      ),
      child: Icon(
        tunnel.isPrivate ? Icons.visibility_off_outlined : Icons.public,
        color: Colors.white,
      ),
    );
  }
}

class _ContactsScreen extends StatelessWidget {
  final bool ru;
  final List<CgContact> contacts;
  final bool privacyLens;
  final Future<void> Function(CgContact contact) onOpen;
  final VoidCallback onInvitePhoneBook;
  final VoidCallback onInviteMessengers;

  const _ContactsScreen({
    required this.ru,
    required this.contacts,
    required this.privacyLens,
    required this.onOpen,
    required this.onInvitePhoneBook,
    required this.onInviteMessengers,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
      children: [
        Text(
          ru ? 'Контакты' : 'Contacts',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          ru
              ? 'Здесь сохраняются люди, с которыми вы общались.'
              : 'People you have chatted with are saved here.',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: .56),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onInvitePhoneBook,
              icon: const Icon(Icons.contact_phone_rounded),
              label: Text(ru ? 'Телефонная книга' : 'Phone book'),
            ),
            OutlinedButton.icon(
              onPressed: onInviteMessengers,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(ru ? 'Мессенджеры' : 'Messengers'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 70,
                  color: scheme.onSurface.withValues(alpha: .18),
                ),
                const SizedBox(height: 12),
                Text(
                  ru ? 'Контактов пока нет' : 'No contacts yet',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          )
        else
          for (final contact in contacts)
            Card(
              child: ListTile(
                onTap: () => onOpen(contact),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: _ContactAvatar(contact: contact),
                title: Text(
                  privacyLens ? '••••••••' : '@${contact.nickname}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  privacyLens
                      ? '••••••••'
                      : _lastSeen(contact.lastSeenAt, ru),
                ),
                trailing: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
      ],
    );
  }

  static String _lastSeen(DateTime value, bool ru) {
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return ru ? 'только что' : 'just now';
    if (difference.inHours < 1) {
      return ru
          ? '${difference.inMinutes} мин назад'
          : '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return ru
          ? '${difference.inHours} ч назад'
          : '${difference.inHours} h ago';
    }
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}';
  }
}

class _ContactAvatar extends StatelessWidget {
  final CgContact contact;

  const _ContactAvatar({required this.contact});

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

class _ProfileScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final ValueChanged<CgProfile> onSave;
  final VoidCallback onCheckUpdates;
  final VoidCallback onChangeLanguage;

  const _ProfileScreen({
    required this.ru,
    required this.profile,
    required this.onSave,
    required this.onCheckUpdates,
    required this.onChangeLanguage,
  });

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  late final TextEditingController _nickname =
      TextEditingController(text: widget.profile.nickname);
  String? _avatarBase64;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _avatarBase64 = widget.profile.avatarBase64;
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    setState(() => _avatarBase64 = base64Encode(bytes));
  }

  Future<void> _save() async {
    final nickname = _nickname.text.trim().toLowerCase();
    if (nickname.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru ? 'Минимум 3 символа.' : 'Use at least 3 characters.',
          ),
        ),
      );
      return;
    }
    final forbiddenRoot = _forbiddenNicknameRoot(nickname);
    if (forbiddenRoot != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Этот ник содержит запрещённое слово: $forbiddenRoot'
                : 'This nickname contains a reserved word: $forbiddenRoot',
          ),
        ),
      );
      return;
    }
    widget.onSave(
      widget.profile.copyWith(
        nickname: nickname,
        avatarBase64: _avatarBase64,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru ? 'Профиль сохранён' : 'Profile saved',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _ProfileAvatar(
                    nickname: _nickname.text,
                    avatarBase64: _avatarBase64,
                    size: 108,
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF18B8FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '@${widget.profile.nickname}',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          Center(
            child: Text(
              'ID ${widget.profile.id}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .48),
              ),
            ),
          ),
          if (_version.isNotEmpty) ...[
            const SizedBox(height: 5),
            Center(
              child: Text(
                '${widget.ru ? 'Версия' : 'Version'} $_version',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .48),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _nickname,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.ru ? 'Никнейм' : 'Nickname',
              prefixText: '@',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              widget.ru ? 'Сохранить профиль' : 'Save profile',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onCheckUpdates,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: Text(
              widget.ru ? 'Проверить обновления' : 'Check updates',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onChangeLanguage,
            icon: const Icon(Icons.language),
            label: Text(widget.ru ? 'English' : 'Русский'),
          ),
        ],
      );
}

class _ProfileAvatar extends StatelessWidget {
  final String nickname;
  final String? avatarBase64;
  final double size;

  const _ProfileAvatar({
    required this.nickname,
    required this.avatarBase64,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarBase64 != null) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(avatarBase64!),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    final letter =
        nickname.trim().isEmpty ? '?' : nickname.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C5CFF), Color(0xFF18B8FF)],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .40,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class CgQrScanner extends StatefulWidget {
  final bool ru;

  const CgQrScanner({super.key, required this.ru});

  @override
  State<CgQrScanner> createState() => _CgQrScannerState();
}

class _CgQrScannerState extends State<CgQrScanner> {
  bool _handled = false;

  String? _extract(String value) {
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
    if (CgTunnel.fromInviteToken(value) != null) return value;
    return null;
  }

  void _detect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    final token = _extract(raw);
    if (token == null) return;
    _handled = true;
    Navigator.pop(context, token);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.ru ? 'Сканировать приглашение' : 'Scan invite',
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(onDetect: _detect),
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF18B8FF),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
            ),
          ],
        ),
      );
}
