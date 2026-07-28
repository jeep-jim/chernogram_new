import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'tunnel_extras.dart'; // CHERNOGRAM_05_EXTRAS

class LocalProfile {
  final String id;
  final String nickname;
  final DateTime createdAt;

  const LocalProfile({
    required this.id,
    required this.nickname,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LocalProfile.fromJson(Map<String, dynamic> json) => LocalProfile(
    id: json['id']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

class TunnelInfo {
  final String id;
  final String name;
  final bool isPublic;
  final String ownerId;
  final DateTime createdAt;
  final List<TunnelMessage> messages;

  const TunnelInfo({
    required this.id,
    required this.name,
    required this.isPublic,
    required this.ownerId,
    required this.createdAt,
    required this.messages,
  });

  String get link => 'https://chernogram.app/t/$id';

  TunnelInfo copyWith({List<TunnelMessage>? messages}) => TunnelInfo(
    id: id,
    name: name,
    isPublic: isPublic,
    ownerId: ownerId,
    createdAt: createdAt,
    messages: messages ?? this.messages,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isPublic': isPublic,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  factory TunnelInfo.fromJson(Map<String, dynamic> json) => TunnelInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    isPublic: json['isPublic'] == true,
    ownerId: json['ownerId']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    messages: ((json['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => TunnelMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
  );
}

class TunnelMessage {
  final String id;
  final String author;
  final String text;
  final String? assetId;
  final DateTime sentAt;

  const TunnelMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.assetId,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author,
    'text': text,
    'assetId': assetId,
    'sentAt': sentAt.toIso8601String(),
  };

  factory TunnelMessage.fromJson(Map<String, dynamic> json) => TunnelMessage(
    id: json['id']?.toString() ?? '',
    author: json['author']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
    assetId: json['assetId']?.toString(),
    sentAt:
        DateTime.tryParse(json['sentAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class LocalTunnelStore {
  static const _profileKey = 'chernogram_profile_v1';
  static const _tunnelsKey = 'chernogram_tunnels_v1';

  static Future<LocalProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return LocalProfile.fromJson(decoded);
  }

  static Future<void> saveProfile(LocalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  static Future<List<TunnelInfo>> loadTunnels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tunnelsKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => TunnelInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<void> saveTunnels(List<TunnelInfo> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tunnelsKey,
      jsonEncode(tunnels.map((tunnel) => tunnel.toJson()).toList()),
    );
  }
}

class NicknameRules {
  static const _blockedRoots = <String>[
    'porn',
    'порн',
    'sex',
    'секс',
    'auto',
    'авто',
    'vk',
    'вк',
    'putin',
    'путин',
    'trump',
    'трамп',
    'war',
    'войн',
    'weapon',
    'оруж',
    'gun',
    'наркот',
    'drug',
    'убил',
    'kill',
    'murder',
    'rape',
    'насил',
    'violence',
    'terror',
    'террор',
    'child',
    'дети',
    'admin',
    'support',
    'official',
    'chernogram',
  ];

  static String? validate(String input, {required bool ru}) {
    final value = input.trim().toLowerCase();
    if (value.length < 4 || value.length > 24) {
      return ru
          ? 'Никнейм: от 4 до 24 символов.'
          : 'Nickname: 4–24 characters.';
    }
    if (!RegExp(r'^[a-zа-яё0-9_.]+$', caseSensitive: false).hasMatch(value)) {
      return ru
          ? 'Разрешены буквы, цифры, точка и подчёркивание.'
          : 'Use letters, numbers, a dot or underscore.';
    }
    final compact = value.replaceAll(RegExp(r'[._0-9]'), '');
    for (final root in _blockedRoots) {
      if (value.contains(root) || compact.contains(root)) {
        return ru
            ? 'Этот никнейм или его часть запрещены.'
            : 'This nickname or part of it is not allowed.';
      }
    }
    return null;
  }
}

String generateChernogramId({int length = 12}) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

class ProfileScreen extends StatefulWidget {
  final bool ru;
  final LocalProfile? profile;
  final ValueChanged<LocalProfile> onProfileChanged;
  final VoidCallback onCheckUpdates;
  final VoidCallback onChangeLanguage;

  const ProfileScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.onProfileChanged,
    required this.onCheckUpdates,
    required this.onChangeLanguage,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nickname = TextEditingController();
  String? _error;
  int _avatarRevision = 0;

  @override
  void initState() {
    super.initState();
    _nickname.text = widget.profile?.nickname ?? '';
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.nickname != widget.profile?.nickname) {
      _nickname.text = widget.profile?.nickname ?? '';
    }
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    final profile = widget.profile;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Сначала сохраните никнейм.'
                : 'Save your nickname first.',
          ),
        ),
      );
      return;
    }
    final changed = await chooseAndSaveLocalAvatar(
      context,
      profileId: profile.id,
      ru: widget.ru,
    );
    if (changed && mounted) {
      setState(() => _avatarRevision++);
    }
  }

  Future<void> _save() async {
    final error = NicknameRules.validate(_nickname.text, ru: widget.ru);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final profile = LocalProfile(
      id: widget.profile?.id ?? generateChernogramId(),
      nickname: _nickname.text.trim().toLowerCase(),
      createdAt: widget.profile?.createdAt ?? DateTime.now(),
    );
    await LocalTunnelStore.saveProfile(profile);
    widget.onProfileChanged(profile);
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'Профиль сохранён на этом устройстве.'
              : 'Profile saved on this device.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      children: [
        Center(
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  LocalProfileAvatar(
                    key: ValueKey(_avatarRevision),
                    profileId: widget.profile?.id,
                    nickname: widget.profile?.nickname ?? '',
                    size: 104,
                    showBrandWhenEmpty: true,
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: ChernogramColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: ru ? 'Выбрать аватарку' : 'Choose avatar',
                      onPressed: _chooseAvatar,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.profile == null
                    ? (ru
                          ? 'Создайте локальный профиль'
                          : 'Create a local profile')
                    : '@${widget.profile!.nickname}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (widget.profile != null) ...[
                const SizedBox(height: 4),
                SelectableText(
                  'ID: ${widget.profile!.id}',
                  style: const TextStyle(color: ChernogramColors.goldLight),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _nickname,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            labelText: ru ? 'Никнейм' : 'Nickname',
            prefixText: '@',
            errorText: _error,
            helperText: ru
                ? 'Запрещённые и служебные слова автоматически блокируются.'
                : 'Restricted and reserved terms are blocked automatically.',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(ru ? 'Занять никнейм' : 'Claim nickname'),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF261B10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            ru
                ? 'Сейчас профиль закрепляется локально. Для глобальной уникальности никнейма и работы туннелей между телефонами подключим безопасный сетевой реестр.'
                : 'The profile is currently stored locally. Global nickname uniqueness and cross-device tunnels will use a secure network registry.',
            style: const TextStyle(
              fontSize: 12,
              color: ChernogramColors.textSoft,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tileColor: ChernogramColors.surface,
          leading: const Icon(Icons.language),
          title: Text(ru ? 'Язык интерфейса' : 'Interface language'),
          trailing: Text(ru ? 'RU' : 'EN'),
          onTap: widget.onChangeLanguage,
        ),
        const SizedBox(height: 8),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tileColor: ChernogramColors.surface,
          leading: const Icon(Icons.system_update_alt_rounded),
          title: Text(ru ? 'Проверить обновления' : 'Check for updates'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onCheckUpdates,
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'CHERNOGRAM 0.5.0',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
      ],
    );
  }
}

class TunnelsScreen extends StatefulWidget {
  final bool ru;
  final LocalProfile? profile;

  const TunnelsScreen({super.key, required this.ru, required this.profile});

  @override
  State<TunnelsScreen> createState() => _TunnelsScreenState();
}

class _TunnelsScreenState extends State<TunnelsScreen> {
  List<TunnelInfo> _tunnels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tunnels = await LocalTunnelStore.loadTunnels();
    if (!mounted) return;
    setState(() {
      _tunnels = tunnels;
      _loading = false;
    });
  }

  Future<void> _createTunnel() async {
    if (widget.profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Сначала создайте профиль во вкладке «Профиль».'
                : 'Create a profile first in the Profile tab.',
          ),
        ),
      );
      return;
    }
    final result = await showModalBottomSheet<_NewTunnelData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateTunnelSheet(ru: widget.ru),
    );
    if (result == null) return;
    final tunnel = TunnelInfo(
      id: generateChernogramId(length: 16).toLowerCase(),
      name: result.name,
      isPublic: result.isPublic,
      ownerId: widget.profile!.id,
      createdAt: DateTime.now(),
      messages: [
        TunnelMessage(
          id: generateChernogramId(),
          author: 'system',
          text: widget.ru
              ? 'Туннель создан. Отправьте ссылку человеку или откройте публичный доступ.'
              : 'Tunnel created. Send the link or make it public.',
          assetId: null,
          sentAt: DateTime.now(),
        ),
      ],
    );
    _tunnels = [tunnel, ..._tunnels];
    await LocalTunnelStore.saveTunnels(_tunnels);
    if (!mounted) return;
    setState(() {});
    _openTunnel(tunnel);
  }

