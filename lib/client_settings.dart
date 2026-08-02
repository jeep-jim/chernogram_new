import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'background_runtime.dart';
import 'brand.dart';
import 'core_models.dart';
import 'device_identity.dart';

const String cGAndroidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';
const String cGWindowsInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/latest';

Future<void> showChernogramInstallShare(
  BuildContext context, {
  required bool ru,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _InstallShareSheet(ru: ru),
  );
}

class _InstallShareSheet extends StatelessWidget {
  final bool ru;

  const _InstallShareSheet({required this.ru});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width > 700 ? 560 : double.infinity),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChernogramLogo(size: 72),
              const SizedBox(height: 10),
              Text(
                ru ? 'Установить Чернограм' : 'Install Chernogram',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                ru
                    ? 'Наведите камеру Android на QR-код или отправьте прямую ссылку.'
                    : 'Scan the QR code with Android or share the direct link.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: QrImageView(
                  data: cGAndroidInstallUrl,
                  version: QrVersions.auto,
                  size: 230,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                cGAndroidInstallUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: cGAndroidInstallUrl),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ru ? 'Ссылка скопирована.' : 'Link copied.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(ru ? 'Копировать' : 'Copy'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Share.share(
                        ru
                            ? 'Установить Чернограм: $cGAndroidInstallUrl'
                            : 'Install Chernogram: $cGAndroidInstallUrl',
                      ),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(ru ? 'Отправить' : 'Share'),
                    ),
                  ),
                ],
              ),
              if (Platform.isWindows) ...[
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    const ClipboardData(text: cGWindowsInstallUrl),
                  ),
                  icon: const Icon(Icons.desktop_windows_outlined),
                  label: Text(
                    ru
                        ? 'Скопировать ссылку Windows'
                        : 'Copy Windows link',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showDeviceAccountSheet(
  BuildContext context, {
  required bool ru,
  required CgProfile profile,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DeviceAccountSheet(ru: ru, profile: profile),
  );
}

class _DeviceAccountSheet extends StatefulWidget {
  final bool ru;
  final CgProfile profile;

  const _DeviceAccountSheet({required this.ru, required this.profile});

  @override
  State<_DeviceAccountSheet> createState() => _DeviceAccountSheetState();
}

class _DeviceAccountSheetState extends State<_DeviceAccountSheet> {
  String? _fingerprint;
  String? _stableId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final values = await Future.wait<String>([
      CgDeviceIdentity.fingerprint(),
      CgDeviceIdentity.stableProfileId(),
    ]);
    if (mounted) {
      setState(() {
        _fingerprint = values[0];
        _stableId = values[1];
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.ru ? 'Аккаунт и устройство' : 'Account and device',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            widget.ru
                ? 'Chernogram ID привязан к устойчивому отпечатку устройства. После переустановки приложение создаст тот же ID; комнаты и история дополнительно восстанавливаются резервной копией Android или кодом переноса.'
                : 'Chernogram ID is tied to a stable device fingerprint. Reinstalling recreates the same ID; rooms and history are additionally restored by Android backup or a transfer code.',
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 16),
          _ValueCard(
            label: 'Chernogram ID',
            value: widget.profile.id,
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 8),
          _ValueCard(
            label: widget.ru ? 'Отпечаток устройства' : 'Device fingerprint',
            value: _fingerprint ?? '…',
            icon: Icons.phonelink_lock_rounded,
          ),
          const SizedBox(height: 8),
          _ValueCard(
            label: widget.ru ? 'ID после чистой установки' : 'ID after reinstall',
            value: _stableId ?? '…',
            icon: Icons.restore_rounded,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: '${widget.profile.id}\n${_fingerprint ?? ''}',
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      widget.ru ? 'Данные скопированы.' : 'Details copied.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_all_rounded),
            label: Text(widget.ru ? 'Скопировать данные' : 'Copy details'),
          ),
        ],
      ),
    ),
  );
}

class _ValueCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ValueCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(18),
    child: ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: SelectableText(value),
    ),
  );
}

Future<void> showBackgroundConnectionSettings(
  BuildContext context, {
  required bool ru,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _BackgroundConnectionSheet(ru: ru),
  );
}

class _BackgroundConnectionSheet extends StatefulWidget {
  final bool ru;

  const _BackgroundConnectionSheet({required this.ru});

  @override
  State<_BackgroundConnectionSheet> createState() =>
      _BackgroundConnectionSheetState();
}

class _BackgroundConnectionSheetState
    extends State<_BackgroundConnectionSheet> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await CgBackgroundRuntime.isEnabled();
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _set(bool value) async {
    setState(() => _busy = true);
    await CgBackgroundRuntime.setEnabled(value);
    if (mounted) {
      setState(() {
        _enabled = value;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_active_outlined, size: 52),
          const SizedBox(height: 10),
          Text(
            widget.ru ? 'Всегда на связи' : 'Always connected',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            widget.ru
                ? 'Android будет держать защищённое соединение в фоновой службе, чтобы показывать сообщения и входящие звонки после сворачивания или закрытия окна. После принудительной остановки приложения системой Android служба не запускается до следующего открытия.'
                : 'Android keeps the encrypted connection in a foreground service for messages and calls after the window is minimized or closed. A system force-stop prevents restart until the app is opened again.',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            value: _enabled ?? false,
            onChanged: _enabled == null || _busy ? null : _set,
            secondary: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded),
            title: Text(
              widget.ru ? 'Фоновое соединение' : 'Background connection',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              widget.ru
                  ? 'Показывает постоянное тихое уведомление Android.'
                  : 'Shows a persistent silent Android notification.',
            ),
          ),
        ],
      ),
    ),
  );
}
