import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CgPermissionCenter {
  static const String _introKey = 'cg_permission_intro_v2';

  static Future<void> maybePrompt(BuildContext context, {required bool ru}) async {
    if (!Platform.isAndroid || !context.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_introKey) == true || !context.mounted) return;
    await prefs.setBool(_introKey, true);

    final openNow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined, size: 38),
        title: Text(ru ? 'Доступы приложения' : 'App permissions'),
        content: Text(
          ru
              ? 'Чернограм запросит только те системные доступы, которые нужны для звонков, уведомлений, файлов, QR, контактов и будущих функций агента. Каждый доступ можно пропустить или позже отключить в настройках устройства.'
              : 'Chernogram requests only the system access needed for calls, notifications, files, QR, contacts and future agent features. Every permission is optional and can be disabled later.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(ru ? 'Позже' : 'Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ru ? 'Настроить' : 'Configure'),
          ),
        ],
      ),
    );
    if (openNow == true && context.mounted) {
      await open(context, ru: ru);
    }
  }

  static Future<void> open(BuildContext context, {required bool ru}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _PermissionSheet(ru: ru),
    );
  }
}

class _PermissionSheet extends StatefulWidget {
  final bool ru;

  const _PermissionSheet({required this.ru});

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet> {
  bool _busy = false;
  String? _status;

  Future<void> _requestAll() async {
    if (_busy) return;
    if (!Platform.isAndroid) {
      setState(() => _status = widget.ru
          ? 'На Windows мобильные разрешения не требуются. Уведомления работают через системный центр и значок в трее.'
          : 'Windows does not require mobile permissions. Notifications use the system center and tray icon.');
      return;
    }
    setState(() {
      _busy = true;
      _status = widget.ru
          ? 'Открываем системные запросы по очереди…'
          : 'Opening system prompts one by one…';
    });

    final permissions = <Permission>[
      Permission.notification,
      Permission.microphone,
      Permission.camera,
      Permission.contacts,
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];
    for (final permission in permissions) {
      try {
        await permission.request();
      } catch (_) {
        // Some permissions do not exist on older Android versions.
      }
    }
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = widget.ru
          ? 'Готово. Разрешённые возможности уже доступны приложению.'
          : 'Done. Granted capabilities are now available.';
    });
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    final scheme = Theme.of(context).colorScheme;
    final items = <({IconData icon, String title, String subtitle})>[
      (
        icon: Icons.notifications_active_outlined,
        title: ru ? 'Уведомления и вибрация' : 'Notifications and vibration',
        subtitle: ru
            ? 'Новые сообщения и входящие вызовы.'
            : 'New messages and incoming calls.',
      ),
      (
        icon: Icons.mic_none_rounded,
        title: ru ? 'Микрофон' : 'Microphone',
        subtitle: ru
            ? 'Аудиозвонки и голосовые сообщения.'
            : 'Audio calls and voice messages.',
      ),
      (
        icon: Icons.camera_alt_outlined,
        title: ru ? 'Камера и фонарик' : 'Camera and flashlight',
        subtitle: ru
            ? 'Видео, QR, кружки и управление вспышкой.'
            : 'Video, QR, circles and flash control.',
      ),
      (
        icon: Icons.contacts_outlined,
        title: ru ? 'Контакты' : 'Contacts',
        subtitle: ru
            ? 'Приглашения и сохранение знакомых людей.'
            : 'Invites and known people.',
      ),
      (
        icon: Icons.perm_media_outlined,
        title: ru ? 'Фото, видео, музыка и файлы' : 'Photos, video, music and files',
        subtitle: ru
            ? 'Отправка, сохранение и P2P-шара.'
            : 'Sending, saving and P2P sharing.',
      ),
      (
        icon: Icons.location_on_outlined,
        title: ru ? 'Геолокация при использовании' : 'Location while in use',
        subtitle: ru
            ? 'Только для функций, где пользователь сам включает геоданные.'
            : 'Only for features where the user enables location.',
      ),
      (
        icon: Icons.bluetooth_searching_rounded,
        title: ru ? 'Bluetooth и устройства рядом' : 'Bluetooth and nearby devices',
        subtitle: ru
            ? 'Поиск собственных устройств и быстрый локальный обмен.'
            : 'Finding your devices and fast local transfer.',
      ),
      (
        icon: Icons.battery_saver_outlined,
        title: ru ? 'Фоновая работа' : 'Background operation',
        subtitle: ru
            ? 'Помогает не пропускать сообщения, пока приложение свёрнуто.'
            : 'Helps receive messages while the app is minimized.',
      ),
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      ru ? 'Доступы Чернограма' : 'Chernogram permissions',
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
                ru
                    ? 'Android всё равно оставляет окончательное решение за вами. Чернограм не получает скрытый или безусловный контроль над телефоном.'
                    : 'Android always leaves the final choice to you. Chernogram does not get hidden or unrestricted control of the phone.',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .60),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: Icon(item.icon, color: scheme.primary),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(item.subtitle),
                  );
                },
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Text(
                  _status!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _requestAll,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        ru ? 'Запросить нужные доступы' : 'Request required access',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(
                        ru ? 'Открыть системные настройки' : 'Open system settings',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
