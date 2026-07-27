import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing2/qrcode.dart';

import 'agent_screen.dart';
import 'brand.dart';
import 'chat_media.dart';
import 'chat_screen.dart';
import 'core_models.dart';
import 'music_player.dart';
import 'internet_core.dart';

String _encodeStoredJson(Object value) => jsonEncode(value);

Future<void> _saveTunnelsFast(List<CgTunnel> tunnels) async {
  final payload = tunnels.map((item) => item.toJson()).toList(growable: false);
  final encoded = await compute(_encodeStoredJson, payload);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(CgStore.tunnelsKey, encoded);
}

Future<void> _saveContactsFast(List<CgContact> contacts) async {
  final payload = contacts.map((item) => item.toJson()).toList(growable: false);
  final encoded = await compute(_encodeStoredJson, payload);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(CgStore.contactsKey, encoded);
}

Future<String?> _decodeQrImage(Uint8List bytes) {
  return compute(_decodeQrImageInBackground, bytes);
}

String? _decodeQrImageInBackground(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = img.bakeOrientation(decoded);

  for (final order in <img.ChannelOrder>[
    img.ChannelOrder.rgba,
    img.ChannelOrder.abgr,
  ]) {
    final pixels = image
        .convert(numChannels: 4)
        .getBytes(order: order)
        .buffer
        .asInt32List();
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    for (final luminance in <LuminanceSource>[source, source.invert()]) {
      for (final hybrid in <bool>[true, false]) {
        try {
          final bitmap = BinaryBitmap(
            hybrid
                ? HybridBinarizer(luminance)
                : GlobalHistogramBinarizer(luminance),
          );
          final value = QRCodeReader().decode(bitmap).text.trim();
          if (value.isNotEmpty) return value;
        } catch (_) {
          // Try another decoder variant.
        }
      }
    }
  }
  return null;
}

class ChernogramV12 extends StatefulWidget {
  final bool ru;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;

  const ChernogramV12({
    super.key,
    required this.ru,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramV12> createState() => _ChernogramV12State();
}

class _ChernogramV12State extends State<ChernogramV12> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  Timer? _saveTunnelsTimer;
  Timer? _saveContactsTimer;
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
    final values = await Future.wait<Object>([
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
    await _listenLinks();
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
    return invite == null || invite.isEmpty ? null : invite;
  }

  Future<void> _handleUri(Uri uri) async {
    final token = _tokenFromUri(uri);
    if (token != null) await _joinToken(token);
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

    final existing = _tunnels.indexWhere((item) => item.id == tunnel.id);
    if (existing >= 0) {
      await _openTunnel(_tunnels[existing]);
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
          '${tunnel.displayName}\n\n${widget.ru ? 'Чат, файлы и звонки работают через интернет.' : 'Chat, files and calls work over the internet.'}',
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
    await _saveTunnelsFast(_tunnels);
    await _openTunnel(tunnel);
  }

  Future<void> _scanQr() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _V12QrScanner(ru: widget.ru)),
    );
    if (token != null) await _joinToken(token);
  }

