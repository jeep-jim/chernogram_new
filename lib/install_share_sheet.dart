import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

const String cernogramAndroidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';

Future<void> showChernogramInstallShareSheet(
  BuildContext context, {
  required bool ru,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              ru ? 'Установить Чернограм' : 'Install Chernogram',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              ru
                  ? 'Отсканируйте QR-код камерой другого телефона или отправьте ссылку через любой мессенджер.'
                  : 'Scan the QR code with another phone or share the link through any messenger.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: QrImageView(
                data: cernogramAndroidInstallUrl,
                size: 230,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              cernogramAndroidInstallUrl,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Share.share(
                  ru
                      ? 'Установить Чернограм:\n$cernogramAndroidInstallUrl'
                      : 'Install Chernogram:\n$cernogramAndroidInstallUrl',
                  subject: ru ? 'Установка Чернограма' : 'Chernogram installation',
                ),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(ru ? 'Отправить ссылку' : 'Share link'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
