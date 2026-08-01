import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'brand.dart';

const String chernogramProductUrl =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';

class CgDeviceStorageCard extends StatefulWidget {
  final bool ru;

  const CgDeviceStorageCard({super.key, required this.ru});

  @override
  State<CgDeviceStorageCard> createState() => _CgDeviceStorageCardState();
}

class _CgDeviceStorageCardState extends State<CgDeviceStorageCard> {
  static const MethodChannel _channel = MethodChannel('chernogram/storage');

  int? _freeBytes;
  int? _totalBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getStorageStats',
      );
      final free = raw?['freeBytes'];
      final total = raw?['totalBytes'];
      if (!mounted) return;
      setState(() {
        _freeBytes = free is num ? free.toInt() : null;
        _totalBytes = total is num ? total.toInt() : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _freeBytes = null;
        _totalBytes = null;
        _loading = false;
      });
    }
  }

  String _size(int? bytes) {
    if (bytes == null || bytes < 0) return '—';
    const kb = 1024.0;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} ГБ';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} МБ';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} КБ';
    return '$bytes Б';
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalBytes;
    final free = _freeBytes;
    final int? used = total != null && free != null
        ? (total - free).clamp(0, total).toInt()
        : null;
    final double ratio = total != null && total > 0 && used != null
        ? (used / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 10, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.storage_rounded),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ru ? 'Память устройства' : 'Device storage',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _loading
                            ? (widget.ru
                                ? 'Считаем свободное место…'
                                : 'Reading free space…')
                            : (widget.ru
                                ? 'Свободно ${_size(free)} из ${_size(total)}'
                                : '${_size(free)} free of ${_size(total)}'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withValues(alpha: .56),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: widget.ru ? 'Обновить' : 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _loading ? null : ratio,
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.ru ? 'Занято' : 'Used'}: ${_size(used)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${widget.ru ? 'Свободно' : 'Free'}: ${_size(free)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showChernogramProductInfo(
  BuildContext context, {
  required bool ru,
}) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChernogramLogo(size: 86),
            const SizedBox(height: 12),
            const Text(
              'Чернограм',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${ru ? 'Версия' : 'Version'} ${info.version} • '
              '${ru ? 'сборка' : 'build'} ${info.buildNumber}',
              style: TextStyle(
                color: Theme.of(sheetContext)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .58),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 17),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: chernogramProductUrl,
                size: 202,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              ru
                  ? 'Отсканируйте QR-код, чтобы открыть страницу Чернограма '
                      'и установить актуальную версию.'
                  : 'Scan the QR code to open Chernogram and install '
                      'the current version.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const SelectableText(
              chernogramProductUrl,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: chernogramProductUrl),
                      );
                      if (!sheetContext.mounted) return;
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            ru ? 'Ссылка скопирована.' : 'Link copied.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(ru ? 'Копировать' : 'Copy'),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Share.share(
                      ru
                          ? 'Чернограм — чаты, файлы и звонки:\n'
                              '$chernogramProductUrl'
                          : 'Chernogram — chats, files and calls:\n'
                              '$chernogramProductUrl',
                      subject: 'Чернограм',
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(ru ? 'Поделиться' : 'Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
