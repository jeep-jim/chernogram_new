import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'brand.dart';
import 'core_models.dart';

const String _pairRelayBase = 'https://ntfy.sh';

String? cGPairTokenFromUri(Uri uri) {
  if (uri.scheme != 'chernogram' || uri.host != 'pair') return null;
  if (uri.pathSegments.isEmpty) return null;
  final token = uri.pathSegments.first.trim();
  return token.isEmpty ? null : token;
}

Future<bool> sendRoomToDesktopPairing({
  required BuildContext context,
  required bool ru,
  required Uri uri,
  required List<CgTunnel> tunnels,
}) async {
  final token = cGPairTokenFromUri(uri);
  if (token == null || tunnels.isEmpty) return false;
  final room = await showModalBottomSheet<CgTunnel>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ru ? 'Подключить компьютер' : 'Connect desktop',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              ru
                  ? 'Выберите комнату, которую нужно открыть на Windows.'
                  : 'Choose the room to open on Windows.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tunnels.length,
                itemBuilder: (context, index) {
                  final tunnel = tunnels[index];
                  return ListTile(
                    leading: ChernogramAvatar(
                      size: 44,
                      seed: tunnel.id,
                      avatarBase64: tunnel.avatarBase64,
                    ),
                    title: Text(
                      tunnel.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      tunnel.isPrivate
                          ? (ru ? 'Закрытая комната' : 'Private room')
                          : (ru ? 'Открытая комната' : 'Public room'),
                    ),
                    trailing: const Icon(Icons.arrow_forward_rounded),
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
  if (room == null) return true;
  final topic = 'chernogram-pair-$token';
  try {
    final response = await http
        .post(
          Uri.parse('$_pairRelayBase/$topic'),
          headers: const <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
            'Title': 'Chernogram room pairing',
            'Tags': 'computer,key',
          },
          body: jsonEncode(<String, dynamic>{
            'kind': 'chernogram-room-pair',
            'invite': room.inviteToken,
            'room': room.displayName,
            'sentAt': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.statusCode >= 200 && response.statusCode < 300
                ? (ru
                      ? 'Комната отправлена на компьютер.'
                      : 'The room was sent to the desktop.')
                : (ru
                      ? 'Не удалось передать комнату. Код: ${response.statusCode}'
                      : 'Room transfer failed: ${response.statusCode}'),
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ru
                ? 'Компьютер не получил комнату. Проверьте интернет и повторите.'
                : 'The desktop did not receive the room. Check the connection and retry.',
          ),
        ),
      );
    }
  }
  return true;
}

Future<String?> showDesktopRoomPairing(
  BuildContext context, {
  required bool ru,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DesktopRoomPairingDialog(ru: ru),
);

class _DesktopRoomPairingDialog extends StatefulWidget {
  final bool ru;

  const _DesktopRoomPairingDialog({required this.ru});

  @override
  State<_DesktopRoomPairingDialog> createState() =>
      _DesktopRoomPairingDialogState();
}

class _DesktopRoomPairingDialogState
    extends State<_DesktopRoomPairingDialog> {
  late final String _token = CgIds.random(26);
  Timer? _timer;
  bool _checking = false;
  String? _error;

  String get _topic => 'chernogram-pair-$_token';
  String get _qrValue => 'chernogram://pair/$_token';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final response = await http
          .get(Uri.parse('$_pairRelayBase/$_topic/json?poll=1&since=all'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (mounted) setState(() => _error = 'HTTP ${response.statusCode}');
        return;
      }
      for (final line in const LineSplitter().convert(response.body)) {
        if (line.trim().isEmpty) continue;
        final envelope = jsonDecode(line);
        if (envelope is! Map) continue;
        final message = envelope['message']?.toString();
        if (message == null || message.isEmpty) continue;
        final payload = jsonDecode(message);
        if (payload is! Map || payload['kind'] != 'chernogram-room-pair') {
          continue;
        }
        final invite = payload['invite']?.toString() ?? '';
        if (invite.isNotEmpty && mounted) {
          Navigator.pop(context, invite);
          return;
        }
      }
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.ru
              ? 'Ожидаем связь с телефоном…'
              : 'Waiting for the phone…',
        );
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.ru ? 'Подключить по QR' : 'Connect with QR'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: _qrValue,
                version: QrVersions.auto,
                size: 238,
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
            const SizedBox(height: 16),
            Text(
              widget.ru
                  ? 'На Android откройте «Сканировать QR», наведите камеру на этот код и выберите комнату.'
                  : 'On Android open “Scan QR”, point the camera at this code and choose a room.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  _error ??
                      (widget.ru
                          ? 'Ожидаем выбор комнаты…'
                          : 'Waiting for a room…'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.ru ? 'Отмена' : 'Cancel'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
