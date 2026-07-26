import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'call_service.dart';
import 'tunnel_extras.dart';

// CHERNOGRAM_061_PATCH

const temporaryLandingBase = 'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';

String _randomId([int length = 16]) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}


class ChernogramNicknameRules {
  static const blockedRoots = <String>[
    'porn', 'порн', 'sex', 'секс', 'adult', '18plus', 'nude', 'нюд',
    'pedo', 'педоф', 'child', 'дет', 'violence', 'насил', 'weapon',
    'оруж', 'gun', 'пистолет', 'drug', 'наркот', 'kill', 'убий',
    'murder', 'rape', 'terror', 'террор', 'war', 'войн', 'putin',
    'путин', 'trump', 'трамп', 'vk', 'вк', 'auto', 'авто', 'admin',
    'support', 'official', 'chernogram',
  ];

  static String? validate(String input, {required bool ru}) {
    final value = input.trim().toLowerCase();
    if (value.length < 4 || value.length > 24) {
      return ru
          ? 'Никнейм должен содержать от 4 до 24 символов.'
          : 'Nickname must contain 4–24 characters.';
    }
    if (!RegExp(r'^[a-zа-яё0-9_.]+$', caseSensitive: false)
        .hasMatch(value)) {
      return ru
          ? 'Разрешены буквы, цифры, точка и подчёркивание.'
          : 'Use letters, numbers, a dot or underscore.';
    }
    final compact = value.replaceAll(RegExp(r'[._0-9]'), '');
    for (final root in blockedRoots) {
      if (value.contains(root) || compact.contains(root)) {
        return ru
            ? 'Этот никнейм или его часть запрещены.'
            : 'This nickname or part of it is not allowed.';
      }
    }
    return null;
  }
}

class ChernogramProfile {
  final String id;
  final String nickname;
  final DateTime createdAt;