  Future<void> _openMediaLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMediaLibraryScreen(
          ru: widget.ru,
          tunnels: _tunnels,
          onTunnelsChanged: (updated) {
            _tunnels = List<CgTunnel>.from(updated);
            if (mounted) setState(() {});
            final snapshot = List<CgTunnel>.from(_tunnels);
            unawaited(_saveTunnelsFast(snapshot));
          },
        ),
      ),
    );
  }

  Future<void> _openMusicPlayer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMusicPlayerScreen(ru: widget.ru, tunnels: _tunnels),
      ),
    );
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
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.ru
                        ? 'Название — необязательно'
                        : 'Name — optional',
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
                    isPrivate ? Icons.visibility_off_outlined : Icons.public,
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
                              : 'Join only with a secret link or QR.')
                        : (widget.ru
                              ? 'Ссылку можно свободно пересылать.'
                              : 'The invite can be freely forwarded.'),
                  ),
                  onChanged: (value) => setSheetState(() => isPrivate = value),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, (
                      name: name.text.trim(),
                      isPrivate: isPrivate,
                    )),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      widget.ru ? 'Создать и пригласить' : 'Create and invite',
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
    await _saveTunnelsFast(_tunnels);
    await _openTunnel(tunnel, autoInvite: true);
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
    copy.sort((a, b) {
      final aTime = a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
      final bTime = b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
      return bTime.compareTo(aTime);
    });
    _tunnels = copy;
    if (mounted) setState(() {});
    _saveTunnelsTimer?.cancel();
    final snapshot = List<CgTunnel>.from(_tunnels);
    _saveTunnelsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveTunnelsFast(snapshot));
    });
  }

  void _rememberContact(CgContact incoming) {
    if (incoming.id.isEmpty || incoming.id == _profile?.id) return;
    final index = _contacts.indexWhere((item) => item.id == incoming.id);
    if (index < 0) {
      _contacts = [incoming, ..._contacts];
    } else {
      final existing = _contacts[index];
      final updated = existing.copyWith(
        nickname: incoming.nickname.trim().isEmpty
            ? existing.nickname
            : incoming.nickname,
        lastSeenAt: incoming.lastSeenAt,
        tunnelIds: <String>{
          ...existing.tunnelIds,
          ...incoming.tunnelIds,
        }.toList(),
        avatarBase64: incoming.avatarBase64,
      );
      final copy = [..._contacts];
      copy[index] = updated;
      _contacts = copy;
    }
    _contacts.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    if (mounted) setState(() {});
    _saveContactsTimer?.cancel();
    final snapshot = List<CgContact>.from(_contacts);
    _saveContactsTimer = Timer(const Duration(milliseconds: 350), () {
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

  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _togglePrivacy() async {
    final next = !_privacyLens;
    await CgStore.savePrivacyLens(next);
    if (mounted) setState(() => _privacyLens = next);
  }

  @override
  void dispose() {
    _saveTunnelsTimer?.cancel();
    _saveContactsTimer?.cancel();
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
      _V12ChatsHome(
        ru: widget.ru,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        onCreate: _createTunnel,
        onScan: _scanQr,
        onOpen: _openTunnel,
      ),
      _V12ContactsScreen(
        ru: widget.ru,
        contacts: _contacts,
        privacyLens: _privacyLens,
        onOpen: _openContact,
      ),
      CgAgentScreen(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        onCreateTunnel: _createTunnel,
        onTogglePrivacy: _togglePrivacy,
      ),
      _V12ProfileScreen(
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
                    widget.ru ? 'Проверить обновления' : 'Check updates',
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
            icon: _V12ProfileAvatar(
              nickname: _profile!.nickname,
              avatarBase64: _profile!.avatarBase64,
              size: 25,
            ),
            selectedIcon: _V12ProfileAvatar(
              nickname: _profile!.nickname,
              avatarBase64: _profile!.avatarBase64,
              size: 29,
            ),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _FastChatHost extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final CgTunnel tunnel;
  final bool privacyLens;
  final bool autoInvite;
  final ValueChanged<CgTunnel> onChanged;
  final ValueChanged<CgContact> onContactSeen;

  const _FastChatHost({
    required this.ru,
    required this.profile,
    required this.tunnel,
    required this.privacyLens,
    required this.autoInvite,
    required this.onChanged,
    required this.onContactSeen,
  });

  @override
  State<_FastChatHost> createState() => _FastChatHostState();
}

class _FastChatHostState extends State<_FastChatHost> {
  bool _showChat = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (InternetRelay.session(widget.tunnel.id) == null) {
        unawaited(
          InternetRelay.open(
            tunnelId: widget.tunnel.id,
            secret: widget.tunnel.secret,
            profileId: widget.profile.id,
            nickname: widget.profile.nickname,
            history: const <Map<String, dynamic>>[],
          ),
        );
      }
      setState(() => _showChat = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showChat) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: widget.ru ? 'Назад' : 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            widget.privacyLens ? '••••••••' : widget.tunnel.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: const Center(child: ChernogramLogo(size: 82, withPlate: true)),
      );
    }

    return Stack(
      children: [
        CgChatScreen(
          ru: widget.ru,
          profile: widget.profile,
          tunnel: widget.tunnel,
          privacyLens: widget.privacyLens,
          autoInvite: widget.autoInvite,
          onChanged: widget.onChanged,
          onContactSeen: widget.onContactSeen,
        ),
        Positioned(
          left: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: 58,
              height: kToolbarHeight,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: IconButton(
                  tooltip: widget.ru ? 'Назад' : 'Back',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _V12ChatsHome extends StatelessWidget {
  final bool ru;
  final List<CgTunnel> tunnels;
  final bool privacyLens;
  final VoidCallback onCreate;
  final VoidCallback onScan;
  final Future<void> Function(CgTunnel tunnel) onOpen;

  const _V12ChatsHome({
    required this.ru,
    required this.tunnels,
    required this.privacyLens,
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
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                ru
                    ? 'Сообщения, файлы и звонки между разными городами и сетями.'
                    : 'Messages, files and calls across cities and networks.',
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${tunnels.length}',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: .45)),
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
                ),
              ],
            ),
          )
        else
          for (final tunnel in tunnels) ...[
            Card(
              child: InkWell(
                onTap: () => onOpen(tunnel),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _V12TunnelAvatar(tunnel: tunnel, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              privacyLens ? '••••••••' : tunnel.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              privacyLens
                                  ? '••••••••••••'
                                  : _lastMessage(tunnel, ru),
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
                      Icon(
                        tunnel.isPrivate
                            ? Icons.visibility_off_outlined
                            : Icons.public,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  static String _lastMessage(CgTunnel tunnel, bool ru) {
    if (tunnel.messages.isEmpty) {
      return ru ? 'Готов к приглашению' : 'Ready to invite';
    }
    final message = tunnel.messages.last;
    if (message.deleted) return ru ? 'Сообщение удалено' : 'Message deleted';
    if (message.type == 'call') return ru ? 'Звонок' : 'Call';
    if (message.attachment != null) {
      return ru
          ? 'Вложение: ${message.attachment!.name}'
          : 'Attachment: ${message.attachment!.name}';
    }
    return message.text;
  }
}

class _V12TunnelAvatar extends StatelessWidget {
  final CgTunnel tunnel;
  final double size;

  const _V12TunnelAvatar({required this.tunnel, required this.size});

  @override
  Widget build(BuildContext context) {
    final raw = tunnel.avatarBase64;
    if (raw != null) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * .32),
          child: Image.memory(
            base64Decode(raw),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(
          colors: tunnel.isPrivate
              ? const [Color(0xFF795DFF), Color(0xFF27396F)]
              : const [Color(0xFF00A9D9), Color(0xFF3867E8)],
        ),
      ),
      child: Icon(
        tunnel.isPrivate ? Icons.visibility_off_outlined : Icons.public,
        color: Colors.white,
      ),
    );
  }
}

class _V12ContactsScreen extends StatelessWidget {
  final bool ru;
  final List<CgContact> contacts;
  final bool privacyLens;
  final Future<void> Function(CgContact contact) onOpen;

  const _V12ContactsScreen({
    required this.ru,
    required this.contacts,
    required this.privacyLens,
    required this.onOpen,
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
          style: TextStyle(color: scheme.onSurface.withValues(alpha: .56)),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: _V12ContactAvatar(contact: contact),
                title: Text(
                  privacyLens ? '••••••••' : '@${contact.nickname}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  privacyLens ? '••••••••' : _lastSeen(contact.lastSeenAt, ru),
                ),
                trailing: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
      ],
    );
  }

  static String _lastSeen(DateTime value, bool ru) {
    final difference = DateTime.now().difference(value);
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

class _V12ContactAvatar extends StatelessWidget {
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

class _V12ProfileScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final ValueChanged<CgProfile> onSave;
  final VoidCallback onCheckUpdates;
  final VoidCallback onChangeLanguage;

  const _V12ProfileScreen({
    required this.ru,
    required this.profile,
    required this.onSave,
    required this.onCheckUpdates,
    required this.onChangeLanguage,
  });

  @override
  State<_V12ProfileScreen> createState() => _V12ProfileScreenState();
}

class _V12ProfileScreenState extends State<_V12ProfileScreen> {
  late final TextEditingController _nickname = TextEditingController(
    text: widget.profile.nickname,
  );
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
    if (bytes != null) setState(() => _avatarBase64 = base64Encode(bytes));
  }

  void _save() {
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
    widget.onSave(
      widget.profile.copyWith(nickname: nickname, avatarBase64: _avatarBase64),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.ru ? 'Профиль сохранён' : 'Profile saved')),
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
          child: _V12ProfileAvatar(
            nickname: _nickname.text,
            avatarBase64: _avatarBase64,
            size: 108,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: Text(
          '@${widget.profile.nickname}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
      Center(
        child: Text(
          'ID ${widget.profile.id}',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .48),
          ),
        ),
      ),
      if (_version.isNotEmpty)
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
        label: Text(widget.ru ? 'Сохранить профиль' : 'Save profile'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: widget.onCheckUpdates,
        icon: const Icon(Icons.system_update_alt_rounded),
        label: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
      ),
      OutlinedButton.icon(
        onPressed: widget.onChangeLanguage,
        icon: const Icon(Icons.language),
        label: Text(widget.ru ? 'English' : 'Русский'),
      ),
    ],
  );
}

class _V12ProfileAvatar extends StatelessWidget {
  final String nickname;
  final String? avatarBase64;
  final double size;

  const _V12ProfileAvatar({
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
    final letter = nickname.trim().isEmpty
        ? '?'
        : nickname.trim()[0].toUpperCase();
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

class _V12QrScanner extends StatefulWidget {
  final bool ru;

  const _V12QrScanner({required this.ru});

  @override
  State<_V12QrScanner> createState() => _V12QrScannerState();
}

class _V12QrScannerState extends State<_V12QrScanner> {
  bool _handled = false;
  bool _readingFile = false;
  MobileScannerController? _controller;

  bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) _controller = MobileScannerController();
  }

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
    return CgTunnel.fromInviteToken(value) == null ? null : value;
  }

  void _detect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final token = _extract(raw);
      if (token == null) continue;
      _handled = true;
      Navigator.pop(context, token);
      return;
    }
  }

  Future<void> _pickImage() async {
    if (_readingFile) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _showError(
        widget.ru
            ? 'Не удалось прочитать выбранное изображение.'
            : 'Could not read the selected image.',
      );
      return;
    }
    setState(() => _readingFile = true);
    try {
      final raw = await _decodeQrImage(bytes);
      if (!mounted) return;
      if (raw == null) {
        _showError(
          widget.ru
              ? 'QR-код не найден. Выберите чёткий скриншот или фотографию.'
              : 'No QR code was found. Choose a clear screenshot or photo.',
        );
        return;
      }
      final token = _extract(raw);
      if (token == null) {
        _showError(
          widget.ru
              ? 'Этот QR-код не содержит приглашение Чернограма.'
              : 'This QR code does not contain a Chernogram invite.',
        );
        return;
      }
      _handled = true;
      Navigator.pop(context, token);
    } finally {
      if (mounted) setState(() => _readingFile = false);
    }
  }

  void _showError(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.ru ? 'Принять приглашение' : 'Accept invite'),
    ),
    body: Column(
      children: [
        Expanded(
          child: _cameraSupported
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(controller: _controller, onDetect: _detect),
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
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 92,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.ru
                              ? 'На компьютере загрузите скриншот или фотографию QR-кода.'
                              : 'On desktop, upload a screenshot or photo of the QR code.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _readingFile ? null : _pickImage,
                icon: _readingFile
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(
                  widget.ru
                      ? 'Загрузить изображение QR-кода'
                      : 'Upload QR-code image',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
