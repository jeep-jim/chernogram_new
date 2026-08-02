import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_access.dart';
import 'app_monitor.dart';
import 'brand.dart';
import 'chat_media.dart';
import 'chat_screen.dart';
import 'client_settings.dart';
import 'core_models.dart';
import 'device_pairing.dart';
import 'legacy_v16_features.dart';
import 'permission_center.dart';

const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';
const String _androidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';

class ChernogramDataFirst extends StatefulWidget {
  final bool ru;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;

  const ChernogramDataFirst({
    super.key,
    required this.ru,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramDataFirst> createState() => _ChernogramDataFirstState();
}

class _ChernogramDataFirstState extends State<ChernogramDataFirst> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  CgProfile? _profile;
  List<CgTunnel> _tunnels = <CgTunnel>[];
  List<CgContact> _contacts = <CgContact>[];
  bool _loading = true;
  bool _privacyLens = false;
  int _tab = 0;

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
    setState(() {
      _profile = values[0] as CgProfile;
      _tunnels = values[1] as List<CgTunnel>;
      _contacts = values[2] as List<CgContact>;
      _privacyLens = values[3] as bool;
      _loading = false;
    });
    unawaited(_syncMonitor());
    unawaited(_listenLinks());
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
    return invite?.isNotEmpty == true ? invite : null;
  }

  Future<void> _handleUri(Uri uri) async {
    if (await sendRoomToDesktopPairing(
      context: context,
      ru: widget.ru,
      uri: uri,
      tunnels: _tunnels,
    )) {
      return;
    }
    final token = _tokenFromUri(uri);
    if (token != null) await _joinToken(token);
  }