  const ChernogramProfile({
    required this.id,
    required this.nickname,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChernogramProfile.fromJson(Map<String, dynamic> json) => ChernogramProfile(
        id: json['id']?.toString() ?? _randomId(12),
        nickname: json['nickname']?.toString() ?? 'user',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

enum AttachmentKind { image, video, audio, voice, document, archive, other }

AttachmentKind attachmentKindFor(String name, {bool voice = false}) {
  if (voice) return AttachmentKind.voice;
  final ext = name.split('.').last.toLowerCase();
  if (<String>{'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp'}.contains(ext)) {
    return AttachmentKind.image;
  }
  if (<String>{'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'}.contains(ext)) {
    return AttachmentKind.video;
  }
  if (<String>{'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus'}.contains(ext)) {
    return AttachmentKind.audio;
  }
  if (<String>{'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) {
    return AttachmentKind.archive;
  }
  if (<String>{'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'json'}.contains(ext)) {
    return AttachmentKind.document;
  }
  return AttachmentKind.other;
}

class TunnelAttachment {
  final String id;
  final String path;
  final String name;
  final int size;
  final AttachmentKind kind;

  const TunnelAttachment({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.kind,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'size': size,
        'kind': kind.name,
      };

  factory TunnelAttachment.fromJson(Map<String, dynamic> json) => TunnelAttachment(
        id: json['id']?.toString() ?? _randomId(),
        path: json['path']?.toString() ?? '',
        name: json['name']?.toString() ?? 'file',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        kind: AttachmentKind.values.firstWhere(
          (kind) => kind.name == json['kind']?.toString(),
          orElse: () => attachmentKindFor(json['name']?.toString() ?? ''),
        ),
      );
}

class ChernogramMessage {
  final String id;
  final String author;
  final String text;
  final DateTime sentAt;
  final TunnelAttachment? attachment;

  const ChernogramMessage({
    required this.id,
    required this.author,
    required this.text,
    required this.sentAt,
    this.attachment,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'text': text,
        'sentAt': sentAt.toIso8601String(),
        if (attachment != null) 'attachment': attachment!.toJson(),
      };

  factory ChernogramMessage.fromJson(Map<String, dynamic> json) => ChernogramMessage(
        id: json['id']?.toString() ?? _randomId(),
        author: json['author']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '') ?? DateTime.now(),
        attachment: json['attachment'] is Map
            ? TunnelAttachment.fromJson(Map<String, dynamic>.from(json['attachment'] as Map))
            : null,
      );
}

class ChernogramTunnel {
  final String id;
  final String name;
  final bool isPublic;
  final String ownerId;
  final String inviteSecret;
  final DateTime createdAt;
  final List<ChernogramMessage> messages;

  const ChernogramTunnel({
    required this.id,
    required this.name,
    required this.isPublic,
    required this.ownerId,
    required this.inviteSecret,
    required this.createdAt,
    required this.messages,
  });

  ChernogramTunnel copyWith({
    String? name,
    bool? isPublic,
    String? inviteSecret,
    List<ChernogramMessage>? messages,
  }) =>
      ChernogramTunnel(
        id: id,
        name: name ?? this.name,
        isPublic: isPublic ?? this.isPublic,
        ownerId: ownerId,
        inviteSecret: inviteSecret ?? this.inviteSecret,
        createdAt: createdAt,
        messages: messages ?? this.messages,
      );

  String get inviteToken {
    final payload = jsonEncode({
      'v': 1,
      'id': id,
      'name': name,
      'owner': ownerId,
      'secret': inviteSecret,
      'public': isPublic,
    });
    return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  }

  String get landingUrl => '$temporaryLandingBase?invite=${Uri.encodeQueryComponent(inviteToken)}';
  String get deepLink => 'chernogram://join/$inviteToken';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isPublic': isPublic,
        'ownerId': ownerId,
        'inviteSecret': inviteSecret,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ChernogramTunnel.fromJson(Map<String, dynamic> json) => ChernogramTunnel(
        id: json['id']?.toString() ?? _randomId(),
        name: json['name']?.toString() ?? 'Tunnel',
        isPublic: json['isPublic'] == true,
        ownerId: json['ownerId']?.toString() ?? '',
        inviteSecret: json['inviteSecret']?.toString() ?? _randomId(28),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        messages: ((json['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => ChernogramMessage.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );

  static ChernogramTunnel? fromInviteToken(String token) {
    try {
      var normalized = token.trim();
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final id = map['id']?.toString() ?? '';
      final secret = map['secret']?.toString() ?? '';
      if (id.isEmpty || secret.isEmpty) return null;
      return ChernogramTunnel(
        id: id,
        name: map['name']?.toString() ?? 'Remote tunnel',
        isPublic: map['public'] == true,
        ownerId: map['owner']?.toString() ?? '',
        inviteSecret: secret,
        createdAt: DateTime.now(),
        messages: const [],
      );
    } catch (_) {
      return null;
    }
  }
}

class ChernogramStore {
  static const profileKey = 'chernogram_profile_v1';
  static const tunnelsKey = 'chernogram_tunnels_v1';

  static Future<ChernogramProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(profileKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? ChernogramProfile.fromJson(Map<String, dynamic>.from(decoded)) : null;
  }

  static Future<void> saveProfile(ChernogramProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profileKey, jsonEncode(profile.toJson()));
  }

  static Future<List<ChernogramTunnel>> loadTunnels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(tunnelsKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => ChernogramTunnel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<void> saveTunnels(List<ChernogramTunnel> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tunnelsKey, jsonEncode(tunnels.map((item) => item.toJson()).toList()));
  }
}

class ChernogramV06 extends StatefulWidget {
  final bool ru;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;
  final bool darkMode;
  final VoidCallback onToggleTheme;

  const ChernogramV06({
    super.key,
    required this.ru,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
    required this.darkMode,
    required this.onToggleTheme,
  });

  @override
  State<ChernogramV06> createState() => _ChernogramV06State();
}

class _ChernogramV06State extends State<ChernogramV06> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  ChernogramProfile? _profile;
  List<ChernogramTunnel> _tunnels = [];
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _listenLinks();
  }

  Future<void> _load() async {
    final profile = await ChernogramStore.loadProfile();
    final tunnels = await ChernogramStore.loadTunnels();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _tunnels = tunnels;
      _loading = false;
    });
  }

  Future<void> _listenLinks() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) WidgetsBinding.instance.addPostFrameCallback((_) => _handleUri(initial));
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleUri);
  }

  String? _tokenFromUri(Uri uri) {
    if (uri.scheme == 'chernogram' && uri.host == 'join' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    if (uri.queryParameters['invite']?.isNotEmpty == true) return uri.queryParameters['invite'];
    return null;
  }

  Future<void> _handleUri(Uri uri) async {
    final token = _tokenFromUri(uri);
    if (token == null || !mounted) return;
    await _joinToken(token);
  }

  Future<void> _joinToken(String token) async {
    final tunnel = ChernogramTunnel.fromInviteToken(token);
    if (tunnel == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.ru ? 'QR не является приглашением Чернограма.' : 'This QR is not a Chernogram invite.')),
        );
      }
      return;
    }
    if (_tunnels.any((item) => item.id == tunnel.id)) {
      setState(() => _tab = 0);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Подключиться к туннелю?' : 'Join this tunnel?'),
        content: Text(
          widget.ru
              ? '«${tunnel.name}»\n${tunnel.isPublic ? 'Публичный доступ' : 'Владелец должен подтвердить запрос'}'
              : '“${tunnel.name}”\n${tunnel.isPublic ? 'Public access' : 'The owner must approve your request'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.ru ? 'Отмена' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(widget.ru ? 'Подключиться' : 'Join')),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() {
      _tunnels.insert(0, tunnel);
      _tab = 0;
    });
    await ChernogramStore.saveTunnels(_tunnels);
  }

