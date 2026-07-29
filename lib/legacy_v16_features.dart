import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'core_models.dart';

class CgV16FeatureStore {
  static const String _permissionKey = 'cg_v16_permission_switches';
  static const String _privacyKey = 'cg_v16_privacy_settings';
  static const String _sessionsKey = 'cg_v16_active_sessions';

  static Future<Map<String, bool>> loadPermissionSwitches() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, bool>{
      'messages': true,
      'notifications': true,
      'microphone': true,
      'camera': true,
      'voice': true,
      'location': true,
      'vibration': true,
      'media': true,
    };
    final raw = prefs.getString(_permissionKey);
    if (raw == null) return result;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          result[entry.key.toString()] = entry.value == true;
        }
      }
    } catch (_) {}
    return result;
  }

  static Future<void> savePermissionSwitches(Map<String, bool> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_permissionKey, jsonEncode(values));
  }

  static Future<Map<String, dynamic>> loadPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{
      'phone': 'contacts',
      'lastSeen': 'everyone',
      'calls': 'everyone',
      'groups': 'everyone',
      'readReceipts': true,
    };
    final raw = prefs.getString(_privacyKey);
    if (raw == null) return result;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) result.addAll(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return result;
  }

  static Future<void> savePrivacy(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_privacyKey, jsonEncode(values));
  }

  static Future<List<CgV16Session>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null) return <CgV16Session>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => CgV16Session.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}
    return <CgV16Session>[];
  }

  static Future<void> saveSessions(List<CgV16Session> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionsKey,
      jsonEncode(values.map((item) => item.toJson()).toList()),
    );
  }

  static String currentDeviceId(String profileId) =>
      '${Platform.operatingSystem}:$profileId';

  static String currentDeviceName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    return Platform.operatingSystem;
  }

  static Future<List<CgV16Session>> touchCurrentSession(
    String profileId,
  ) async {
    final sessions = await loadSessions();
    final id = currentDeviceId(profileId);
    final index = sessions.indexWhere((item) => item.id == id);
    final current = CgV16Session(
      id: id,
      name: currentDeviceName(),
      platform: Platform.operatingSystem,
      current: true,
      lastSeenAt: DateTime.now(),
    );
    for (var i = 0; i < sessions.length; i++) {
      sessions[i] = sessions[i].copyWith(current: false);
    }
    if (index < 0) {
      sessions.insert(0, current);
    } else {
      sessions[index] = current;
    }
    await saveSessions(sessions);
    return sessions;
  }
}

class CgV16Session {
  final String id;
  final String name;
  final String platform;
  final bool current;
  final DateTime lastSeenAt;

  const CgV16Session({
    required this.id,
    required this.name,
    required this.platform,
    required this.current,
    required this.lastSeenAt,
  });

  CgV16Session copyWith({bool? current, DateTime? lastSeenAt}) => CgV16Session(
    id: id,
    name: name,
    platform: platform,
    current: current ?? this.current,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'platform': platform,
    'current': current,
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
  };