  Future<void> _joinToken(String token) async {
    final tunnel = CgTunnel.fromInviteToken(token);
    if (tunnel == null || !mounted) {
      _showMessage(
        widget.ru
            ? 'Ссылка не содержит приглашение Чернограма.'
            : 'The link does not contain a Chernogram invite.',
      );
      return;
    }
    final existing = _tunnels.indexWhere((item) => item.id == tunnel.id);
    if (existing >= 0) {
      await _openTunnel(_tunnels[existing]);
      return;
    }
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChernogramAvatar(size: 72, seed: tunnel.id),
            const SizedBox(height: 14),
            Text(
              tunnel.displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              tunnel.isPrivate
                  ? (widget.ru
                        ? 'Закрытая комната. Вход по этому приглашению.'
                        : 'Private room. Join with this invite.')
                  : (widget.ru
                        ? 'Открытая комната с общими чатами и файлами.'
                        : 'Public room with shared chats and files.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(widget.ru ? 'Подключиться' : 'Join'),
              ),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _tunnels = [tunnel, ..._tunnels];
      _tab = 0;
    });
    await CgStore.saveTunnels(_tunnels);
    unawaited(_syncMonitor());
    await _openTunnel(tunnel);
  }

  Future<CgTunnel?> _createTunnel({
    String? preferredName,
    bool? preferredPrivate,
  }) async {
    final profile = _profile;
    if (profile == null || !mounted) return null;
    final name = TextEditingController(text: preferredName ?? '');
    var isPrivate = preferredPrivate ?? true;
    final result = await showModalBottomSheet<({String name, bool isPrivate})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            22 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.ru ? 'Новая комната' : 'New room',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.ru
                    ? 'Личная переписка, групповая комната или открытая папка файлов.'
                    : 'Direct chat, group room, or public file space.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .56),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.ru
                      ? 'Название — необязательно'
                      : 'Name — optional',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  side: const WidgetStatePropertyAll(BorderSide.none),
                ),
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
                selected: {isPrivate},
                onSelectionChanged: (value) {
                  setSheetState(() => isPrivate = value.first);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, (
                    name: name.text.trim(),
                    isPrivate: isPrivate,
                  )),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(widget.ru ? 'Создать' : 'Create'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    if (result == null) return null;
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
    unawaited(_syncMonitor());
    return tunnel;
  }

  Future<void> _createAndOpen() async {
    final tunnel = await _createTunnel();
    if (tunnel != null) await _openTunnel(tunnel, autoInvite: true);
  }

  Future<void> _openTunnel(CgTunnel tunnel, {bool autoInvite = false}) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
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
          onForward: _forwardMessage,
          onContactSeen: _rememberContact,
        ),
      ),
    );
  }

  void _updateTunnel(CgTunnel updated) {
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
    final copy = [..._tunnels];
    if (index < 0) {
      copy.insert(0, updated);
    } else {
      copy[index] = updated;
    }
    copy.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
    if (mounted) setState(() => _tunnels = copy);
    unawaited(CgStore.saveTunnels(copy));
    unawaited(_syncMonitor());
  }

  DateTime _lastActivity(CgTunnel tunnel) =>
      tunnel.messages.isEmpty ? tunnel.createdAt : tunnel.messages.last.sentAt;

  void _rememberContact(CgContact incoming) {
    if (incoming.id.isEmpty || incoming.id == _profile?.id) return;
    final index = _contacts.indexWhere((item) => item.id == incoming.id);
    final copy = [..._contacts];
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

  Future<void> _forwardMessage(CgMessage source) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final candidates = _tunnels.toList();
    if (candidates.isEmpty) return;
    final target = await showModalBottomSheet<CgTunnel>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Переслать в чат' : 'Forward to chat',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final tunnel = candidates[index];
                    return ListTile(
                      leading: ChernogramAvatar(
                        size: 42,
                        seed: tunnel.id,
                        avatarBase64: tunnel.avatarBase64,
                      ),
                      title: Text(tunnel.displayName),
                      trailing: const Icon(Icons.forward_rounded),
                      onTap: () => Navigator.pop(context, tunnel),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    final forwarded = CgMessage(
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
    final updated = target.copyWith(messages: [...target.messages, forwarded]);
    _updateTunnel(updated);
    await ChernogramAppMonitor.publishMessage(
      profile: profile,
      tunnel: updated,
      message: forwarded,
    );
    _showMessage(widget.ru ? 'Сообщение переслано.' : 'Message forwarded.');
  }

  Future<void> _openKnownContact(CgContact contact) async {
    for (final id in contact.tunnelIds) {
      final index = _tunnels.indexWhere((item) => item.id == id);
      if (index >= 0) {
        await _openTunnel(_tunnels[index]);
        return;
      }
    }
    final tunnel = await _createTunnel(
      preferredName: contact.nickname,
      preferredPrivate: true,
    );
    if (tunnel != null) await _openTunnel(tunnel, autoInvite: true);
  }

  Future<void> _invitePhoneContact(Contact contact) async {
    final tunnel = await _createTunnel(
      preferredName: contact.displayName,
      preferredPrivate: true,
    );
    if (tunnel == null) return;
    final url =
        '$_landingBase?invite=${Uri.encodeQueryComponent(tunnel.inviteToken)}';
    await Share.share(
      widget.ru
          ? 'Присоединяйся ко мне в Чернограме: $url\n\nЕсли приложения ещё нет, установи его: $_androidInstallUrl'
          : 'Join me on Chernogram: $url\n\nIf the app is not installed yet: $_androidInstallUrl',
      subject: widget.ru ? 'Приглашение в Чернограм' : 'Chernogram invite',
    );
    if (mounted) await _openTunnel(tunnel);
  }

  Future<void> _scanInvite() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => CgInviteQrScanner(ru: widget.ru)),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final uri = Uri.tryParse(raw.trim());
    if (uri != null &&
        await sendRoomToDesktopPairing(
          context: context,
          ru: widget.ru,
          uri: uri,
          tunnels: _tunnels,
        )) {
      return;
    }
    var token = raw.trim();
    if (uri != null) token = _tokenFromUri(uri) ?? token;
    await _joinToken(token);
  }

  Future<void> _openContacts() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ContactHub(
        ru: widget.ru,
        contacts: _contacts,
        onOpenKnown: _openKnownContact,
        onInvitePhone: _invitePhoneContact,
        onCreateRoom: _createAndOpen,
        onScan: _scanInvite,
      ),
    );
  }

  Future<void> _openPrelanding() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => CgPrelandingPlaceholder(ru: widget.ru)),
    );
  }

  Future<void> _restoreIdentity(CgIdentityBundle bundle) async {
    await CgStore.saveProfile(bundle.profile);
    await CgStore.saveTunnels(bundle.tunnels);
    await CgStore.saveContacts(bundle.contacts);
    if (!mounted) return;
    setState(() {
      _profile = bundle.profile;
      _tunnels = bundle.tunnels;
      _contacts = bundle.contacts;
    });
    unawaited(_syncMonitor());
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(body: Center(child: ChernogramLogo(size: 132)));
    }
    final titles = widget.ru
        ? const ['Чаты', 'Файлы', 'Музыка', 'Профиль']
        : const ['Chats', 'Files', 'Music', 'Profile'];
    final pages = <Widget>[
      _ChatsPage(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        contacts: _contacts,
        onOpen: _openTunnel,
        onCreate: _createAndOpen,
        onContacts: _openContacts,
      ),
      _FilesPage(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        onTunnelChanged: _updateTunnel,
        onOpenTunnel: _openTunnel,
        onCreatePublicRoom: () async {
          final tunnel = await _createTunnel(preferredPrivate: false);
          if (tunnel != null) setState(() => _tab = 1);
        },
      ),
      _MusicPage(ru: widget.ru, tunnels: _tunnels),
      _ProfilePage(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        contacts: _contacts,
        privacyLens: _privacyLens,
        onPrivacyChanged: (value) async {
          await CgStore.savePrivacyLens(value);
          if (mounted) setState(() => _privacyLens = value);
        },
        onProfileChanged: (profile) async {
          await CgStore.saveProfile(profile);
          if (mounted) setState(() => _profile = profile);
          unawaited(_syncMonitor());
        },
        onRestore: _restoreIdentity,
        onCheckUpdates: widget.onCheckUpdates,
        onChangeLanguage: widget.onChangeLanguage,
      ),
    ];
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        titleSpacing: 14,
        title: BrandHeader(
          ru: widget.ru,
          subtitle: titles[_tab],
          onTap: _openPrelanding,
        ),
        actions: [
          GlassIconButton(
            icon: widget.darkMode
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            tooltip: widget.ru ? 'Сменить тему' : 'Change theme',
            onPressed: widget.onToggleTheme,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: CgChatPatternBackground(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: widget.ru ? 'Чаты' : 'Chats',
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_copy_outlined),
            label: widget.ru ? 'Файлы' : 'Files',
          ),
          NavigationDestination(
            icon: const Icon(Icons.graphic_eq_rounded),
            label: widget.ru ? 'Музыка' : 'Music',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(ChernogramAppMonitor.stop());
    super.dispose();
  }
}