  Future<void> _scan() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ChernogramScanner(ru: widget.ru)),
    );
    if (token != null) await _joinToken(token);
  }

  Future<void> _saveProfile(ChernogramProfile profile) async {
    await ChernogramStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _saveTunnels(List<ChernogramTunnel> tunnels) async {
    await ChernogramStore.saveTunnels(tunnels);
    if (mounted) setState(() => _tunnels = tunnels);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: ChernogramLogo(size: 118, withPlate: true)));
    }
    final pages = [
      TunnelsV06Screen(
        ru: widget.ru,
        profile: _profile,
        tunnels: _tunnels,
        onChanged: _saveTunnels,
        onScan: _scan,
      ),
      FilesV06Screen(ru: widget.ru, tunnels: _tunnels),
      DevicesV06Screen(ru: widget.ru, profile: _profile),
      ProfileV06Screen(
        ru: widget.ru,
        profile: _profile,
        onSave: _saveProfile,
        onChangeLanguage: widget.onChangeLanguage,
        onCheckUpdates: widget.onCheckUpdates,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: BrandHeader(
          subtitle: widget.ru ? 'ПРИВАТНАЯ СЕТЬ ВАШИХ УСТРОЙСТВ' : 'YOUR PRIVATE DEVICE NETWORK',
        ),
        actions: [
          IconButton(
            tooltip: widget.darkMode
                ? (widget.ru ? 'Светлая тема' : 'Light theme')
                : (widget.ru ? 'Тёмная тема' : 'Dark theme'),
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.darkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.cable_outlined), selectedIcon: const Icon(Icons.cable), label: widget.ru ? 'Туннели' : 'Tunnels'),
          NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder), label: widget.ru ? 'Файлы' : 'Files'),
          NavigationDestination(icon: const Icon(Icons.devices_other_outlined), selectedIcon: const Icon(Icons.devices), label: widget.ru ? 'Устройства' : 'Devices'),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: widget.ru ? 'Профиль' : 'Profile'),
        ],
      ),
    );
  }
}

class TunnelsV06Screen extends StatelessWidget {
  final bool ru;
  final ChernogramProfile? profile;
  final List<ChernogramTunnel> tunnels;
  final ValueChanged<List<ChernogramTunnel>> onChanged;
  final VoidCallback onScan;

  const TunnelsV06Screen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.onChanged,
    required this.onScan,
  });

  Future<void> _create(BuildContext context) async {
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ru ? 'Сначала создайте профиль.' : 'Create your profile first.')),
      );
      return;
    }
    final controller = TextEditingController();
    var isPublic = false;
    final data = await showModalBottomSheet<(String, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ru ? 'Новый туннель' : 'New tunnel', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: ru ? 'Название' : 'Name')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isPublic,
                onChanged: (value) => setState(() => isPublic = value),
                title: Text(ru ? 'Публичный туннель' : 'Public tunnel'),
                subtitle: Text(isPublic
                    ? (ru ? 'Любой с действующим приглашением войдёт сразу.' : 'Anyone with a valid invite can join immediately.')
                    : (ru ? 'Каждый вход подтверждает владелец.' : 'The owner approves every join request.')),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.length >= 3) Navigator.pop(context, (name, isPublic));
                  },
                  child: Text(ru ? 'Создать' : 'Create'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (data == null) return;
    final tunnel = ChernogramTunnel(
      id: _randomId(14),
      name: data.$1,
      isPublic: data.$2,
      ownerId: profile!.id,
      inviteSecret: _randomId(32),
      createdAt: DateTime.now(),
      messages: const [],
    );
    onChanged([tunnel, ...tunnels]);
  }

  Future<void> _open(BuildContext context, ChernogramTunnel tunnel) async {
    if (profile == null) return;
    final updated = await Navigator.push<ChernogramTunnel>(
      context,
      MaterialPageRoute(builder: (_) => TunnelChatV06(ru: ru, profile: profile!, tunnel: tunnel)),
    );
    if (updated == null) return;
    final copy = [...tunnels];
    final index = copy.indexWhere((item) => item.id == updated.id);
    if (index >= 0) copy[index] = updated;
    onChanged(copy);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF351705), Color(0xFF17110D)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ru ? 'Туннели Чернограма' : 'Chernogram tunnels', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                ru ? 'Чат, любые файлы, звонки и доступ к устройствам без центрального хранилища контента.' : 'Chat, any files, calls and device access without central content storage.',
                style: const TextStyle(color: ChernogramColors.textSoft),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _create(context),
                      icon: const Icon(Icons.add),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          ru ? 'Создать туннель' : 'Create tunnel',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          ru ? 'Сканировать QR' : 'Scan QR',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (tunnels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 70),
            child: Column(
              children: [
                const Icon(Icons.cable_outlined, size: 72, color: Colors.white24),
                const SizedBox(height: 12),
                Text(ru ? 'Создайте первый туннель' : 'Create your first tunnel', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          )
        else
          for (final tunnel in tunnels)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: tunnel.isPublic ? ChernogramColors.orange : ChernogramColors.gold,
                  child: Icon(tunnel.isPublic ? Icons.public : Icons.lock_outline),
                ),
                title: Text(tunnel.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${tunnel.isPublic ? (ru ? 'Публичный' : 'Public') : (ru ? 'Приватный' : 'Private')} • ${tunnel.messages.length}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, tunnel),
              ),
            ),
      ],
    );
  }
}

