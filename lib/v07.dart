import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'agent_screen.dart';
import 'brand.dart';
import 'chat_screen.dart';
import 'core_models.dart';

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
  bool _loading = true;
  bool _privacyLens = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final profile = await CgStore.loadOrCreateProfile();
    final tunnels = await CgStore.loadTunnels();
    final privacy = await CgStore.loadPrivacyLens();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _tunnels = tunnels;
      _privacyLens = privacy;
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
          '${tunnel.displayName}\n\n${widget.ru ? 'Сообщения и звонки работают через интернет, даже если участники находятся в разных сетях.' : 'Messages and calls work over the internet even when participants use different networks.'}',
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
                  widget.ru ? 'Новый туннель' : 'New tunnel',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.ru
                      ? 'Название можно не вводить — туннель создастся сразу и предложит отправить ссылку.'
                      : 'The name is optional. The tunnel opens immediately and offers an invite.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .56),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.ru ? 'Название — необязательно' : 'Name — optional',
                    hintText: widget.ru ? 'Можно оставить пустым' : 'You may leave it empty',
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
                            ? 'Секретная ссылка и сквозное шифрование.'
                            : 'Secret invite and end-to-end encryption.')
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
                    onPressed: () => Navigator.pop(
                      context,
                      (name: name.text.trim(), isPrivate: isPrivate),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(widget.ru ? 'Создать и пригласить' : 'Create and invite'),
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
        ),
      ),
    );
  }

  void _updateTunnel(CgTunnel updated) {
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      _tunnels = [updated, ..._tunnels];
    } else {
      final copy = [..._tunnels];
      copy[index] = updated;
      _tunnels = copy;
    }
    if (mounted) setState(() {});
    unawaited(CgStore.saveTunnels(_tunnels));
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
      _TunnelsHome(
        ru: widget.ru,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        onCreate: _createTunnel,
        onScan: _scanQr,
        onOpen: _openTunnel,
      ),
      CgAgentScreen(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        onCreateTunnel: _createTunnel,
        onTogglePrivacy: _togglePrivacy,
      ),
      _DevicesScreen(ru: widget.ru, profile: _profile!),
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
          subtitle: widget.ru
              ? 'ЗАЩИЩЁННЫЕ ТУННЕЛИ И ЗВОНКИ'
              : 'SECURE TUNNELS AND CALLS',
        ),
        actions: [
          GlassIconButton(
            icon: _privacyLens
                ? Icons.visibility_off_rounded
                : Icons.visibility_outlined,
            tooltip: widget.ru ? 'Приватный взгляд' : 'Privacy Lens',
            active: _privacyLens,
            onPressed: _togglePrivacy,
          ),
          const SizedBox(width: 6),
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
                  leading: Icon(widget.darkMode ? Icons.light_mode : Icons.dark_mode),
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
                  title: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
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
            label: widget.ru ? 'Туннели' : 'Tunnels',
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: widget.ru ? 'Агент' : 'Agent',
          ),
          NavigationDestination(
            icon: const Icon(Icons.devices_outlined),
            selectedIcon: const Icon(Icons.devices_rounded),
            label: widget.ru ? 'Устройства' : 'Devices',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person_rounded),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _TunnelsHome extends StatelessWidget {
  final bool ru;
  final List<CgTunnel> tunnels;
  final bool privacyLens;
  final VoidCallback onCreate;
  final VoidCallback onScan;
  final Future<void> Function(CgTunnel tunnel) onOpen;

  const _TunnelsHome({
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
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                ru
                    ? 'Создайте туннель за одно нажатие. Сообщения и звонки работают между разными городами и сетями.'
                    : 'Create a tunnel in one tap. Messages and calls work across cities and networks.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: .57)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(ru ? 'Новый туннель' : 'New tunnel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: Text(ru ? 'QR' : 'QR'),
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
                ru ? 'Мои туннели' : 'My tunnels',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
                Icon(Icons.forum_outlined, size: 68, color: scheme.onSurface.withValues(alpha: .18)),
                const SizedBox(height: 12),
                Text(
                  ru ? 'Туннелей пока нет' : 'No tunnels yet',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  ru
                      ? 'Название вводить необязательно — нажмите «Новый туннель».'
                      : 'A name is optional — tap New tunnel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: .48)),
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
  final VoidCallback onTap;

  const _TunnelTile({
    required this.tunnel,
    required this.privacyLens,
    required this.ru,
    required this.onTap,
  });

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
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                        ),
                        Icon(
                          tunnel.isPrivate
                              ? Icons.visibility_off_outlined
                              : Icons.public,
                          size: 16,
                          color: tunnel.isPrivate ? scheme.primary : scheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      last == null
                          ? (ru ? 'Готов к приглашению' : 'Ready to invite')
                          : privacyLens
                              ? '••••••••••••'
                              : last.attachment != null
                                  ? (ru ? 'Вложение: ${last.attachment!.name}' : 'Attachment: ${last.attachment!.name}')
                                  : last.text,
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

class _DevicesScreen extends StatelessWidget {
  final bool ru;
  final CgProfile profile;

  const _DevicesScreen({required this.ru, required this.profile});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
        children: [
          Text(
            ru ? 'Сеть и устройства' : 'Network and devices',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.smartphone_rounded)),
              title: Text(
                ru ? 'Это устройство' : 'This device',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('ID ${profile.id}'),
              trailing: const Chip(
                avatar: Icon(Icons.circle, size: 9, color: ChernogramColors.success),
                label: Text('ONLINE'),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _RouteCard(
            icon: Icons.public_rounded,
            title: ru ? 'Глобальный relay' : 'Global relay',
            subtitle: ru
                ? 'Переписка между разными городами, операторами и Wi‑Fi.'
                : 'Messaging across cities, carriers and Wi-Fi networks.',
            status: ru ? 'АКТИВНО' : 'ACTIVE',
          ),
          _RouteCard(
            icon: Icons.lock_outline_rounded,
            title: ru ? 'Сквозное шифрование' : 'End-to-end encryption',
            subtitle: ru
                ? 'Relay получает только AES-256-GCM шифротекст.'
                : 'The relay receives AES-256-GCM ciphertext only.',
            status: ru ? 'АКТИВНО' : 'ACTIVE',
          ),
          _RouteCard(
            icon: Icons.call_outlined,
            title: 'WebRTC + STUN/TURN',
            subtitle: ru
                ? 'Прямые аудио- и видеозвонки с relay-резервом.'
                : 'Direct audio/video calls with relay fallback.',
            status: 'BETA',
          ),
          _RouteCard(
            icon: Icons.wifi_rounded,
            title: ru ? 'Локальный ускоритель' : 'Local accelerator',
            subtitle: ru
                ? 'Позже большие файлы будут идти напрямую в одной сети.'
                : 'Large files will later use a direct local route.',
            status: ru ? 'СКОРО' : 'SOON',
          ),
        ],
      );
}

class _RouteCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;

  const _RouteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(subtitle),
            trailing: Text(
              status,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: ChernogramColors.success,
              ),
            ),
          ),
        ),
      );
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

  @override
  void initState() {
    super.initState();
    _avatarBase64 = widget.profile.avatarBase64;
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
          content: Text(widget.ru ? 'Минимум 3 символа.' : 'Use at least 3 characters.'),
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
                      color: ChernogramColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(Icons.photo_camera_outlined, color: Colors.white, size: 20),
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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          Center(
            child: Text(
              'ID ${widget.profile.id}',
              style: const TextStyle(fontSize: 11, color: ChernogramColors.gold),
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
          const SizedBox(height: 16),
          GlassPanel(
            child: Text(
              widget.ru
                  ? 'Чернограм не хранит seed-фразы и пароли кошельков. Будущий кошелёк будет подключать внешние приложения через подтверждение каждой операции.'
                  : 'Chernogram will never store wallet seed phrases. Future wallet connections will require approval for every transaction.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58),
              ),
            ),
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
    final letter = nickname.trim().isEmpty ? '?' : nickname.trim()[0].toUpperCase();
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
          title: Text(widget.ru ? 'Сканировать приглашение' : 'Scan invite'),
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
                  border: Border.all(color: ChernogramColors.goldLight, width: 3),
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
            ),
          ],
        ),
      );
}