class _ChatsPage extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final List<CgContact> contacts;
  final Future<void> Function(CgTunnel tunnel) onOpen;
  final VoidCallback onCreate;
  final VoidCallback onContacts;

  const _ChatsPage({
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.contacts,
    required this.onOpen,
    required this.onCreate,
    required this.onContacts,
  });

  @override
  State<_ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<_ChatsPage> {
  final _search = TextEditingController();

  bool _isGroup(CgTunnel tunnel) {
    final authors = tunnel.messages
        .map((message) => message.authorId)
        .where((id) => id.isNotEmpty)
        .toSet();
    authors.add(tunnel.ownerId);
    return authors.length > 2 ||
        tunnel.messages.any((m) => m.meta['group'] == true);
  }

  bool _online(CgTunnel tunnel) {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 55));
    return widget.contacts.any(
      (contact) =>
          contact.tunnelIds.contains(tunnel.id) &&
          contact.lastSeenAt.isAfter(cutoff),
    );
  }

  String _preview(CgTunnel tunnel) {
    if (tunnel.messages.isEmpty) {
      return widget.ru ? 'Комната готова к приглашению' : 'Room is ready';
    }
    final message = tunnel.messages.last;
    if (message.type == 'call') {
      final video = message.meta['video'] == true;
      return video
          ? (widget.ru ? 'Видеозвонок' : 'Video call')
          : (widget.ru ? 'Звонок' : 'Call');
    }
    if (message.attachment != null) return message.attachment!.name;
    return message.deleted
        ? (widget.ru ? 'Сообщение удалено' : 'Message deleted')
        : message.text;
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final tunnels = widget.tunnels.where((tunnel) {
      if (query.isEmpty) return true;
      return tunnel.displayName.toLowerCase().contains(query) ||
          tunnel.messages.any(
            (message) =>
                message.text.toLowerCase().contains(query) ||
                (message.attachment?.name.toLowerCase().contains(query) ??
                    false),
          );
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.ru
                        ? 'Найти чат, сообщение или файл'
                        : 'Find a chat, message, or file',
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
              const SizedBox(width: 9),
              SizedBox.square(
                dimension: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: widget.onContacts,
                  child: const Icon(Icons.person_add_alt_1_rounded),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: tunnels.isEmpty
              ? _EmptyChats(ru: widget.ru, onCreate: widget.onCreate)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 110),
                  itemCount: tunnels.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final tunnel = tunnels[index];
                    final group = _isGroup(tunnel);
                    final online = _online(tunnel);
                    return Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: () => widget.onOpen(tunnel),
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ChernogramAvatar(
                                    size: 48,
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
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            tunnel.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          tunnel.isPrivate
                                              ? Icons.lock_outline_rounded
                                              : Icons.public_rounded,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: .42),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _preview(tunnel),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: .52),
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
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _EmptyChats extends StatelessWidget {
  final bool ru;
  final VoidCallback onCreate;

  const _EmptyChats({required this.ru, required this.onCreate});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 96),
          const SizedBox(height: 17),
          Text(
            ru ? 'Начните с комнаты' : 'Start with a room',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            ru
                ? 'Личный чат, группа или открытое пространство для файлов.'
                : 'Direct chat, group, or public file space.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text(ru ? 'Создать комнату' : 'Create room'),
          ),
        ],
      ),
    ),
  );
}

class _ContactHub extends StatefulWidget {
  final bool ru;
  final List<CgContact> contacts;
  final Future<void> Function(CgContact contact) onOpenKnown;
  final Future<void> Function(Contact contact) onInvitePhone;
  final VoidCallback onCreateRoom;
  final VoidCallback onScan;

  const _ContactHub({
    required this.ru,
    required this.contacts,
    required this.onOpenKnown,
    required this.onInvitePhone,
    required this.onCreateRoom,
    required this.onScan,
  });

  @override
  State<_ContactHub> createState() => _ContactHubState();
}

class _ContactHubState extends State<_ContactHub> {
  List<Contact> _phoneContacts = const [];
  bool _loadingPhone = false;
  int _section = 0;