class TunnelChatV06 extends StatefulWidget {
  final bool ru;
  final ChernogramProfile profile;
  final ChernogramTunnel tunnel;

  const TunnelChatV06({super.key, required this.ru, required this.profile, required this.tunnel});

  @override
  State<TunnelChatV06> createState() => _TunnelChatV06State();
}

class _TunnelChatV06State extends State<TunnelChatV06> {
  final TextEditingController _text = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  late ChernogramTunnel _tunnel;
  TunnelPermissions _permissions = const TunnelPermissions();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _tunnel = widget.tunnel;
    _loadPermissions();
  }

  Future<void> _persist() async {
    final tunnels = await ChernogramStore.loadTunnels();
    final index = tunnels.indexWhere((item) => item.id == _tunnel.id);
    if (index >= 0) {
      tunnels[index] = _tunnel;
    } else {
      tunnels.insert(0, _tunnel);
    }
    await ChernogramStore.saveTunnels(tunnels);
  }

  void _addMessage(ChernogramMessage message) {
    setState(() => _tunnel = _tunnel.copyWith(messages: [..._tunnel.messages, message]));
    unawaited(_persist());
  }

  void _sendText() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    _addMessage(ChernogramMessage(id: _randomId(), author: widget.profile.nickname, text: value, sentAt: DateTime.now()));
    _text.clear();
  }

  Future<void> _pickFiles({FileType type = FileType.any, List<String>? extensions}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: extensions == null ? type : FileType.custom,
      allowedExtensions: extensions,
      withData: false,
    );
    if (result == null) return;
    for (final file in result.files) {
      if (file.path == null) continue;
      final attachment = TunnelAttachment(
        id: _randomId(),
        path: file.path!,
        name: file.name,
        size: file.size,
        kind: attachmentKindFor(file.name),
      );
      _addMessage(ChernogramMessage(
        id: _randomId(),
        author: widget.profile.nickname,
        text: '',
        sentAt: DateTime.now(),
        attachment: attachment,
      ));
    }
  }

  Future<void> _showAttachmentMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          children: [
            _AttachAction(icon: Icons.image_outlined, label: widget.ru ? 'Фото' : 'Photo', onTap: () { Navigator.pop(context); _pickFiles(extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic']); }),
            _AttachAction(icon: Icons.movie_outlined, label: widget.ru ? 'Видео' : 'Video', onTap: () { Navigator.pop(context); _pickFiles(extensions: ['mp4', 'mov', 'mkv', 'webm']); }),
            _AttachAction(icon: Icons.music_note, label: widget.ru ? 'Музыка' : 'Music', onTap: () { Navigator.pop(context); _pickFiles(extensions: ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg']); }),
            _AttachAction(icon: Icons.description_outlined, label: widget.ru ? 'Документ' : 'Document', onTap: () { Navigator.pop(context); _pickFiles(extensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']); }),
            _AttachAction(icon: Icons.folder_zip_outlined, label: widget.ru ? 'Архив' : 'Archive', onTap: () { Navigator.pop(context); _pickFiles(extensions: ['zip', 'rar', '7z', 'tar', 'gz']); }),
            _AttachAction(icon: Icons.folder_open, label: widget.ru ? 'Любой файл' : 'Any file', onTap: () { Navigator.pop(context); _pickFiles(); }),
          ],
        ),
      ),
    );
  }

  Future<void> _startVoice() async {
    if (_recording) return;
    if (!await _recorder.hasPermission()) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stopVoice() async {
    if (!_recording) return;
    final path = await _recorder.stop();
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    final attachment = TunnelAttachment(
      id: _randomId(),
      path: path,
      name: path.split(Platform.pathSeparator).last,
      size: await file.length(),
      kind: AttachmentKind.voice,
    );
    _addMessage(ChernogramMessage(
      id: _randomId(),
      author: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      attachment: attachment,
    ));
  }

  Future<void> _loadPermissions() async {
    final value =
        await LocalTunnelExtrasStore.loadPermissions(_tunnel.id);
    if (mounted) setState(() => _permissions = value);
  }

  String get _inviteText => widget.ru
      ? 'Присоединяйся к моему туннелю «${_tunnel.name}» в Чернограме: ${_tunnel.landingUrl}'
      : 'Join my Chernogram tunnel “${_tunnel.name}”: ${_tunnel.landingUrl}';

  Future<void> _copyInvite() async {
    await Clipboard.setData(ClipboardData(text: _tunnel.landingUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru ? 'Ссылка приглашения скопирована' : 'Invite link copied',
        ),
      ),
    );
  }

  Future<void> _inviteContacts() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InviteContactsSheetV061(
        ru: widget.ru,
        inviteText: _inviteText,
      ),
    );
  }

  Future<void> _settings() async {
    var isPublic = _tunnel.isPublic;
    var revoke = false;
    var permissions = _permissions;
    final updated = await showModalBottomSheet<
        ({bool isPublic, bool revoke, TunnelPermissions permissions})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Widget permissionTile({
            required IconData icon,
            required String titleRu,
            required String titleEn,
            required bool value,
            required ValueChanged<bool> onChanged,
          }) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(icon),
              value: value,
              onChanged: (next) {
                onChanged(next);
                setSheetState(() {});
              },
              title: Text(widget.ru ? titleRu : titleEn),
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                18 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.ru ? 'Настройки туннеля' : 'Tunnel settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      isPublic ? Icons.public : Icons.lock_outline,
                    ),
                    value: isPublic,
                    onChanged: (value) =>
                        setSheetState(() => isPublic = value),
                    title: Text(
                      widget.ru ? 'Публичный туннель' : 'Public tunnel',
                    ),
                    subtitle: Text(
                      isPublic
                          ? (widget.ru
                              ? 'Вход по действующему QR без подтверждения.'
                              : 'Join with a valid QR without approval.')
                          : (widget.ru
                              ? 'Новые участники отправляют запрос владельцу.'
                              : 'New participants request owner approval.'),
                    ),
                  ),
                  const Divider(),
                  Text(
                    widget.ru ? 'Права участников' : 'Participant permissions',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  permissionTile(
                    icon: Icons.chat_bubble_outline,
                    titleRu: 'Писать сообщения',
                    titleEn: 'Send messages',
                    value: permissions.canWriteMessages,
                    onChanged: (next) => permissions = permissions.copyWith(
                      canWriteMessages: next,
                    ),
                  ),
                  permissionTile(
                    icon: Icons.attach_file,
                    titleRu: 'Отправлять медиа и файлы',
                    titleEn: 'Send media and files',
                    value: permissions.canSendMedia,
                    onChanged: (next) => permissions = permissions.copyWith(
                      canSendMedia: next,
                    ),
                  ),
                  permissionTile(
                    icon: Icons.download_outlined,
                    titleRu: 'Скачивать файлы',
                    titleEn: 'Download files',
                    value: permissions.canDownload,
                    onChanged: (next) => permissions = permissions.copyWith(
                      canDownload: next,
                    ),
                  ),
                  permissionTile(
                    icon: Icons.person_add_alt_1_outlined,
                    titleRu: 'Приглашать других',
                    titleEn: 'Invite others',
                    value: permissions.canInvite,
                    onChanged: (next) => permissions = permissions.copyWith(
                      canInvite: next,
                    ),
                  ),
                  permissionTile(
                    icon: Icons.history,
                    titleRu: 'Видеть прошлую историю',
                    titleEn: 'See previous history',
                    value: permissions.canSeeHistory,
                    onChanged: (next) => permissions = permissions.copyWith(
                      canSeeHistory: next,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: revoke,
                    onChanged: (value) =>
                        setSheetState(() => revoke = value ?? false),
                    title: Text(
                      widget.ru
                          ? 'Отозвать старые QR и ссылки'
                          : 'Revoke old QR codes and links',
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _inviteContacts,
                      icon: const Icon(Icons.contacts_outlined),
                      label: Text(
                        widget.ru
                            ? 'Пригласить из телефонной книги'
                            : 'Invite from contacts',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        (
                          isPublic: isPublic,
                          revoke: revoke,
                          permissions: permissions,
                        ),
                      ),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(widget.ru ? 'Сохранить' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (updated == null) return;
    setState(() {
      _tunnel = _tunnel.copyWith(
        isPublic: updated.isPublic,
        inviteSecret:
            updated.revoke ? _randomId(32) : _tunnel.inviteSecret,
      );
      _permissions = updated.permissions;
    });
    await LocalTunnelExtrasStore.savePermissions(
      _tunnel.id,
      updated.permissions,
    );
    await _persist();
  }

  Future<void> _showQr() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'QR туннеля' : 'Tunnel QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: _tunnel.landingUrl, size: 230),
            ),
            const SizedBox(height: 10),
            Text(
              widget.ru
                  ? 'Если Чернограм установлен — страница откроет приложение. Иначе предложит APK для Android.'
                  : 'If Chernogram is installed, the page opens the app. Otherwise it offers the Android APK.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: ChernogramColors.textSoft),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: _tunnel.landingUrl)), child: Text(widget.ru ? 'Копировать' : 'Copy')),
          FilledButton(onPressed: () => Share.share(_tunnel.landingUrl), child: Text(widget.ru ? 'Поделиться' : 'Share')),
        ],
      ),
    );
  }

  void _openCall(bool video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChernogramCallScreen(tunnelName: _tunnel.name, video: video, ru: widget.ru)),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_persist());
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
              Text(_tunnel.name, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                _tunnel.isPublic ? (widget.ru ? 'Публичный • локальный режим' : 'Public • local mode') : (widget.ru ? 'Приватный • по запросу' : 'Private • approval required'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
          actions: [
            IconButton(onPressed: () => _openCall(false), icon: const Icon(Icons.call_outlined)),
            IconButton(onPressed: () => _openCall(true), icon: const Icon(Icons.videocam_outlined)),
            IconButton(
              tooltip: widget.ru ? 'Пригласить' : 'Invite',
              onPressed: _inviteContacts,
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
            IconButton(onPressed: _showQr, icon: const Icon(Icons.qr_code_2)),
            IconButton(onPressed: _settings, icon: const Icon(Icons.tune)),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.link,
                        color: ChernogramColors.goldLight,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _tunnel.landingUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      TextButton(
                        onPressed: _copyInvite,
                        child: Text(widget.ru ? 'Копировать' : 'Copy'),
                      ),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _inviteContacts,
                        icon: const Icon(Icons.contacts_outlined),
                        label: Text(widget.ru ? 'Контакты' : 'Contacts'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Share.share(_inviteText),
                        icon: const Icon(Icons.share_outlined),
                        label: Text(widget.ru ? 'Поделиться' : 'Share'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: ChernogramColors.goldLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.ru ? 'Контент хранится на устройствах. P2P-синхронизация подключается следующим сетевым этапом.' : 'Content stays on devices. P2P sync is the next network stage.',
                      style: const TextStyle(fontSize: 11, color: ChernogramColors.textSoft),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                itemCount: _tunnel.messages.length,
                itemBuilder: (context, index) {
                  final message = _tunnel.messages[index];
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: const Color(0xFF633013), borderRadius: BorderRadius.circular(17)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.attachment != null) AttachmentPreview(attachment: message.attachment!, ru: widget.ru),
                          if (message.text.isNotEmpty) ...[
                            if (message.attachment != null) const SizedBox(height: 7),
                            Text(message.text),
                          ],
                          const SizedBox(height: 4),
                          Text('${message.author} • ${TimeOfDay.fromDateTime(message.sentAt).format(context)}', style: const TextStyle(fontSize: 9, color: Colors.white38)),
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
                    IconButton.filledTonal(onPressed: _showAttachmentMenu, icon: const Icon(Icons.add)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(hintText: _recording ? (widget.ru ? 'Запись голосового…' : 'Recording voice…') : (widget.ru ? 'Сообщение…' : 'Message…'), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 7),
                    GestureDetector(
                      onLongPressStart: (_) => _startVoice(),
                      onLongPressEnd: (_) => _stopVoice(),
                      child: IconButton.filled(
                        onPressed: _sendText,
                        icon: Icon(_recording ? Icons.mic : Icons.send),
                      ),
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

class _AttachAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 31), const SizedBox(height: 6), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))]),
      );
}

class AttachmentPreview extends StatelessWidget {
  final TunnelAttachment attachment;
  final bool ru;

  const AttachmentPreview({super.key, required this.attachment, required this.ru});

  @override
  Widget build(BuildContext context) {
    final file = File(attachment.path);
    if (!file.existsSync()) {
      return Row(children: [const Icon(Icons.delete_outline), const SizedBox(width: 8), Expanded(child: Text(ru ? 'Файл удалён с устройства' : 'File was removed from device'))]);
    }
    if (attachment.kind == AttachmentKind.image) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(file, width: 250, height: 190, fit: BoxFit.cover));
    }
    if (attachment.kind == AttachmentKind.audio || attachment.kind == AttachmentKind.voice) {
      return AudioAttachmentTile(attachment: attachment);
    }
    final icon = switch (attachment.kind) {
      AttachmentKind.video => Icons.movie_outlined,
      AttachmentKind.document => Icons.description_outlined,
      AttachmentKind.archive => Icons.folder_zip_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return Row(
      children: [
        Icon(icon, size: 38),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(attachment.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), Text(_fileSize(attachment.size), style: const TextStyle(fontSize: 10, color: Colors.white54))])),
      ],
    );
  }
}