  factory CgV16Session.fromJson(Map<String, dynamic> json) => CgV16Session(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Device',
    platform: json['platform']?.toString() ?? '',
    current: json['current'] == true,
    lastSeenAt:
        DateTime.tryParse(json['lastSeenAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

class _CgPermissionSpec {
  final String id;
  final IconData icon;
  final String titleRu;
  final String titleEn;
  final String subtitleRu;
  final String subtitleEn;
  final List<Permission> permissions;

  const _CgPermissionSpec({
    required this.id,
    required this.icon,
    required this.titleRu,
    required this.titleEn,
    required this.subtitleRu,
    required this.subtitleEn,
    this.permissions = const <Permission>[],
  });
}

class CgV16PermissionsScreen extends StatefulWidget {
  final bool ru;

  const CgV16PermissionsScreen({super.key, required this.ru});

  @override
  State<CgV16PermissionsScreen> createState() =>
      _CgV16PermissionsScreenState();
}

class _CgV16PermissionsScreenState extends State<CgV16PermissionsScreen>
    with WidgetsBindingObserver {
  static const List<_CgPermissionSpec> _items = <_CgPermissionSpec>[
    _CgPermissionSpec(
      id: 'messages',
      icon: Icons.chat_bubble_outline_rounded,
      titleRu: 'Сообщения',
      titleEn: 'Messages',
      subtitleRu: 'Разрешить получать сообщения.',
      subtitleEn: 'Allow incoming messages.',
    ),
    _CgPermissionSpec(
      id: 'notifications',
      icon: Icons.notifications_none_rounded,
      titleRu: 'Уведомления',
      titleEn: 'Notifications',
      subtitleRu: 'Новые сообщения, звонки и события.',
      subtitleEn: 'New messages, calls and events.',
      permissions: <Permission>[Permission.notification],
    ),
    _CgPermissionSpec(
      id: 'microphone',
      icon: Icons.mic_none_rounded,
      titleRu: 'Микрофон',
      titleEn: 'Microphone',
      subtitleRu: 'Звонки и голосовые сообщения.',
      subtitleEn: 'Calls and voice messages.',
      permissions: <Permission>[Permission.microphone],
    ),
    _CgPermissionSpec(
      id: 'camera',
      icon: Icons.camera_alt_outlined,
      titleRu: 'Камера и фонарик',
      titleEn: 'Camera and flashlight',
      subtitleRu: 'Видео, QR и управление вспышкой.',
      subtitleEn: 'Video, QR and flash control.',
      permissions: <Permission>[Permission.camera],
    ),
    _CgPermissionSpec(
      id: 'voice',
      icon: Icons.record_voice_over_outlined,
      titleRu: 'Голосовые команды',
      titleEn: 'Voice commands',
      subtitleRu: 'Управление звонками и агентом.',
      subtitleEn: 'Control calls and the agent.',
      permissions: <Permission>[Permission.microphone],
    ),
    _CgPermissionSpec(
      id: 'location',
      icon: Icons.location_on_outlined,
      titleRu: 'Геолокация',
      titleEn: 'Location',
      subtitleRu: 'Маршруты и доверенные места.',
      subtitleEn: 'Routes and trusted places.',
      permissions: <Permission>[Permission.locationWhenInUse],
    ),
    _CgPermissionSpec(
      id: 'vibration',
      icon: Icons.vibration_rounded,
      titleRu: 'Вибрация',
      titleEn: 'Vibration',
      subtitleRu: 'Обратная связь и входящие звонки.',
      subtitleEn: 'Feedback and incoming calls.',
    ),
    _CgPermissionSpec(
      id: 'media',
      icon: Icons.folder_copy_outlined,
      titleRu: 'Файлы и медиатека',
      titleEn: 'Files and media library',
      subtitleRu: 'Отправка и сохранение на устройстве.',
      subtitleEn: 'Send and save on the device.',
      permissions: <Permission>[
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ],
    ),
  ];

  Map<String, bool> _values = <String, bool>{};
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final values = await CgV16FeatureStore.loadPermissionSwitches();
    if (Platform.isAndroid) {
      for (final item in _items) {
        if (item.permissions.isEmpty || values[item.id] != true) continue;
        var granted = true;
        for (final permission in item.permissions) {
          try {
            final status = await permission.status;
            granted = granted &&
                (status.isGranted || status.isLimited || status.isProvisional);
          } catch (_) {}
        }
        if (!granted) values[item.id] = false;
      }
    }
    if (mounted) setState(() => _values = values);
  }

  Future<void> _toggle(_CgPermissionSpec item, bool enabled) async {
    if (_busy.contains(item.id)) return;
    setState(() => _busy.add(item.id));
    try {
      var finalValue = enabled;
      if (Platform.isAndroid && item.permissions.isNotEmpty) {
        if (enabled) {
          for (final permission in item.permissions) {
            try {
              final status = await permission.request();
              if (!(status.isGranted ||
                  status.isLimited ||
                  status.isProvisional)) {
                finalValue = false;
              }
            } catch (_) {}
          }
        } else {
          finalValue = false;
          await openAppSettings();
        }
      }
      _values[item.id] = finalValue;
      await CgV16FeatureStore.savePermissionSwitches(_values);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(ru ? 'Разрешения и приватность' : 'Permissions and privacy'),
        actions: <Widget>[
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.shield_outlined, color: scheme.primary),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
        children: <Widget>[
          for (final item in _items) ...<Widget>[
            Card(
              child: SwitchListTile(
                value: _values[item.id] ?? false,
                onChanged: _busy.contains(item.id)
                    ? null
                    : (value) => _toggle(item, value),
                secondary: _busy.contains(item.id)
                    ? const SizedBox.square(
                        dimension: 23,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(item.icon, color: scheme.primary),
                title: Text(
                  ru ? item.titleRu : item.titleEn,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(ru ? item.subtitleRu : item.subtitleEn),
              ),
            ),
            const SizedBox(height: 5),
          ],
          const SizedBox(height: 12),
          Text(
            ru
                ? 'Настройки применяются только к возможностям приложения. Системные разрешения всегда можно изменить в настройках устройства.'
                : 'These controls apply only to app capabilities. System permissions can always be changed in device settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: .55),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class CgV16TwoDevicesScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;

  const CgV16TwoDevicesScreen({
    super.key,
    required this.ru,
    required this.profile,
  });

  @override
  State<CgV16TwoDevicesScreen> createState() => _CgV16TwoDevicesScreenState();
}

class _CgV16TwoDevicesScreenState extends State<CgV16TwoDevicesScreen> {
  List<CgV16Session> _sessions = <CgV16Session>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final values = await CgV16FeatureStore.touchCurrentSession(widget.profile.id);
    if (mounted) setState(() => _sessions = values);
  }

  String _pairCode() {
    final nonce = List<int>.generate(
      18,
      (_) => Random.secure().nextInt(256),
    );
    final payload = <String, dynamic>{
      'v': 16,
      'kind': 'chernogram-device',
      'profileId': widget.profile.id,
      'nickname': widget.profile.nickname,
      'nonce': base64UrlEncode(nonce),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    return 'CGD1-${base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
  }

  Future<void> _showPairCode() async {
    final code = _pairCode();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.ru ? 'Привязать второе устройство' : 'Link another device',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'Откройте Чернограм на компьютере или втором телефоне и отсканируйте код.'
                    : 'Open Chernogram on the computer or another phone and scan the code.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(data: code, size: 220),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(code),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(widget.ru ? 'Отправить код' : 'Share code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Код второго устройства' : 'Second-device code'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.link_rounded)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(widget.ru ? 'Подключить' : 'Link'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !code.startsWith('CGD1-')) return;
    final values = await CgV16FeatureStore.loadSessions();
    final id = 'paired:${code.hashCode.abs()}';
    if (!values.any((item) => item.id == id)) {
      values.add(
        CgV16Session(
          id: id,
          name: Platform.isAndroid ? 'Windows' : 'Android',
          platform: Platform.isAndroid ? 'windows' : 'android',
          current: false,
          lastSeenAt: DateTime.now(),
        ),
      );
      await CgV16FeatureStore.saveSessions(values);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    final scheme = Theme.of(context).colorScheme;
    final other = _sessions.where((item) => !item.current).toList();
    return Scaffold(
      appBar: AppBar(title: Text(ru ? 'Два устройства' : 'Two devices')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.devices_rounded, color: Colors.white, size: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ru ? 'Один аккаунт — телефон + компьютер' : 'One account — phone + computer',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ru
                            ? 'Диалоги доступны на двух устройствах.'
                            : 'Chats are available on two devices.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DeviceCard(
            icon: Platform.isAndroid ? Icons.smartphone_rounded : Icons.laptop_windows_rounded,
            title: CgV16FeatureStore.currentDeviceName(),
            subtitle: ru ? 'Текущее устройство' : 'Current device',
            active: true,
          ),
          const SizedBox(height: 10),
          if (other.isEmpty)
            _DeviceCard(
              icon: Platform.isAndroid ? Icons.laptop_windows_rounded : Icons.smartphone_rounded,
              title: Platform.isAndroid ? 'Windows' : 'Android',
              subtitle: ru ? 'Не подключено' : 'Not connected',
              active: false,
            )
          else
            for (final session in other)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DeviceCard(
                  icon: session.platform.contains('windows')
                      ? Icons.laptop_windows_rounded
                      : Icons.smartphone_rounded,
                  title: session.name,
                  subtitle: ru ? 'Подключено' : 'Connected',
                  active: true,
                ),
              ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _showPairCode,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text(ru ? 'Привязать устройство' : 'Link device'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _enterCode,
              icon: const Icon(Icons.link_rounded),
              label: Text(ru ? 'Ввести код привязки' : 'Enter link code'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;

  const _DeviceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Icon(icon, size: 38),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: Icon(
        active ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
    ),
  );
}

class CgV16SessionsScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;

  const CgV16SessionsScreen({
    super.key,
    required this.ru,
    required this.profile,
  });

  @override
  State<CgV16SessionsScreen> createState() => _CgV16SessionsScreenState();
}

class _CgV16SessionsScreenState extends State<CgV16SessionsScreen> {
  List<CgV16Session> _sessions = <CgV16Session>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final values = await CgV16FeatureStore.touchCurrentSession(widget.profile.id);
    if (mounted) setState(() => _sessions = values);
  }

  Future<void> _revoke(CgV16Session session) async {
    final values = _sessions.where((item) => item.id != session.id).toList();
    await CgV16FeatureStore.saveSessions(values);
    if (mounted) setState(() => _sessions = values);
  }

  Future<void> _revokeOthers() async {
    final values = _sessions.where((item) => item.current).toList();
    await CgV16FeatureStore.saveSessions(values);
    if (mounted) setState(() => _sessions = values);
  }

  String _time(CgV16Session session) {
    if (session.current) return widget.ru ? 'Сейчас' : 'Now';
    final value = session.lastSeenAt;
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.ru ? 'Активные сессии' : 'Active sessions')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
      children: <Widget>[
        for (final session in _sessions)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: Icon(
                session.platform.contains('windows')
                    ? Icons.laptop_windows_rounded
                    : Icons.smartphone_rounded,
                size: 34,
              ),
              title: Text(
                session.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                session.current
                    ? (widget.ru ? 'Это устройство' : 'This device')
                    : _time(session),
              ),
              trailing: session.current
                  ? const Icon(Icons.check_circle_rounded)
                  : IconButton(
                      tooltip: widget.ru ? 'Завершить' : 'Revoke',
                      onPressed: () => _revoke(session),
                      icon: const Icon(Icons.logout_rounded),
                    ),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _sessions.any((item) => !item.current) ? _revokeOthers : null,
          icon: const Icon(Icons.phonelink_erase_rounded),
          label: Text(
            widget.ru ? 'Завершить все другие сессии' : 'Revoke all other sessions',
          ),
        ),
      ],
    ),
  );
}

class CgV16SystemContactsScreen extends StatefulWidget {
  final bool ru;

  const CgV16SystemContactsScreen({super.key, required this.ru});

  @override
  State<CgV16SystemContactsScreen> createState() =>
      _CgV16SystemContactsScreenState();
}

class _CgV16SystemContactsScreenState
    extends State<CgV16SystemContactsScreen> {
  final TextEditingController _search = TextEditingController();
  List<Contact> _contacts = <Contact>[];
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) {
        setState(() {
          _loading = false;
          _denied = true;
        });
      }
      return;
    }
    final values = await FlutterContacts.getContacts(withProperties: true);
    values.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (mounted) {
      setState(() {
        _contacts = values;
        _loading = false;
        _denied = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final values = _contacts.where((contact) {
      if (query.isEmpty) return true;
      return contact.displayName.toLowerCase().contains(query) ||
          contact.phones.any((phone) => phone.number.contains(query));
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.ru ? 'Системные контакты' : 'System contacts')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.ru ? 'Поиск контактов' : 'Search contacts',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _denied
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.contacts_outlined, size: 64),
                          const SizedBox(height: 12),
                          Text(
                            widget.ru
                                ? 'Разрешите доступ к контактам.'
                                : 'Allow contacts access.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: Text(widget.ru ? 'Разрешить' : 'Allow'),
                          ),
                        ],
                      ),
                    ),
                  )
                : values.isEmpty
                ? Center(
                    child: Text(
                      Platform.isWindows
                          ? (widget.ru
                                ? 'Системная телефонная книга доступна в Android-версии.'
                                : 'The system phone book is available on Android.')
                          : (widget.ru ? 'Контакты не найдены.' : 'No contacts found.'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 30),
                    itemCount: values.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final contact = values[index];
                      final name = contact.displayName.trim();
                      final phone = contact.phones.isEmpty
                          ? ''
                          : contact.phones.first.number;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(
                          name.isEmpty
                              ? (widget.ru ? 'Без имени' : 'Unnamed')
                              : name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: phone.isEmpty ? null : Text(phone),
                        trailing: const Icon(Icons.chat_bubble_outline_rounded),
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

class CgV16PrivacyScreen extends StatefulWidget {
  final bool ru;

  const CgV16PrivacyScreen({super.key, required this.ru});

  @override
  State<CgV16PrivacyScreen> createState() => _CgV16PrivacyScreenState();
}

class _CgV16PrivacyScreenState extends State<CgV16PrivacyScreen> {
  Map<String, dynamic> _values = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final values = await CgV16FeatureStore.loadPrivacy();
    if (mounted) setState(() => _values = values);
  }

  String _label(String value) {
    switch (value) {
      case 'contacts':
        return widget.ru ? 'Только контакты' : 'Contacts only';
      case 'nobody':
        return widget.ru ? 'Никто' : 'Nobody';
      default:
        return widget.ru ? 'Все' : 'Everyone';
    }
  }

  Future<void> _choose(String key, String title) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final item in <String>['everyone', 'contacts', 'nobody'])
                RadioListTile<String>(
                  value: item,
                  groupValue: _values[key]?.toString() ?? 'everyone',
                  title: Text(_label(item)),
                  onChanged: (next) => Navigator.pop(context, next),
                ),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    _values[key] = value;
    await CgV16FeatureStore.savePrivacy(_values);
    if (mounted) setState(() {});
  }

  Widget _choiceTile(String key, String title) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(_label(_values[key]?.toString() ?? 'everyone')),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: () => _choose(key, title),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.ru ? 'Приватность' : 'Privacy')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
      children: <Widget>[
        _choiceTile(
          'phone',
          widget.ru ? 'Номер телефона' : 'Phone number',
        ),
        _choiceTile(
          'lastSeen',
          widget.ru ? 'Последняя активность' : 'Last seen',
        ),
        _choiceTile(
          'calls',
          widget.ru ? 'Кто может звонить' : 'Who can call',
        ),
        _choiceTile(
          'groups',
          widget.ru
              ? 'Кто может добавлять в группы'
              : 'Who can add me to groups',
        ),
        Card(
          child: SwitchListTile(
            value: _values['readReceipts'] != false,
            onChanged: (value) async {
              _values['readReceipts'] = value;
              await CgV16FeatureStore.savePrivacy(_values);
              if (mounted) setState(() {});
            },
            title: Text(
              widget.ru ? 'Отчёты о прочтении' : 'Read receipts',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          widget.ru
              ? 'Настройки приватности сохраняются локально и применяются к новым контактам, звонкам и приглашениям.'
              : 'Privacy settings are stored locally and apply to new contacts, calls and invites.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}