  Future<void> _loadPhoneContacts() async {
    if (_loadingPhone || _phoneContacts.isNotEmpty) return;
    setState(() => _loadingPhone = true);
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (granted) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
        );
        contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
        if (mounted) setState(() => _phoneContacts = contacts);
      }
    } finally {
      if (mounted) setState(() => _loadingPhone = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .86;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.ru ? 'Новый диалог' : 'New conversation',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _QuickContactAction(
                    icon: Icons.add_comment_rounded,
                    label: widget.ru ? 'Комната' : 'Room',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onCreateRoom();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickContactAction(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onScan();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickContactAction(
                    icon: Icons.contacts_rounded,
                    label: widget.ru ? 'Телефон' : 'Phone',
                    onTap: () {
                      setState(() => _section = 1);
                      _loadPhoneContacts();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: ButtonStyle(
                side: const WidgetStatePropertyAll(BorderSide.none),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(widget.ru ? 'В Чернограме' : 'Chernogram'),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(widget.ru ? 'Телефон' : 'Phone'),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (value) {
                setState(() => _section = value.first);
                if (_section == 1) _loadPhoneContacts();
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _section == 0
                  ? widget.contacts.isEmpty
                        ? Center(
                            child: Text(
                              widget.ru
                                  ? 'Здесь появятся люди из ваших комнат.'
                                  : 'People from your rooms will appear here.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: widget.contacts.length,
                            itemBuilder: (context, index) {
                              final contact = widget.contacts[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                leading: ChernogramAvatar(
                                  size: 46,
                                  seed: contact.id,
                                  avatarBase64: contact.avatarBase64,
                                ),
                                title: Text(
                                  contact.nickname,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  widget.ru
                                      ? 'Открыть диалог'
                                      : 'Open conversation',
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                ),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await widget.onOpenKnown(contact);
                                },
                              );
                            },
                          )
                  : _loadingPhone
                  ? const Center(child: CircularProgressIndicator())
                  : _phoneContacts.isEmpty
                  ? Center(
                      child: Text(
                        widget.ru
                            ? 'Разрешите доступ к контактам, чтобы пригласить человека через любой мессенджер.'
                            : 'Allow contacts access to invite anyone through any messenger.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _phoneContacts.length,
                      itemBuilder: (context, index) {
                        final contact = _phoneContacts[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: ChernogramAvatar(size: 46, seed: contact.id),
                          title: Text(
                            contact.displayName.isEmpty
                                ? (widget.ru ? 'Без имени' : 'Unnamed')
                                : contact.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            widget.ru
                                ? 'Создать чат и отправить приглашение'
                                : 'Create chat and share invite',
                          ),
                          trailing: const Icon(Icons.ios_share_rounded),
                          onTap: () async {
                            Navigator.pop(context);
                            await widget.onInvitePhone(contact);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickContactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickContactAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          children: [
            Icon(icon),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );
}

class _FileEntry {
  final CgTunnel tunnel;
  final CgMessage message;
  final CgAttachment attachment;

  const _FileEntry({
    required this.tunnel,
    required this.message,
    required this.attachment,
  });

  bool get isPublic => !tunnel.isPrivate && message.meta['publicFile'] == true;
}

class _FilesPage extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final ValueChanged<CgTunnel> onTunnelChanged;
  final Future<void> Function(CgTunnel tunnel) onOpenTunnel;
  final VoidCallback onCreatePublicRoom;

  const _FilesPage({
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.onTunnelChanged,
    required this.onOpenTunnel,
    required this.onCreatePublicRoom,
  });

  @override
  State<_FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<_FilesPage> {
  final _search = TextEditingController();
  int _filter = 0;
  bool _busy = false;
  final Set<String> _selectedFileIds = <String>{};

  List<_FileEntry> get _entries {
    final result = <_FileEntry>[];
    for (final tunnel in widget.tunnels) {
      for (final message in tunnel.messages) {
        final attachment = message.attachment;
        if (attachment != null && !message.deleted) {
          result.add(
            _FileEntry(
              tunnel: tunnel,
              message: message,
              attachment: attachment,
            ),
          );
        }
      }
    }
    result.sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return result;
  }

  void _toggleFileSelection(_FileEntry entry) {
    setState(() {
      if (!_selectedFileIds.add(entry.message.id)) {
        _selectedFileIds.remove(entry.message.id);
      }
    });
  }

  List<_FileEntry> _selectedFiles(List<_FileEntry> entries) => entries
      .where((entry) => _selectedFileIds.contains(entry.message.id))
      .toList(growable: false);

  Future<void> _shareSelectedFiles(List<_FileEntry> entries) async {
    final files = <XFile>[];
    for (final entry in _selectedFiles(entries)) {
      final file = await _materialize(entry.attachment);
      if (file != null) files.add(XFile(file.path));
    }
    if (files.isNotEmpty) await Share.shareXFiles(files);
  }

  Future<void> _clearSelectedLocalFiles(List<_FileEntry> entries) async {
    var tunnels = widget.tunnels;
    for (final entry in _selectedFiles(entries)) {
      tunnels = await CgMediaStore.purgeItem(
        tunnels,
        CgMediaItem(
          tunnelId: entry.tunnel.id,
          tunnelName: entry.tunnel.displayName,
          messageId: entry.message.id,
          authorName: entry.message.authorName,
          sentAt: entry.message.sentAt,
          attachment: entry.attachment,
        ),
      );
    }
    for (final tunnel in tunnels) {
      widget.onTunnelChanged(tunnel);
    }
    if (mounted) setState(_selectedFileIds.clear);
  }

  Future<File?> _materialize(CgAttachment attachment) async {
    final path = attachment.localPath;
    if (path != null && await File(path).exists()) return File(path);
    final raw = attachment.dataBase64;
    if (raw == null) return null;
    final directory = await getTemporaryDirectory();
    final safeName = attachment.name.replaceAll(
      RegExp(r'[^A-Za-zА-Яа-я0-9._-]'),
      '_',
    );
    final file = File('${directory.path}/${attachment.id}_$safeName');
    await file.writeAsBytes(base64Decode(raw), flush: true);
    return file;
  }

  Future<void> _openEntry(_FileEntry entry) async {
    final file = await _materialize(entry.attachment);
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Файл пока доступен только на устройстве отправителя.'
                  : 'The file is currently available only on the sender device.',
            ),
          ),
        );
      }
      return;
    }
    await OpenFilex.open(file.path);
  }

  Future<void> _publishFile() async {
    final publicRooms = widget.tunnels
        .where((tunnel) => !tunnel.isPrivate)
        .toList();
    if (publicRooms.isEmpty) {
      final create = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_rounded, size: 50),
              const SizedBox(height: 12),
              Text(
                widget.ru
                    ? 'Нужна открытая комната'
                    : 'A public room is required',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.ru
                    ? 'Общие файлы индексируются внутри открытых комнат, к которым подключён пользователь.'
                    : 'Shared files are indexed inside public rooms joined by the user.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(widget.ru ? 'Создать комнату' : 'Create room'),
                ),
              ),
            ],
          ),
        ),
      );
      if (create == true) widget.onCreatePublicRoom();
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) return;
    if (bytes.length > 20 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'В текущем стабильном транспорте общий файл должен быть до 20 МБ. Большие файлы пойдут отдельным P2P-потоком.'
                  : 'The current stable transport supports shared files up to 20 MB. Larger files will use a separate P2P stream.',
            ),
          ),
        );
      }
      return;
    }
    final room = await showModalBottomSheet<CgTunnel>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.ru ? 'Опубликовать в комнате' : 'Publish in room',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final room in publicRooms)
              ListTile(
                leading: ChernogramAvatar(size: 42, seed: room.id),
                title: Text(room.displayName),
                trailing: const Icon(Icons.arrow_forward_rounded),
                onTap: () => Navigator.pop(context, room),
              ),
          ],
        ),
      ),
    );
    if (room == null) return;
    setState(() => _busy = true);
    try {
      final attachment = CgAttachment(
        id: CgIds.random(20),
        name: picked.name,
        size: bytes.length,
        kind: _kind(picked.name),
        dataBase64: base64Encode(bytes),
        localPath: picked.path,
      );
      final message = CgMessage(
        id: CgIds.random(24),
        authorId: widget.profile.id,
        authorName: widget.profile.nickname,
        text: '',
        sentAt: DateTime.now(),
        type: 'attachment',
        attachment: attachment,
        meta: const {'publicFile': true, 'indexed': true},
      );
      final updated = room.copyWith(messages: [...room.messages, message]);
      widget.onTunnelChanged(updated);
      await ChernogramAppMonitor.publishMessage(
        profile: widget.profile,
        tunnel: updated,
        message: message,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Файл добавлен в общий индекс комнаты.'
                  : 'The file was added to the room public index.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kind(String name) {
    final ext = name.split('.').last.toLowerCase();
    if ({'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'}.contains(ext))
      return 'image';
    if ({'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'}.contains(ext))
      return 'audio';
    if ({'mp4', 'mov', 'mkv', 'webm'}.contains(ext)) return 'video';
    if ({'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) return 'archive';
    return 'document';
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final entries = _entries.where((entry) {
      if (_filter == 1 && !entry.isPublic) return false;
      if (_filter == 2 && entry.isPublic) return false;
      if (query.isEmpty) return true;
      return entry.attachment.name.toLowerCase().contains(query) ||
          entry.tunnel.displayName.toLowerCase().contains(query) ||
          entry.message.authorName.toLowerCase().contains(query);
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: widget.ru
                  ? 'Найти общий файл по имени или комнате'
                  : 'Find a shared file by name or room',
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  children: [
                    ChoiceChip(
                      label: Text(widget.ru ? 'Все' : 'All'),
                      selected: _filter == 0,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = 0),
                    ),
                    ChoiceChip(
                      label: Text(widget.ru ? 'Общие' : 'Public'),
                      selected: _filter == 1,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = 1),
                    ),
                    ChoiceChip(
                      label: Text(widget.ru ? 'В чатах' : 'Chats'),
                      selected: _filter == 2,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = 2),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: _busy ? null : _publishFile,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded),
              ),
            ],
          ),
        ),
        if (_selectedFileIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => setState(_selectedFileIds.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      widget.ru
                          ? 'Выбрано: ${_selectedFileIds.length}'
                          : 'Selected: ${_selectedFileIds.length}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.ru ? 'Отправить' : 'Share',
                    onPressed: () => _shareSelectedFiles(entries),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  IconButton(
                    tooltip: widget.ru
                        ? 'Удалить локальные копии'
                        : 'Remove local copies',
                    onPressed: () => _clearSelectedLocalFiles(entries),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_open_rounded, size: 70),
                        const SizedBox(height: 12),
                        Text(
                          widget.ru
                              ? 'Файлы появятся здесь'
                              : 'Files will appear here',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.ru
                              ? 'Файлы из всех комнат собраны в одном поиске.'
                              : 'Files from every room are collected into one search.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 110),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final selected = _selectedFileIds.contains(
                      entry.message.id,
                    );
                    return Material(
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .14)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: () => _selectedFileIds.isEmpty
                            ? _openEntry(entry)
                            : _toggleFileSelection(entry),
                        onLongPress: () => _toggleFileSelection(entry),
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .13),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(_fileIcon(entry.attachment.kind)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.attachment.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${entry.tunnel.displayName} • ${_fileSize(entry.attachment.size)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: .50),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (entry.isPublic)
                                const Icon(Icons.public_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _fileIcon(String kind) => switch (kind) {
    'image' => Icons.image_outlined,
    'audio' => Icons.audio_file_outlined,
    'video' => Icons.video_file_outlined,
    'archive' => Icons.folder_zip_outlined,
    _ => Icons.description_outlined,
  };

  String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _MusicEntry {
  final CgTunnel tunnel;
  final CgAttachment attachment;

  const _MusicEntry({required this.tunnel, required this.attachment});
}

class _MusicPage extends StatefulWidget {
  final bool ru;
  final List<CgTunnel> tunnels;

  const _MusicPage({required this.ru, required this.tunnels});

  @override
  State<_MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<_MusicPage> {
  static const _tokenKey = 'cg_audd_token_v1';

  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<PlayerState>? _playerSubscription;
  _MusicEntry? _current;
  bool _recognizing = false;
  String? _recognitionResult;

  List<_MusicEntry> get _tracks {
    final tracks = <_MusicEntry>[];
    for (final tunnel in widget.tunnels) {
      for (final message in tunnel.messages) {
        final attachment = message.attachment;
        if (!message.deleted && attachment?.kind == 'audio') {
          tracks.add(_MusicEntry(tunnel: tunnel, attachment: attachment!));
        }
      }
    }
    return tracks;
  }

  @override
  void initState() {
    super.initState();
    _playerSubscription = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<File?> _trackFile(CgAttachment attachment) =>
      CgMediaStore.ensureFile(attachment);

  Future<void> _play(_MusicEntry entry) async {
    final file = await _trackFile(entry.attachment);
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Аудиофайл ещё не загружен на устройство.'
                  : 'The audio file is not downloaded to this device yet.',
            ),
          ),
        );
      }
      return;
    }
    try {
      if (_current?.attachment.id == entry.attachment.id) {
        if (_player.playing) {
          await _player.pause();
        } else {
          unawaited(_player.play());
        }
        return;
      }
      await _player.setAudioSource(AudioSource.uri(Uri.file(file.path)));
      if (mounted) setState(() => _current = entry);
      unawaited(_player.play());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Не удалось воспроизвести файл: $error'
                  : 'Playback failed: $error',
            ),
          ),
        );
      }
    }
  }

  Future<String?> _recognitionToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_tokenKey)?.trim();
    if (existing?.isNotEmpty == true) return existing;
    if (!mounted) return null;
    final controller = TextEditingController();
    final token = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          22 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.ru ? 'Распознавание музыки' : 'Music recognition',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              widget.ru
                  ? 'Для реального поиска используется токен сервиса распознавания. Он хранится только на устройстве.'
                  : 'Real recognition uses a service token stored only on this device.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'AudD API token',
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(widget.ru ? 'Сохранить' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (token?.isNotEmpty == true) {
      await prefs.setString(_tokenKey, token!);
      return token;
    }
    return null;
  }

  Future<void> _recognize() async {
    if (_recognizing) return;
    final token = await _recognitionToken();
    if (token == null) return;
    final permission = await _recorder.hasPermission();
    if (!permission || !mounted) return;
    setState(() {
      _recognizing = true;
      _recognitionResult = widget.ru ? 'Слушаю…' : 'Listening…';
    });
    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/recognition_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      await Future<void>.delayed(const Duration(seconds: 12));
      final recordedPath = await _recorder.stop();
      if (recordedPath == null) throw StateError('Recording was not created');
      final request =
          http.MultipartRequest('POST', Uri.parse('https://api.audd.io/'))
            ..fields['api_token'] = token
            ..fields['return'] = 'apple_music,spotify'
            ..files.add(
              await http.MultipartFile.fromPath('file', recordedPath),
            );
      final response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        throw HttpException('Recognition HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      final result = decoded is Map ? decoded['result'] : null;
      if (result is Map) {
        final artist = result['artist']?.toString() ?? '';
        final title = result['title']?.toString() ?? '';
        setState(() {
          _recognitionResult = artist.isEmpty && title.isEmpty
              ? (widget.ru ? 'Трек не найден' : 'Track not found')
              : '$artist — $title';
        });
      } else {
        setState(() {
          _recognitionResult = widget.ru ? 'Трек не найден' : 'Track not found';
        });
      }
    } catch (error) {
      await _recorder.stop();
      if (mounted) {
        setState(() {
          _recognitionResult = widget.ru
              ? 'Не удалось распознать: $error'
              : 'Recognition failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final playing = _player.playing;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              ChernogramEqualizerLogo(
                size: 112,
                active: playing || _recognizing,
              ),
              const SizedBox(height: 12),
              Text(
                _current?.attachment.name ??
                    (widget.ru ? 'Музыка Чернограма' : 'Chernogram Music'),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_current != null) ...[
                const SizedBox(height: 3),
                Text(
                  _current!.tunnel.displayName,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .52),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final total = _player.duration ?? Duration.zero;
                  final max = total.inMilliseconds <= 0
                      ? 1.0
                      : total.inMilliseconds.toDouble();
                  final value = position.inMilliseconds
                      .clamp(0, max.toInt())
                      .toDouble();
                  return Slider(
                    value: value,
                    max: max,
                    onChanged: _current == null
                        ? null
                        : (next) => _player.seek(
                            Duration(milliseconds: next.round()),
                          ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: _current == null
                        ? null
                        : () => _player.seek(Duration.zero),
                    icon: const Icon(Icons.replay_rounded),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    iconSize: 34,
                    onPressed: _current == null
                        ? (tracks.isEmpty ? null : () => _play(tracks.first))
                        : () async {
                            if (playing) {
                              await _player.pause();
                            } else {
                              unawaited(_player.play());
                            }
                          },
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: _recognizing ? null : _recognize,
                    tooltip: widget.ru ? 'Что играет?' : 'What is playing?',
                    icon: _recognizing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.hearing_rounded),
                  ),
                ],
              ),
              if (_recognitionResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _recognitionResult!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.ru ? 'Аудио из всех комнат' : 'Audio from every room',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 9),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 38),
            child: Text(
              widget.ru
                  ? 'Отправленные аудиофайлы автоматически появятся здесь.'
                  : 'Shared audio files will automatically appear here.',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final track in tracks) ...[
            Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                leading: ChernogramAvatar(size: 44, seed: track.attachment.id),
                title: Text(
                  track.attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(track.tunnel.displayName),
                trailing: Icon(
                  _current?.attachment.id == track.attachment.id && playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                onTap: () => _play(track),
              ),
            ),
            const SizedBox(height: 7),
          ],
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_playerSubscription?.cancel());
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

class _ProfilePage extends StatelessWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final List<CgContact> contacts;
  final bool privacyLens;
  final ValueChanged<bool> onPrivacyChanged;
  final ValueChanged<CgProfile> onProfileChanged;
  final ValueChanged<CgIdentityBundle> onRestore;
  final VoidCallback onCheckUpdates;
  final VoidCallback onChangeLanguage;

  const _ProfilePage({
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.contacts,
    required this.privacyLens,
    required this.onPrivacyChanged,
    required this.onProfileChanged,
    required this.onRestore,
    required this.onCheckUpdates,
    required this.onChangeLanguage,
  });

  Future<void> _editProfile(BuildContext context) async {
    final controller = TextEditingController(text: profile.nickname);
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          22 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: ru ? 'Имя в Чернограме' : 'Chernogram name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(ru ? 'Сохранить' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value?.isNotEmpty == true)
      onProfileChanged(profile.copyWith(nickname: value));
  }

  Future<void> _security(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SecuritySheet(
        ru: ru,
        profile: profile,
        tunnels: tunnels,
        contacts: contacts,
        onRestore: onRestore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
    children: [
      GlassPanel(
        child: Row(
          children: [
            ChernogramAvatar(
              size: 66,
              seed: profile.id,
              avatarBase64: profile.avatarBase64,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.nickname,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID ${profile.id}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .48),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _editProfile(context),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          value: privacyLens,
          onChanged: onPrivacyChanged,
          secondary: Icon(
            privacyLens
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          title: Text(
            ru ? 'Приватный экран' : 'Privacy screen',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            ru
                ? 'Скрывает имена и текст сообщений, не отключая связь.'
                : 'Hides names and message text without disconnecting.',
          ),
        ),
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.admin_panel_settings_outlined,
        title: ru ? 'Разрешения и приватность' : 'Permissions and privacy',
        subtitle: ru
            ? 'Уведомления, микрофон, камера, контакты, файлы и фон.'
            : 'Notifications, microphone, camera, contacts, files and background.',
        onTap: () => CgPermissionCenter.open(context, ru: ru),
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.privacy_tip_outlined,
        title: ru ? 'Приватность' : 'Privacy',
        subtitle: ru
            ? 'Номер телефона, активность, звонки, группы и отчёты о прочтении.'
            : 'Phone number, activity, calls, groups and read receipts.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16PrivacyScreen(ru: ru),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.devices_rounded,
        title: ru ? 'Связанные устройства' : 'Linked devices',
        subtitle: ru
            ? 'Один профиль на телефонах и Windows.'
            : 'One profile across phones and Windows.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16TwoDevicesScreen(ru: ru, profile: profile),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.phonelink_lock_rounded,
        title: ru ? 'Активные сессии' : 'Active sessions',
        subtitle: ru
            ? 'Устройства, где сейчас открыт ваш аккаунт.'
            : 'Devices where your account is currently open.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16SessionsScreen(ru: ru, profile: profile),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.contacts_outlined,
        title: ru ? 'Системные контакты' : 'System contacts',
        subtitle: ru
            ? 'Телефонная книга и приглашения в Чернограм.'
            : 'Phone book and Chernogram invites.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16SystemContactsScreen(ru: ru),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.install_mobile_rounded,
        title: ru ? 'Поделиться приложением' : 'Share the app',
        subtitle: ru
            ? 'QR-код и прямая ссылка на актуальную Android-версию.'
            : 'QR code and direct link to the current Android version.',
        onTap: () => showChernogramInstallShare(context, ru: ru),
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.account_circle_outlined,
        title: ru ? 'Аккаунт и устройство' : 'Account and device',
        subtitle: ru
            ? 'Устойчивый ID устройства и восстановление после переустановки.'
            : 'Stable device ID and reinstall recovery.',
        onTap: () => showDeviceAccountSheet(context, ru: ru, profile: profile),
      ),
      const SizedBox(height: 8),
      if (Platform.isAndroid) ...[
        _ProfileAction(
          icon: Icons.notifications_active_outlined,
          title: ru ? 'Всегда на связи' : 'Always connected',
          subtitle: ru
              ? 'Сообщения и звонки при свёрнутом или закрытом окне.'
              : 'Messages and calls while the window is minimized or closed.',
          onTap: () => showBackgroundConnectionSettings(context, ru: ru),
        ),
        const SizedBox(height: 8),
      ],
      _ProfileAction(
        icon: Icons.fingerprint_rounded,
        title: ru ? 'Доступ и перенос аккаунта' : 'Access and account transfer',
        subtitle: ru
            ? 'PIN, отпечаток или лицо и зашифрованный код восстановления.'
            : 'PIN, biometrics, and an encrypted recovery code.',
        onTap: () => _security(context),
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.system_update_alt_rounded,
        title: ru ? 'Проверить обновления' : 'Check updates',
        subtitle: ru
            ? 'Обновления Android устанавливаются прямо из приложения.'
            : 'Android updates install directly from the app.',
        onTap: onCheckUpdates,
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.language_rounded,
        title: ru ? 'English' : 'Русский',
        subtitle: ru
            ? 'Сменить язык интерфейса.'
            : 'Change interface language.',
        onTap: onChangeLanguage,
      ),
      const SizedBox(height: 18),
      Text(
        ru ? 'О приложении' : 'About',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 8),
      Text(
        ru
            ? 'Чаты, звонки и передача файлов без рекламы и лишних разделов.'
            : 'Chats, calls, and file exchange without ads or unnecessary sections.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .62),
          height: 1.45,
        ),
      ),
    ],
  );
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(22),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: onTap,
    ),
  );
}