class AudioAttachmentTile extends StatefulWidget {
  final TunnelAttachment attachment;

  const AudioAttachmentTile({super.key, required this.attachment});

  @override
  State<AudioAttachmentTile> createState() => _AudioAttachmentTileState();
}

class _AudioAttachmentTileState extends State<AudioAttachmentTile> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_player.audioSource == null) await _player.setFilePath(widget.attachment.path);
      await _player.play();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconButton.filledTonal(onPressed: _toggle, icon: Icon(_playing ? Icons.pause : Icons.play_arrow)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.attachment.kind == AttachmentKind.voice ? 'Voice message' : widget.attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), Text(_fileSize(widget.attachment.size), style: const TextStyle(fontSize: 10, color: Colors.white54))])),
        ],
      );
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class ChernogramScanner extends StatefulWidget {
  final bool ru;

  const ChernogramScanner({super.key, required this.ru});

  @override
  State<ChernogramScanner> createState() => _ChernogramScannerState();
}

class _ChernogramScannerState extends State<ChernogramScanner> {
  bool _handled = false;

  String? _extract(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      if (uri.scheme == 'chernogram' && uri.host == 'join' && uri.pathSegments.isNotEmpty) return uri.pathSegments.first;
      if (uri.queryParameters['invite']?.isNotEmpty == true) return uri.queryParameters['invite'];
    }
    if (ChernogramTunnel.fromInviteToken(value) != null) return value;
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
        appBar: AppBar(title: Text(widget.ru ? 'Сканировать туннель' : 'Scan a tunnel')),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(onDetect: _detect),
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(border: Border.all(color: ChernogramColors.goldLight, width: 3), borderRadius: BorderRadius.circular(28)),
              ),
            ),
          ],
        ),
      );
}

