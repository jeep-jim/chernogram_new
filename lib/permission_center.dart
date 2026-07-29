import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CgPermissionCenter {
  static Future<void> open(BuildContext context, {required bool ru}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PermissionSheet(ru: ru),
    );
  }
}

class _PermissionItem {
  final String id;
  final IconData icon;
  final String titleRu;
  final String titleEn;
  final String subtitleRu;
  final String subtitleEn;
  final List<Permission> permissions;

  const _PermissionItem({
    required this.id,
    required this.icon,
    required this.titleRu,
    required this.titleEn,
    required this.subtitleRu,
    required this.subtitleEn,
    required this.permissions,
  });
}

class _PermissionSheet extends StatefulWidget {
  final bool ru;

  const _PermissionSheet({required this.ru});

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet>
    with WidgetsBindingObserver {
  static const List<_PermissionItem> _items = <_PermissionItem>[
    _PermissionItem(
      id: 'notifications',
      icon: Icons.notifications_active_outlined,
      titleRu: 'Уведомления',
      titleEn: 'Notifications',
      subtitleRu: 'Сообщения, входящие звонки и вибрация.',
      subtitleEn: 'Messages, incoming calls and vibration.',
      permissions: <Permission>[Permission.notification],
    ),
    _PermissionItem(
      id: 'microphone',
      icon: Icons.mic_none_rounded,
      titleRu: 'Микрофон',
      titleEn: 'Microphone',
      subtitleRu: 'Аудиозвонки и голосовые сообщения.',
      subtitleEn: 'Audio calls and voice messages.',
      permissions: <Permission>[Permission.microphone],
    ),
    _PermissionItem(
      id: 'camera',
      icon: Icons.camera_alt_outlined,
      titleRu: 'Камера',
      titleEn: 'Camera',
      subtitleRu: 'Видео, QR и видеокружки.',
      subtitleEn: 'Video, QR and video circles.',
      permissions: <Permission>[Permission.camera],
    ),
    _PermissionItem(
      id: 'contacts',
      icon: Icons.contacts_outlined,
      titleRu: 'Контакты',
      titleEn: 'Contacts',
      subtitleRu: 'Приглашения людям из телефонной книги.',
      subtitleEn: 'Invites for people from the phone book.',
      permissions: <Permission>[Permission.contacts],
    ),
    _PermissionItem(
      id: 'media',
      icon: Icons.perm_media_outlined,
      titleRu: 'Фото, видео и музыка',
      titleEn: 'Photos, video and music',
      subtitleRu: 'Отправка, сохранение и воспроизведение файлов.',
      subtitleEn: 'Sending, saving and playing files.',
      permissions: <Permission>[
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ],
    ),
    _PermissionItem(
      id: 'nearby',
      icon: Icons.bluetooth_searching_rounded,
      titleRu: 'Устройства рядом',
      titleEn: 'Nearby devices',
      subtitleRu: 'Bluetooth и быстрый локальный обмен.',
      subtitleEn: 'Bluetooth and fast local exchange.',
      permissions: <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ],
    ),
    _PermissionItem(
      id: 'background',
      icon: Icons.battery_saver_outlined,
      titleRu: 'Фоновая работа',
      titleEn: 'Background operation',
      subtitleRu: 'Помогает не пропускать сообщения и звонки.',
      subtitleEn: 'Helps avoid missing messages and calls.',
      permissions: <Permission>[Permission.ignoreBatteryOptimizations],
    ),
  ];

  final Map<String, bool> _enabled = <String, bool>{};
  final Set<String> _busy = <String>{};

  bool get _android => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!_android) {
      if (mounted) {
        setState(() {
          for (final item in _items) {
            _enabled[item.id] = true;
          }
        });
      }
      return;
    }
    final next = <String, bool>{};
    for (final item in _items) {
      var granted = true;
      for (final permission in item.permissions) {
        try {
          final status = await permission.status;
          granted = granted &&
              (status.isGranted || status.isLimited || status.isProvisional);
        } catch (_) {
          // A permission may not exist on an older Android version.
        }
      }
      next[item.id] = granted;
    }
    if (mounted) setState(() => _enabled.addAll(next));
  }

  Future<void> _toggle(_PermissionItem item, bool value) async {
    if (!_android || _busy.contains(item.id)) return;
    setState(() => _busy.add(item.id));
    try {
      if (value) {
        for (final permission in item.permissions) {
          try {
            await permission.request();
          } catch (_) {
            // Ignore permissions unavailable on this Android version.
          }
        }
      } else {
        await openAppSettings();
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _requestAll() async {
    if (!_android) return;
    for (final item in _items) {
      if (_enabled[item.id] != true) await _toggle(item, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 10, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ru ? 'Разрешения и приватность' : 'Permissions and privacy',
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
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                _android
                    ? (ru
                          ? 'Каждый доступ включается отдельно. Отключение открывает системные настройки Android — приложение не может тайно вернуть разрешение.'
                          : 'Every permission is controlled separately. Turning one off opens Android settings; the app cannot silently restore it.')
                    : (ru
                          ? 'На Windows мобильные разрешения не требуются. Камера и микрофон запрашиваются системой только при использовании.'
                          : 'Windows does not require mobile permissions. Camera and microphone are requested only when used.'),
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .62),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final busy = _busy.contains(item.id);
                  return Material(
                    color: scheme.surface.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(20),
                    child: SwitchListTile(
                      value: _enabled[item.id] ?? false,
                      onChanged: _android && !busy
                          ? (value) => _toggle(item, value)
                          : null,
                      secondary: busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(item.icon, color: scheme.primary),
                      title: Text(
                        ru ? item.titleRu : item.titleEn,
                        style: const TextStyle(fontWeight: FontWeight.w850),
                      ),
                      subtitle: Text(ru ? item.subtitleRu : item.subtitleEn),
                    ),
                  );
                },
              ),
            ),
            if (_android)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _requestAll,
                        icon: const Icon(Icons.security_rounded),
                        label: Text(ru ? 'Запросить нужные' : 'Request needed'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: ru ? 'Системные настройки' : 'System settings',
                      onPressed: openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