  Future<void> _openTunnel(TunnelInfo tunnel) async {
    final updated = await Navigator.push<TunnelInfo>(
      context,
      MaterialPageRoute(
        builder: (_) => TunnelChatScreen(
          ru: widget.ru,
          profile: widget.profile!,
          tunnel: tunnel,
        ),
      ),
    );
    if (updated == null) return;
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _tunnels[index] = updated;
    await LocalTunnelStore.saveTunnels(_tunnels);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTunnel,
        icon: const Icon(Icons.add_link),
        label: Text(ru ? 'Создать туннель' : 'Create tunnel'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF351705), Color(0xFF21160E)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const ChernogramLogo(size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ru ? 'Туннели' : 'Tunnels',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        ru
                            ? 'Чат, папка и быстрая ссылка для передачи медиа в одном месте.'
                            : 'Chat, shared media and a quick invite link in one place.',
                        style: const TextStyle(
                          color: ChernogramColors.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_tunnels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  const Icon(
                    Icons.cable_outlined,
                    size: 70,
                    color: Colors.white30,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ru ? 'Пока нет туннелей' : 'No tunnels yet',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    ru
                        ? 'Создайте ссылку и пригласите человека из контактов, Telegram или Instagram.'
                        : 'Create a link and invite someone from contacts, Telegram or Instagram.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ChernogramColors.textSoft),
                  ),
                ],
              ),
            )
          else
            for (final tunnel in _tunnels) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: LocalProfileAvatar(
                    profileId: widget.profile?.id,
                    nickname: widget.profile?.nickname ?? tunnel.name,
                    size: 46,
                    showBrandWhenEmpty: true,
                  ),
                  title: Text(
                    tunnel.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${tunnel.isPublic ? (ru ? 'Публичный' : 'Public') : (ru ? 'По приглашению' : 'Invite only')} • ${tunnel.messages.length}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openTunnel(tunnel),
                ),
              ),
              const SizedBox(height: 5),
            ],
        ],
      ),
    );
  }
}