class FilesV06Screen extends StatelessWidget {
  final bool ru;
  final List<ChernogramTunnel> tunnels;

  const FilesV06Screen({super.key, required this.ru, required this.tunnels});

  @override
  Widget build(BuildContext context) {
    final attachments = tunnels.expand((tunnel) => tunnel.messages).map((message) => message.attachment).whereType<TunnelAttachment>().toList().reversed.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      children: [
        Text(ru ? 'Файлы ваших туннелей' : 'Files in your tunnels', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(ru ? 'Чернограм хранит ссылки на локальные оригиналы. Если оригинал удалён — предпросмотр исчезает.' : 'Chernogram keeps local references. If the original is removed, the preview disappears.', style: const TextStyle(color: ChernogramColors.textSoft)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FileChip(icon: Icons.image_outlined, text: ru ? 'Фото' : 'Photos'),
            _FileChip(icon: Icons.movie_outlined, text: ru ? 'Видео' : 'Videos'),
            _FileChip(icon: Icons.music_note, text: ru ? 'Музыка' : 'Music'),
            _FileChip(icon: Icons.description_outlined, text: ru ? 'Документы' : 'Documents'),
            _FileChip(icon: Icons.folder_zip_outlined, text: ru ? 'Архивы' : 'Archives'),
          ],
        ),
        const SizedBox(height: 18),
        if (attachments.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.only(top: 70), child: Text(ru ? 'В туннелях пока нет файлов.' : 'There are no tunnel files yet.')))
        else
          for (final attachment in attachments)
            Card(
              child: ListTile(
                leading: Icon(attachment.kind == AttachmentKind.audio || attachment.kind == AttachmentKind.voice ? Icons.music_note : attachment.kind == AttachmentKind.image ? Icons.image : Icons.insert_drive_file),
                title: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(File(attachment.path).existsSync() ? _fileSize(attachment.size) : (ru ? 'Удалён с устройства' : 'Removed from device')),
              ),
            ),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FileChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(text));
}

