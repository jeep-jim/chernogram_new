import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../brand.dart';
import '../core_models.dart';
import 'light_theme.dart';

String? _inviteTokenFromRaw(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  final direct = CgTunnel.fromInviteToken(value);
  if (direct != null) return value;

  try {
    final uri = Uri.parse(value);
    if (uri.scheme == 'chernogram' &&
        uri.host == 'join' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    final invite = uri.queryParameters['invite'];
    if (invite != null && invite.isNotEmpty) return invite;
  } catch (_) {}
  return null;
}

class LightInviteQrScreen extends StatelessWidget {
  final CgTunnel chat;
  final String inviteUrl;
  final Future<void> Function() onShare;

  const LightInviteQrScreen({
    super.key,
    required this.chat,
    required this.inviteUrl,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Подключить человека')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LightGlass(
                padding: const EdgeInsets.all(22),
                borderRadius: BorderRadius.circular(34),
                child: Column(
                  children: [
                    const ChernogramLogo(size: 78),
                    const SizedBox(height: 12),
                    Text(
                      chat.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'На втором телефоне откройте Чернограм и нажмите «Сканировать QR».',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.4,
                        color: scheme.onSurface.withValues(alpha: .62),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: QrImageView(
                        data: inviteUrl,
                        version: QrVersions.auto,
                        size: 285,
                        gapless: true,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
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
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onShare,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Отправить ссылку'),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'QR и ссылка содержат один и тот же защищённый ключ диалога.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LightInviteScannerScreen extends StatefulWidget {
  const LightInviteScannerScreen({super.key});

  @override
  State<LightInviteScannerScreen> createState() =>
      _LightInviteScannerScreenState();
}

class _LightInviteScannerScreenState extends State<LightInviteScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoZoom: true,
  );

  bool _finished = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_finished) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final token = _inviteTokenFromRaw(raw);
      final chat = token == null ? null : CgTunnel.fromInviteToken(token);
      if (chat == null) {
        if (mounted) {
          setState(() => _error = 'Это не QR-приглашение Чернограма');
        }
        continue;
      }
      _finished = true;
      unawaited(_controller.stop());
      if (mounted) Navigator.pop(context, chat);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Сканировать QR'),
      actions: [
        IconButton(
          tooltip: 'Вспышка',
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_rounded),
        ),
        IconButton(
          tooltip: 'Сменить камеру',
          onPressed: _controller.switchCamera,
          icon: const Icon(Icons.cameraswitch_rounded),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 294,
              height: 294,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: const Color(0xFFA997FF), width: 3),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x668C7BFF),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 28,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xE6191D2A),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'Наведите камеру на QR другого телефона',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'После распознавания контакт и диалог сохранятся автоматически.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