class _NewTunnelData {
  final String name;
  final bool isPublic;

  const _NewTunnelData(this.name, this.isPublic);
}

class _CreateTunnelSheet extends StatefulWidget {
  final bool ru;

  const _CreateTunnelSheet({required this.ru});

  @override
  State<_CreateTunnelSheet> createState() => _CreateTunnelSheetState();
}

class _CreateTunnelSheetState extends State<_CreateTunnelSheet> {
  final _name = TextEditingController();
  bool _isPublic = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        4,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ru ? 'Новый туннель' : 'New tunnel',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: ru ? 'Название' : 'Name',
              hintText: ru
                  ? 'Например: Котик для Маши'
                  : 'Example: Cat photos for Maya',
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _isPublic,
            contentPadding: EdgeInsets.zero,
            title: Text(ru ? 'Публичная ссылка' : 'Public link'),
            subtitle: Text(
              _isPublic
                  ? (ru
                        ? 'Ссылку сможет открыть любой, у кого она есть.'
                        : 'Anyone with the link can open it.')
                  : (ru
                        ? 'Доступ только по персональному приглашению.'
                        : 'Access only by personal invitation.'),
            ),
            onChanged: (value) => setState(() => _isPublic = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final name = _name.text.trim();
                if (name.length < 3) return;
                Navigator.pop(context, _NewTunnelData(name, _isPublic));
              },
              icon: const Icon(Icons.cable),
              label: Text(ru ? 'Создать' : 'Create'),
            ),
          ),
        ],
      ),
    );
  }
}

class TunnelChatScreen extends StatefulWidget {
  final bool ru;
  final LocalProfile profile;
  final TunnelInfo tunnel;

  const TunnelChatScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnel,
  });

  @override
  State<TunnelChatScreen> createState() => _TunnelChatScreenState();
}

class _TunnelChatScreenState extends State<TunnelChatScreen> {
  final _controller = TextEditingController();
  late TunnelInfo _tunnel;
  TunnelPermissions _permissions = const TunnelPermissions();