class DevicesV06Screen extends StatelessWidget {
  final bool ru;
  final ChernogramProfile? profile;

  const DevicesV06Screen({super.key, required this.ru, required this.profile});

  @override
  Widget build(BuildContext context) {
    final routes = [
      (Icons.wifi, ru ? 'Локальная сеть' : 'Local network', ru ? 'Прямой канал без интернета' : 'Direct connection without internet'),
      (Icons.wifi_tethering, 'Wi‑Fi Direct', ru ? 'Для быстрой передачи рядом' : 'Fast nearby transfers'),
      (Icons.bluetooth, 'Bluetooth', ru ? 'Обнаружение и резерв для малых файлов' : 'Discovery and small-file fallback'),
      (Icons.public, 'WebRTC P2P', ru ? 'Интернет, чат и звонки' : 'Internet, chat and calls'),
      (Icons.swap_horiz, 'Relay', ru ? 'Зашифрованный резерв при сложном NAT' : 'Encrypted fallback behind difficult NAT'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      children: [
        Text(ru ? 'Мои устройства' : 'My devices', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.smartphone)),
            title: Text(ru ? 'Это устройство' : 'This device', style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(profile == null ? (ru ? 'Создайте профиль' : 'Create a profile') : 'ID ${profile!.id}'),
            trailing: const Chip(label: Text('ONLINE')),
          ),
        ),
        const SizedBox(height: 14),
        Text(ru ? 'Маршруты соединения' : 'Connection routes', style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final route in routes)
          Card(
            child: ListTile(
              leading: Icon(route.$1, color: ChernogramColors.goldLight),
              title: Text(route.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(route.$3),
              trailing: Text(ru ? 'заложено' : 'planned', style: const TextStyle(fontSize: 10, color: ChernogramColors.textSoft)),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          ru ? 'Чернограм будет автоматически выбирать лучший доступный маршрут и переключаться между ними без участия пользователя.' : 'Chernogram will automatically choose the best available route and switch between them.',
          style: const TextStyle(color: ChernogramColors.textSoft),
        ),
      ],
    );
  }
}

class ProfileV06Screen extends StatefulWidget {
  final bool ru;
  final ChernogramProfile? profile;
  final ValueChanged<ChernogramProfile> onSave;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;