class _SecuritySheet extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final List<CgContact> contacts;
  final ValueChanged<CgIdentityBundle> onRestore;

  const _SecuritySheet({
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.contacts,
    required this.onRestore,
  });

  @override
  State<_SecuritySheet> createState() => _SecuritySheetState();
}

class _SecuritySheetState extends State<_SecuritySheet> {
  bool _busy = false;

  Future<String?> _password({required bool recovery}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          recovery
              ? (widget.ru ? 'Пароль восстановления' : 'Recovery password')
              : 'PIN',
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: recovery ? TextInputType.text : TextInputType.number,
          decoration: InputDecoration(
            hintText: recovery ? '6+ symbols' : '4+ digits',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(widget.ru ? 'Продолжить' : 'Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _setPin() async {
    final pin = await _password(recovery: false);
    if (pin == null) return;
    setState(() => _busy = true);
    try {
      await CgAccountVault.setPin(pin);
      _toast(widget.ru ? 'PIN установлен.' : 'PIN enabled.');
    } catch (error) {
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableBiometric() async {
    setState(() => _busy = true);
    try {
      final available = await CgAccountVault.biometricsAvailable();
      if (!available) {
        _toast(
          widget.ru
              ? 'На устройстве не настроен отпечаток или лицо.'
              : 'No fingerprint or face is enrolled on this device.',
        );
        return;
      }
      final verified = await CgAccountVault.authenticateBiometric(
        ru: widget.ru,
      );
      if (verified) {
        await CgAccountVault.setBiometricEnabled(true);
        _toast(widget.ru ? 'Биометрия включена.' : 'Biometrics enabled.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final password = await _password(recovery: true);
    if (password == null) return;
    setState(() => _busy = true);
    try {
      final code = await CgAccountVault.exportIdentity(
        profile: widget.profile,
        tunnels: widget.tunnels,
        contacts: widget.contacts,
        password: password,
      );
      await Share.share(
        code,
        subject: widget.ru
            ? 'Код восстановления Чернограма'
            : 'Chernogram recovery code',
      );
    } catch (error) {
      _toast(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final code = TextEditingController();
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.ru ? 'Войти на этом устройстве' : 'Sign in on this device',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: widget.ru
                      ? 'Код Chernogram ID'
                      : 'Chernogram ID code',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.ru
                      ? 'Пароль восстановления'
                      : 'Recovery password',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Восстановить' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      code.dispose();
      password.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final bundle = await CgAccountVault.importIdentity(
        code: code.text,
        password: password.text,
      );
      widget.onRestore(bundle);
      _toast(
        widget.ru ? 'Chernogram ID восстановлен.' : 'Chernogram ID restored.',
      );
    } catch (error) {
      _toast(
        widget.ru
            ? 'Не удалось восстановить: $error'
            : 'Restore failed: $error',
      );
    } finally {
      code.dispose();
      password.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .82,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          widget.ru ? 'Доступ к Chernogram ID' : 'Chernogram ID access',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 7),
        Text(
          widget.ru
              ? 'Аккаунт остаётся локальным. Для другого устройства используется зашифрованный переносимый код, а на каждом устройстве — свой PIN или биометрия.'
              : 'The account remains local. A portable encrypted code moves it to another device, while each device uses its own PIN or biometrics.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .60),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _ProfileAction(
          icon: Icons.pin_rounded,
          title: widget.ru ? 'Установить PIN' : 'Set PIN',
          subtitle: widget.ru
              ? 'Запрашивается при запуске приложения.'
              : 'Requested when the app starts.',
          onTap: _busy ? () {} : _setPin,
        ),
        const SizedBox(height: 8),
        _ProfileAction(
          icon: Icons.fingerprint_rounded,
          title: widget.ru
              ? 'Включить отпечаток или лицо'
              : 'Enable fingerprint or face',
          subtitle: widget.ru
              ? 'Проверка выполняется системой Android.'
              : 'Authentication is handled by Android.',
          onTap: _busy ? () {} : _enableBiometric,
        ),
        const SizedBox(height: 8),
        _ProfileAction(
          icon: Icons.key_rounded,
          title: widget.ru
              ? 'Создать код восстановления'
              : 'Create recovery code',
          subtitle: widget.ru
              ? 'Шифрует профиль, комнаты и контакты вашим паролем.'
              : 'Encrypts profile, rooms, and contacts with your password.',
          onTap: _busy ? () {} : _export,
        ),
        const SizedBox(height: 8),
        _ProfileAction(
          icon: Icons.login_rounded,
          title: widget.ru ? 'Войти по коду' : 'Sign in with code',
          subtitle: widget.ru
              ? 'Восстановить тот же ID на другом устройстве.'
              : 'Restore the same ID on another device.',
          onTap: _busy ? () {} : _import,
        ),
        if (_busy) ...[
          const SizedBox(height: 18),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    ),
  );
}

class CgPrelandingPlaceholder extends StatelessWidget {
  final bool ru;

  const CgPrelandingPlaceholder({super.key, required this.ru});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassPanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const ChernogramLogo(size: 132),
                  const SizedBox(height: 18),
                  Text(
                    ru ? 'Что такое Чернограм' : 'What is Chernogram',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ru
                        ? 'Чернограм объединяет быстрые чаты, звонки и передачу данных между устройствами.'
                        : 'Chernogram combines fast chats, calls, and direct data transfer between devices.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class CgInviteQrScanner extends StatefulWidget {
  final bool ru;

  const CgInviteQrScanner({super.key, required this.ru});

  @override
  State<CgInviteQrScanner> createState() => _CgInviteQrScannerState();
}

class _CgInviteQrScannerState extends State<CgInviteQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  void _detect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.pop(context, value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.ru ? 'Сканировать приглашение' : 'Scan invite'),
      actions: [
        IconButton(
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_rounded),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _detect),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 252,
              height: 252,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
