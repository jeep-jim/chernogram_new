import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_monitor.dart';
import '../brand.dart';
import '../chat_screen.dart';
import '../core_models.dart';
import 'light_theme.dart';

const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';
const String _androidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';
const String _phoneLinksKey = 'chernogram_phone_links_v1';

class ChernogramLightHome extends StatefulWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onCheckUpdates;

  const ChernogramLightHome({
    super.key,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramLightHome> createState() => _ChernogramLightHomeState();
}

class _ChernogramLightHomeState extends State<ChernogramLightHome> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  CgProfile? _profile;
  List<CgTunnel> _chats = <CgTunnel>[];
  List<CgContact> _knownContacts = <CgContact>[];
  List<Contact> _phoneContacts = <Contact>[];
  Map<String, String> _phoneLinks = <String, String>{};
  PackageInfo? _packageInfo;
  bool _loading = true;
  bool _contactsLoading = false;
  int _tab = 0;
  String _dialValue = '';

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final links = <String, String>{};
    final rawLinks = prefs.getString(_phoneLinksKey);
    if (rawLinks != null) {
      try {
        final decoded = jsonDecode(rawLinks);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            links[entry.key.toString()] = entry.value.toString();
          }
        }
      } catch (_) {}
    }

    final values = await Future.wait<Object>(<Future<Object>>[
      CgStore.loadOrCreateProfile(),
      CgStore.loadTunnels(),
      CgStore.loadContacts(),
      PackageInfo.fromPlatform(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = values[0] as CgProfile;
      _chats = values[1] as List<CgTunnel>;
      _knownContacts = values[2] as List<CgContact>;
      _packageInfo = values[3] as PackageInfo;
      _phoneLinks = links;
      _sortChats();
      _loading = false;
    });
    unawaited(_syncMonitor());
    unawaited(_listenLinks());
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

  Future<void> _syncMonitor() async {
    final profile = _profile;
    if (profile == null) return;
    await ChernogramAppMonitor.sync(
      profile: profile,
      tunnels: _chats,
      ru: true,
      onTunnelChanged: _replaceChat,
      onContactSeen: _rememberContact,
    );
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
    final token = _tokenFromUri(uri);
    if (token == null) return;
    final incoming = CgTunnel.fromInviteToken(token);
    if (incoming == null || !mounted) {
      _toast('Ссылка не содержит приглашение Чернограма.');
      return;
    }
    final existing = _chats.indexWhere((chat) => chat.id == incoming.id);
    if (existing >= 0) {
      await _openChat(_chats[existing]);
      return;
    }
    setState(() {
      _chats.insert(0, incoming);
      _tab = 1;
    });
    await CgStore.saveTunnels(_chats);
    unawaited(_syncMonitor());
    if (mounted) await _openChat(incoming);
  }

  void _sortChats() {
    _chats.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
  }

  DateTime _lastActivity(CgTunnel chat) =>
      chat.messages.isEmpty ? chat.createdAt : chat.messages.last.sentAt;

  void _replaceChat(CgTunnel updated) {
    final copy = <CgTunnel>[..._chats];
    final index = copy.indexWhere((chat) => chat.id == updated.id);
    if (index < 0) {
      copy.insert(0, updated);
    } else {
      copy[index] = updated;
    }
    copy.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
    if (mounted) setState(() => _chats = copy);
    unawaited(CgStore.saveTunnels(copy));
    unawaited(_syncMonitor());
  }

  void _rememberContact(CgContact incoming) {
    final profile = _profile;
    if (incoming.id.isEmpty || incoming.id == profile?.id) return;
    final copy = <CgContact>[..._knownContacts];
    final index = copy.indexWhere((contact) => contact.id == incoming.id);
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
    if (mounted) setState(() => _knownContacts = copy);
    unawaited(CgStore.saveContacts(copy));
  }

  CgTunnel _newDirectChat(String name) {
    final profile = _profile!;
    return CgTunnel(
      id: CgIds.random(18),
      name: name.trim().isEmpty ? 'Новый контакт' : name.trim(),
      isPrivate: true,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
  }

  Future<void> _openChat(CgTunnel chat, {String initialAction = 'chat'}) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgChatScreen(
          ru: true,
          profile: profile,
          tunnel: chat,
          privacyLens: false,
          onChanged: _replaceChat,
          onContactSeen: _rememberContact,
          initialAction: initialAction,
        ),
      ),
    );
  }

  Future<void> _savePhoneLinks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneLinksKey, jsonEncode(_phoneLinks));
  }

  String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9+]'), '');

  CgTunnel? _chatForPhone(String phone) {
    final id = _phoneLinks[_normalizePhone(phone)];
    if (id == null) return null;
    return _chats.where((chat) => chat.id == id).firstOrNull;
  }

  Contact? _phoneContact(String phone) {
    final normalized = _normalizePhone(phone);
    for (final contact in _phoneContacts) {
      for (final item in contact.phones) {
        final candidate = _normalizePhone(item.number);
        if (candidate == normalized ||
            (candidate.length >= 10 &&
                normalized.length >= 10 &&
                candidate.substring(candidate.length - 10) ==
                    normalized.substring(normalized.length - 10))) {
          return contact;
        }
      }
    }
    return null;
  }

  Future<CgTunnel> _createPhoneChat(String phone, {String? name}) async {
    final normalized = _normalizePhone(phone);
    final existing = _chatForPhone(normalized);
    if (existing != null) return existing;
    final chat = _newDirectChat(name ?? normalized);
    setState(() {
      _chats.insert(0, chat);
      _phoneLinks[normalized] = chat.id;
    });
    await Future.wait<void>(<Future<void>>[
      CgStore.saveTunnels(_chats),
      _savePhoneLinks(),
    ]);
    unawaited(_syncMonitor());
    return chat;
  }

  String _inviteUrl(CgTunnel chat) =>
      '$_landingBase?invite=${Uri.encodeQueryComponent(chat.inviteToken)}';

  Future<void> _shareInvite(CgTunnel chat, {String? contactName}) async {
    final name = contactName?.trim().isNotEmpty == true
        ? contactName!.trim()
        : chat.displayName;
    await Share.share(
      'Привет, $name! Напиши или позвони мне в Чернограме: ${_inviteUrl(chat)}\n\n'
      'Установить приложение: $_androidInstallUrl',
      subject: 'Приглашение в Чернограм',
    );
  }

  Future<void> _dialAction(String action) async {
    final number = _normalizePhone(_dialValue);
    if (number.isEmpty) {
      await _showPhoneContacts();
      return;
    }
    var chat = _chatForPhone(number);
    if (chat == null) {
      final contact = _phoneContact(number);
      chat = await _createPhoneChat(
        number,
        name: contact?.displayName.trim().isNotEmpty == true
            ? contact!.displayName
            : number,
      );
      await _shareInvite(chat, contactName: contact?.displayName);
      if (!mounted) return;
      _toast(
        'Первое подключение создано. После принятия ссылки звонки станут доступны.',
      );
      await _openChat(chat);
      return;
    }
    await _openChat(chat, initialAction: action);
  }

  Future<void> _loadPhoneContacts() async {
    if (_contactsLoading || _phoneContacts.isNotEmpty) return;
    setState(() => _contactsLoading = true);
    try {
      final allowed = await FlutterContacts.requestPermission(readonly: true);
      if (!allowed) {
        _toast(
          'Разрешение на контакты не выдано. Можно отправить ссылку вручную.',
        );
        return;
      }
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (mounted) setState(() => _phoneContacts = contacts);
    } finally {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> _showPhoneContacts() async {
    await _loadPhoneContacts();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PhoneContactsSheet(contacts: _phoneContacts),
    );
    if (selected == null || selected.phones.isEmpty) return;
    final phone = _normalizePhone(selected.phones.first.number);
    setState(() {
      _dialValue = phone;
      _tab = 0;
    });
  }

  Future<void> _openKnownContact(CgContact contact, String action) async {
    for (final id in contact.tunnelIds) {
      final chat = _chats.where((item) => item.id == id).firstOrNull;
      if (chat != null) {
        await _openChat(chat, initialAction: action);
        return;
      }
    }
    final chat = _newDirectChat(contact.nickname);
    setState(() => _chats.insert(0, chat));
    await CgStore.saveTunnels(_chats);
    await _shareInvite(chat, contactName: contact.nickname);
    if (mounted) await _openChat(chat);
  }

  Future<void> _newChat() async {
    await _loadPhoneContacts();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PhoneContactsSheet(
        contacts: _phoneContacts,
        allowManualInvite: true,
      ),
    );
    if (selected == null) {
      final chat = _newDirectChat('Новый контакт');
      setState(() => _chats.insert(0, chat));
      await CgStore.saveTunnels(_chats);
      await _shareInvite(chat);
      if (mounted) await _openChat(chat);
      return;
    }
    if (selected.phones.isEmpty) return;
    final phone = _normalizePhone(selected.phones.first.number);
    final chat = await _createPhoneChat(phone, name: selected.displayName);
    await _shareInvite(chat, contactName: selected.displayName);
    if (mounted) await _openChat(chat);
  }

  Future<void> _changeProfilePhoto() async {
    final profile = _profile;
    if (profile == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    if (bytes.length > 2 * 1024 * 1024) {
      _toast('Выбери фотографию меньше 2 МБ.');
      return;
    }
    final updated = profile.copyWith(avatarBase64: base64Encode(bytes));
    await CgStore.saveProfile(updated);
    if (mounted) setState(() => _profile = updated);
    unawaited(_syncMonitor());
  }

  Future<void> _changeProfileName() async {
    final profile = _profile;
    if (profile == null) return;
    final controller = TextEditingController(text: profile.nickname);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Имя профиля'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'Как тебя увидят люди'),
          onSubmitted: (text) => Navigator.pop(context, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    final updated = profile.copyWith(nickname: value);
    await CgStore.saveProfile(updated);
    if (mounted) setState(() => _profile = updated);
    unawaited(_syncMonitor());
  }

  Future<void> _deleteChat(CgTunnel chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          'История «${chat.displayName}» удалится только с этого телефона.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _chats.removeWhere((item) => item.id == chat.id);
      _phoneLinks.removeWhere((_, value) => value == chat.id);
    });
    await Future.wait<void>(<Future<void>>[
      CgStore.saveTunnels(_chats),
      _savePhoneLinks(),
    ]);
    unawaited(_syncMonitor());
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: ChernogramLogo(size: 124)),
      );
    }

    final pages = <Widget>[
      _ContactsHomePage(
        contacts: _knownContacts,
        chats: _chats,
        onInvite: _newChat,
        onOpenChat: _openChat,
        onKnownContact: _openKnownContact,
      ),
      _ChatsPage(
        profile: _profile!,
        chats: _chats,
        contacts: _knownContacts,
        onOpen: _openChat,
        onCreate: _newChat,
        onDelete: _deleteChat,
      ),
      _ProfilePage(
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
    ];

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
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Контакты',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Чаты',
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

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(ChernogramAppMonitor.stop());
    super.dispose();
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 18, 10),
    child: Row(
      children: [
        const ChernogramLogo(size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .55),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class _ContactsHomePage extends StatefulWidget {
  final List<CgContact> contacts;
  final List<CgTunnel> chats;
  final Future<void> Function() onInvite;
  final Future<void> Function(CgTunnel chat, {String initialAction}) onOpenChat;
  final Future<void> Function(CgContact contact, String action) onKnownContact;

  const _ContactsHomePage({
    required this.contacts,
    required this.chats,
    required this.onInvite,
    required this.onOpenChat,
    required this.onKnownContact,
  });

  @override
  State<_ContactsHomePage> createState() => _ContactsHomePageState();
}

class _ContactsHomePageState extends State<_ContactsHomePage> {
  final TextEditingController _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final contacts = widget.contacts.where((contact) {
      if (query.isEmpty) return true;
      return contact.nickname.toLowerCase().contains(query);
    }).toList();
    final recentChats = widget.chats.take(5).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PageHeader(
              title: 'Контакты',
              subtitle: 'Только реальные контакты Чернограма',
              trailing: IconButton.filled(
                tooltip: 'Пригласить человека',
                onPressed: widget.onInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Найти контакт',
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
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: LightGlass(
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(26),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: LightChatColors.violet.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.link_rounded),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Добавить человека',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Выбери контакт телефона и отправь ему защищённую ссылку. После принятия появятся чат и звонки.',
                            style: TextStyle(fontSize: 11.5, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: widget.onInvite,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Люди в Чернограме',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (contacts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: LightGlass(
                  padding: const EdgeInsets.all(20),
                  borderRadius: BorderRadius.circular(26),
                  child: Column(
                    children: [
                      const Icon(Icons.people_outline_rounded, size: 46),
                      const SizedBox(height: 10),
                      Text(
                        query.isEmpty
                            ? 'Контактов Чернограма пока нет'
                            : 'Контакт не найден',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        query.isEmpty
                            ? 'Пригласи человека один раз — контакт и диалог сохранятся.'
                            : 'Измени запрос или очисти поиск.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .58),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
              sliver: SliverList.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: LightGlass(
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(26),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 6, 5, 6),
                        leading: ChernogramAvatar(
                          size: 50,
                          seed: contact.id,
                          avatarBase64: contact.avatarBase64,
                        ),
                        title: Text(
                          contact.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: const Text('Контакт Чернограма'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Написать',
                              onPressed: () =>
                                  widget.onKnownContact(contact, 'chat'),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Аудиозвонок',
                              onPressed: () =>
                                  widget.onKnownContact(contact, 'audio'),
                              icon: const Icon(Icons.call_outlined),
                            ),
                            IconButton(
                              tooltip: 'Видеозвонок',
                              onPressed: () =>
                                  widget.onKnownContact(contact, 'video'),
                              icon: const Icon(Icons.videocam_outlined),
                            ),
                          ],
                        ),
                        onTap: () => widget.onKnownContact(contact, 'chat'),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (recentChats.isNotEmpty) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Последние диалоги',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 110),
              sliver: SliverList.builder(
                itemCount: recentChats.length,
                itemBuilder: (context, index) {
                  final chat = recentChats[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: LightGlass(
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(26),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                        leading: ChernogramAvatar(
                          size: 48,
                          seed: chat.id,
                          avatarBase64: chat.avatarBase64,
                        ),
                        title: Text(
                          chat.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          chat.messages.isEmpty
                              ? 'Открыть диалог'
                              : chat.messages.last.text.trim().isEmpty
                              ? 'Вложение или звонок'
                              : chat.messages.last.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 15,
                        ),
                        onTap: () => widget.onOpenChat(chat),
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _ChatsPage extends StatefulWidget {
  final CgProfile profile;
  final List<CgTunnel> chats;
  final List<CgContact> contacts;
  final Future<void> Function(CgTunnel chat, {String initialAction}) onOpen;
  final Future<void> Function() onCreate;
  final Future<void> Function(CgTunnel chat) onDelete;

  const _ChatsPage({
    required this.profile,
    required this.chats,
    required this.contacts,
    required this.onOpen,
    required this.onCreate,
    required this.onDelete,
  });

  @override
  State<_ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<_ChatsPage> {
  final TextEditingController _search = TextEditingController();

  String _preview(CgTunnel chat) {
    if (chat.messages.isEmpty) return 'Нажми, чтобы написать';
    final message = chat.messages.last;
    if (message.deleted) return 'Сообщение удалено';
    if (message.type == 'call') {
      return message.meta['video'] == true ? 'Видеозвонок' : 'Звонок';
    }
    if (message.attachment != null) {
      return switch (message.attachment!.kind) {
        'circle' => 'Видеокружок',
        'voice' => 'Голосовое сообщение',
        'image' => 'Фотография',
        'video' => 'Видео',
        _ => message.attachment!.name,
      };
    }
    return message.text;
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final chats = widget.chats.where((chat) {
      if (query.isEmpty) return true;
      return chat.displayName.toLowerCase().contains(query) ||
          chat.messages.any(
            (message) => message.text.toLowerCase().contains(query),
          );
    }).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _PageHeader(
            title: 'Чаты',
            subtitle: '${widget.chats.length} сохранённых диалогов',
            trailing: IconButton.filled(
              tooltip: 'Новый чат',
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Поиск',
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
            child: chats.isEmpty
                ? _EmptyChats(onCreate: widget.onCreate)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 108),
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      final last = chat.messages.isEmpty
                          ? null
                          : chat.messages.last;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: LightGlass(
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(26),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              11,
                              7,
                              4,
                              7,
                            ),
                            leading: ChernogramAvatar(
                              size: 52,
                              seed: chat.id,
                              avatarBase64: chat.avatarBase64,
                            ),
                            title: Text(
                              chat.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _preview(chat),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (last != null)
                                  Text(
                                    '${last.sentAt.hour.toString().padLeft(2, '0')}:${last.sentAt.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .45),
                                    ),
                                  ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'delete')
                                      widget.onDelete(chat);
                                  },
                                  itemBuilder: (_) =>
                                      const <PopupMenuEntry<String>>[
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                              SizedBox(width: 10),
                                              Text('Удалить чат'),
                                            ],
                                          ),
                                        ),
                                      ],
                                ),
                              ],
                            ),
                            onTap: () => widget.onOpen(chat),
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
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _ProfilePage extends StatelessWidget {
  final CgProfile profile;
  final PackageInfo? packageInfo;
  final bool darkMode;
  final Future<void> Function() onPhoto;
  final Future<void> Function() onName;
  final VoidCallback onTheme;
  final Future<void> Function() onShareInstall;
  final VoidCallback onUpdate;

  const _ProfilePage({
    required this.profile,
    required this.packageInfo,
    required this.darkMode,
    required this.onPhoto,
    required this.onName,
    required this.onTheme,
    required this.onShareInstall,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final version = packageInfo == null
        ? 'Версия загружается…'
        : 'Версия ${packageInfo!.version} • сборка ${packageInfo!.buildNumber}';
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          const _PageHeader(
            title: 'Профиль',
            subtitle: 'Только основные настройки',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: LightGlass(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: onPhoto,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ChernogramAvatar(
                          size: 112,
                          seed: profile.id,
                          avatarBase64: profile.avatarBase64,
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Material(
                            color: Theme.of(context).colorScheme.primary,
                            shape: const CircleBorder(),
                            child: const SizedBox.square(
                              dimension: 36,
                              child: Icon(
                                Icons.photo_camera_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    profile.nickname,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    profile.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .45),
                    ),
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton.icon(
                    onPressed: onName,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Изменить имя'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LightGlass(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: Icon(
                      darkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                    ),
                    title: const Text(
                      'Оформление',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      darkMode ? 'Мягкая тёмная тема' : 'Светлая тема',
                    ),
                    trailing: Switch(
                      value: darkMode,
                      onChanged: (_) => onTheme(),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.install_mobile_rounded),
                    title: const Text(
                      'Ссылка на установку',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Отправить приложение другому человеку',
                    ),
                    trailing: const Icon(Icons.ios_share_rounded),
                    onTap: onShareInstall,
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: const Icon(Icons.system_update_alt_rounded),
                    title: const Text(
                      'Обновление',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('Проверить новую версию онлайн'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: onUpdate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: [
                const ChernogramLogo(size: 44),
                const SizedBox(height: 7),
                Text(
                  version,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneContactsSheet extends StatefulWidget {
  final List<Contact> contacts;
  final bool allowManualInvite;

  const _PhoneContactsSheet({
    required this.contacts,
    this.allowManualInvite = false,
  });

  @override
  State<_PhoneContactsSheet> createState() => _PhoneContactsSheetState();
}

class _PhoneContactsSheetState extends State<_PhoneContactsSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final contacts = widget.contacts.where((contact) {
      if (contact.phones.isEmpty) return false;
      if (query.isEmpty) return true;
      return contact.displayName.toLowerCase().contains(query) ||
          contact.phones.any((phone) => phone.number.contains(query));
    }).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(
          children: [
            const Text(
              'Контакты',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                controller: _search,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Имя или номер',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (widget.allowManualInvite)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .10),
                  leading: const CircleAvatar(child: Icon(Icons.link_rounded)),
                  title: const Text(
                    'Отправить ссылку вручную',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: contacts.isEmpty
                  ? const Center(child: Text('Контакты с номерами не найдены'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              contact.displayName.trim().isEmpty
                                  ? '?'
                                  : contact.displayName
                                        .trim()
                                        .characters
                                        .first
                                        .toUpperCase(),
                            ),
                          ),
                          title: Text(
                            contact.displayName.trim().isEmpty
                                ? 'Без имени'
                                : contact.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(contact.phones.first.number),
                          onTap: () => Navigator.pop(context, contact),
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
    super.dispose();
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
    child: LightGlass(
      child: Column(
        children: [
          const Icon(Icons.contacts_outlined, size: 48),
          const SizedBox(height: 10),
          const Text(
            'Здесь появятся люди',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Выбери контакт телефона или отправь человеку ссылку на первый чат.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .56),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyChats extends StatelessWidget {
  final Future<void> Function() onCreate;

  const _EmptyChats({required this.onCreate});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 86),
          const SizedBox(height: 14),
          const Text(
            'Чатов пока нет',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            'Выбери человека из контактов или отправь ссылку. Диалог сохранится здесь для следующих сообщений и звонков.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.4,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .56),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новый чат'),
          ),
        ],
      ),
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