  const ProfileV06Screen({
    super.key,
    required this.ru,
    required this.profile,
    required this.onSave,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
  });

  @override
  State<ProfileV06Screen> createState() => _ProfileV06ScreenState();
}

class _ProfileV06ScreenState extends State<ProfileV06Screen> {
  late final TextEditingController _nickname =
      TextEditingController(text: widget.profile?.nickname ?? '');
  String? _error;
  int _avatarRevision = 0;

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
    final nickname = _nickname.text.trim().toLowerCase();
    final error =
        ChernogramNicknameRules.validate(nickname, ru: widget.ru);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onSave(
      ChernogramProfile(
        id: widget.profile?.id ?? _randomId(12),
        nickname: nickname,
        createdAt: widget.profile?.createdAt ?? DateTime.now(),
      ),
    );
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'Профиль сохранён локально.'
              : 'Profile saved locally.',
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
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                LocalProfileAvatar(
                  key: ValueKey(
                    '${widget.profile?.id}:$_avatarRevision',
                  ),
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
                    tooltip: widget.ru
                        ? 'Выбрать аватарку'
                        : 'Choose avatar',
                    onPressed: _chooseAvatar,
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(child: Text(widget.profile == null ? (widget.ru ? 'Локальный профиль' : 'Local profile') : '@${widget.profile!.nickname}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
          if (widget.profile != null) Center(child: SelectableText('ID ${widget.profile!.id}', style: const TextStyle(color: ChernogramColors.goldLight))),
          const SizedBox(height: 20),
          TextField(
            controller: _nickname,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: widget.ru ? 'Никнейм' : 'Nickname',
              prefixText: '@',
              errorText: _error,
              helperText: widget.ru
                  ? 'Стоп-слова и служебные названия блокируются.'
                  : 'Restricted and reserved terms are blocked.',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(widget.ru ? 'Сохранить профиль' : 'Save profile')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: widget.onCheckUpdates, icon: const Icon(Icons.system_update_alt), label: Text(widget.ru ? 'Проверить обновления' : 'Check updates')),
          OutlinedButton.icon(onPressed: widget.onChangeLanguage, icon: const Icon(Icons.language), label: Text(widget.ru ? 'English' : 'Русский')),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.ru
                    ? 'Профиль и контент сейчас хранятся локально. Сетевой реестр будет хранить только ID устройств, публичные ключи и краткоживущие данные соединения — без файлов и переписки.'
                    : 'Profile and content are local. The network registry will keep only device IDs, public keys and short-lived connection data — never files or chat history.',
                style: const TextStyle(color: ChernogramColors.textSoft),
              ),
            ),
          ),
        ],
      );
}


class InviteContactsSheetV061 extends StatefulWidget {
  final bool ru;
  final String inviteText;

  const InviteContactsSheetV061({
    super.key,
    required this.ru,
    required this.inviteText,
  });

  @override
  State<InviteContactsSheetV061> createState() =>
      _InviteContactsSheetV061State();
}

class _InviteContactsSheetV061State
    extends State<InviteContactsSheetV061> {
  final TextEditingController _search = TextEditingController();
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
      if (mounted) {
        setState(() {
          _loading = false;
          _denied = true;
        });
      }
      return;
    }
    final contacts =
        await FlutterContacts.getContacts(withProperties: true);
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loading = false;
    });
  }

  Future<void> _invite(Contact contact) async {
    final phone =
        contact.phones.isEmpty ? null : contact.phones.first.number;
    if (phone == null || phone.trim().isEmpty) {
      await Share.share(widget.inviteText);
      return;
    }
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': widget.inviteText},
    );
    final opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) await Share.share(widget.inviteText);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _contacts
        : _contacts
            .where(
              (contact) =>
                  contact.displayName.toLowerCase().contains(query),
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
              widget.ru
                  ? 'Пригласить из контактов'
                  : 'Invite from contacts',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText:
                    widget.ru ? 'Найти человека' : 'Find a person',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _denied
                      ? Center(
                          child: Text(
                            widget.ru
                                ? 'Доступ к контактам не разрешён. Используйте системное меню «Поделиться».'
                                : 'Contacts permission was denied. Use the system Share menu.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, index) {
                            final contact = visible[index];
                            final name = contact.displayName.trim();
                            final letter =
                                name.isEmpty ? '?' : name[0].toUpperCase();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    ChernogramColors.orangeDeep,
                                child: Text(letter),
                              ),
                              title: Text(contact.displayName),
                              subtitle: contact.phones.isEmpty
                                  ? null
                                  : Text(contact.phones.first.number),
                              trailing:
                                  const Icon(Icons.send_outlined),
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
                  widget.ru
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