  @override
  void initState() {
    super.initState();
    _tunnel = widget.tunnel;
    _loadPermissions();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final value = await LocalTunnelExtrasStore.loadPermissions(_tunnel.id);
    if (mounted) setState(() => _permissions = value);
  }

  Future<void> _showQr() async {
    await showTunnelQrDialog(
      context,
      link: _tunnel.link,
      tunnelName: _tunnel.name,
      ru: widget.ru,
    );
  }

  Future<void> _editPermissions() async {
    final value = await showTunnelPermissionsDialog(
      context,
      initial: _permissions,
      ru: widget.ru,
    );
    if (value == null) return;
    await LocalTunnelExtrasStore.savePermissions(_tunnel.id, value);
    if (mounted) setState(() => _permissions = value);
  }

  String get _inviteText => widget.ru
      ? 'Присоединяйся к моему туннелю «${_tunnel.name}» в Чернограме: ${_tunnel.link}'
      : 'Join my Chernogram tunnel “${_tunnel.name}”: ${_tunnel.link}';

  Future<void> _saveAndReturn() async {
    final tunnels = await LocalTunnelStore.loadTunnels();
    final index = tunnels.indexWhere((item) => item.id == _tunnel.id);
    if (index >= 0) {
      tunnels[index] = _tunnel;
    } else {
      tunnels.insert(0, _tunnel);
    }
    await LocalTunnelStore.saveTunnels(tunnels);
  }

  void _sendText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final message = TunnelMessage(
      id: generateChernogramId(),
      author: widget.profile.nickname,
      text: text,
      assetId: null,
      sentAt: DateTime.now(),
    );
    setState(() {
      _tunnel = _tunnel.copyWith(messages: [..._tunnel.messages, message]);
      _controller.clear();
    });
    _saveAndReturn();
  }

  Future<void> _attachMedia() async {
    final asset = await Navigator.push<AssetEntity>(
      context,
      MaterialPageRoute(builder: (_) => TunnelMediaPicker(ru: widget.ru)),
    );
    if (asset == null) return;
    final message = TunnelMessage(
      id: generateChernogramId(),
      author: widget.profile.nickname,
      text: widget.ru ? 'Медиа из галереи' : 'Media from gallery',
      assetId: asset.id,
      sentAt: DateTime.now(),
    );
    setState(() {
      _tunnel = _tunnel.copyWith(messages: [..._tunnel.messages, message]);
    });
    _saveAndReturn();
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _tunnel.link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.ru ? 'Ссылка скопирована' : 'Link copied')),
    );
  }

  Future<void> _shareTelegram() async {
    final uri = Uri.https('t.me', '/share/url', {
      'url': _tunnel.link,
      'text': widget.ru
          ? 'Смотри медиа в моём туннеле Чернограма'
          : 'See media in my Chernogram tunnel',
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) await Share.share(_inviteText);
  }

  Future<void> _inviteContacts() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          InviteContactsSheet(ru: widget.ru, inviteText: _inviteText),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveAndReturn();
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 58,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: LocalProfileAvatar(
              profileId: widget.profile.id,
              nickname: widget.profile.nickname,
              size: 40,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tunnel.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                _tunnel.isPublic
                    ? (ru ? 'Публичный туннель' : 'Public tunnel')
                    : (ru ? 'Доступ по приглашению' : 'Invite-only access'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: ru ? 'QR-код' : 'QR code',
              onPressed: _showQr,
              icon: const Icon(Icons.qr_code_2),
            ),
            IconButton(
              tooltip: ru ? 'Права доступа' : 'Permissions',
              onPressed: _editPermissions,
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
            IconButton(onPressed: _copyLink, icon: const Icon(Icons.link)),
            IconButton(
              onPressed: () => Share.share(_inviteText),
              icon: const Icon(Icons.share),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ChernogramColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.link, color: ChernogramColors.goldLight),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _tunnel.link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _copyLink,
                        child: Text(ru ? 'Копировать' : 'Copy'),
                      ),
                    ],
                  ),
                  const Divider(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _inviteContacts,
                          icon: const Icon(Icons.contacts_outlined),
                          label: Text(ru ? 'Контакты' : 'Contacts'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareTelegram,
                          icon: const Icon(Icons.send),
                          label: const Text('Telegram'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Share.share(_inviteText),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Instagram'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                itemCount: _tunnel.messages.length,
                itemBuilder: (_, index) {
                  final message = _tunnel.messages[index];
                  final mine = message.author == widget.profile.nickname;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 330),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: mine
                            ? const Color(0xFF633013)
                            : ChernogramColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.assetId != null)
                            _TunnelAssetPreview(assetId: message.assetId!),
                          if (message.assetId != null)
                            const SizedBox(height: 7),
                          Text(message.text),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LocalProfileAvatar(
                                profileId: mine ? widget.profile.id : null,
                                nickname: message.author,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${message.author} • ${_time(message.sentAt)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _attachMedia,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: ru ? 'Сообщение…' : 'Message…',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    IconButton.filled(
                      onPressed: _sendText,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InviteContactsSheet extends StatefulWidget {
  final bool ru;
  final String inviteText;

  const InviteContactsSheet({
    super.key,
    required this.ru,
    required this.inviteText,
  });

  @override
  State<InviteContactsSheet> createState() => _InviteContactsSheetState();
}

class _InviteContactsSheetState extends State<InviteContactsSheet> {
  final _search = TextEditingController();
  List<Contact> _contacts = [];
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final allowed = await FlutterContacts.requestPermission(readonly: true);
    if (!allowed) {
      if (mounted)
        setState(() {
          _loading = false;
          _denied = true;
        });
      return;
    }
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  Future<void> _invite(Contact contact) async {
    final phone = contact.phones.isEmpty ? null : contact.phones.first.number;
    if (phone == null || phone.trim().isEmpty) {
      await Share.share(widget.inviteText);
      return;
    }
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': widget.inviteText},
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) await Share.share(widget.inviteText);
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _contacts
        : _contacts
              .where(
                (contact) => contact.displayName.toLowerCase().contains(query),
              )
              .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ru ? 'Пригласить из контактов' : 'Invite from contacts',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: ru ? 'Найти человека' : 'Find a person',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _denied
                  ? Center(
                      child: Text(
                        ru
                            ? 'Доступ к контактам не разрешён. Можно отправить ссылку через системное меню.'
                            : 'Contacts permission was denied. Use the system share menu instead.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final contact = visible[index];
                        final letter = contact.displayName.trim().isEmpty
                            ? '?'
                            : contact.displayName.trim()[0].toUpperCase();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: ChernogramColors.orangeDeep,
                            child: Text(letter),
                          ),
                          title: Text(contact.displayName),
                          subtitle: contact.phones.isEmpty
                              ? null
                              : Text(contact.phones.first.number),
                          trailing: const Icon(Icons.send_outlined),
                          onTap: () => _invite(contact),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Share.share(widget.inviteText),
                icon: const Icon(Icons.apps),
                label: Text(
                  ru
                      ? 'Отправить через другое приложение'
                      : 'Send through another app',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TunnelMediaPicker extends StatefulWidget {
  final bool ru;

  const TunnelMediaPicker({super.key, required this.ru});

  @override
  State<TunnelMediaPicker> createState() => _TunnelMediaPickerState();
}

class _TunnelMediaPickerState extends State<TunnelMediaPicker> {
  List<AssetEntity> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      hasAll: true,
      type: RequestType.common,
    );
    final assets = albums.isEmpty
        ? <AssetEntity>[]
        : await albums.first.getAssetListPaged(page: 0, size: 120);
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Добавить в туннель' : 'Add to tunnel'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _assets.length,
              itemBuilder: (_, index) {
                final asset = _assets[index];
                return InkWell(
                  onTap: () => Navigator.pop(context, asset),
                  child: FutureBuilder<Uint8List?>(
                    future: asset.thumbnailDataWithSize(
                      const ThumbnailSize.square(320),
                    ),
                    builder: (_, snapshot) => snapshot.data == null
                        ? const ColoredBox(
                            color: ChernogramColors.surfaceHigh,
                            child: Icon(Icons.image_outlined),
                          )
                        : Image.memory(snapshot.data!, fit: BoxFit.cover),
                  ),
                );
              },
            ),
    );
  }
}

class _TunnelAssetPreview extends StatelessWidget {
  final String assetId;

  const _TunnelAssetPreview({required this.assetId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(assetId),
      builder: (_, assetSnapshot) {
        final asset = assetSnapshot.data;
        if (asset == null) {
          return const SizedBox(
            height: 90,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
        }
        return FutureBuilder<Uint8List?>(
          future: asset.thumbnailDataWithSize(const ThumbnailSize(640, 640)),
          builder: (_, snapshot) => snapshot.data == null
              ? const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    snapshot.data!,
                    width: 280,
                    height: 190,
                    fit: BoxFit.cover,
                  ),
                ),
        );
      },
    );
  }
}

String _time(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
