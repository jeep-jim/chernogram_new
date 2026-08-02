import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../brand.dart';
import 'optical_codec.dart';
import 'optical_models.dart';
import 'optical_store.dart';

class OpticalRoomInviteScreen extends StatelessWidget {
  final OpticalRoom room;

  const OpticalRoomInviteScreen({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final data = OpticalInviteCodec.encodeRoom(room);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Подключить второе устройство')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const ChernogramLogo(size: 78),
                  const SizedBox(height: 12),
                  Text(
                    room.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'На втором Android откройте «Сканировать комнату» и наведите камеру на этот код.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(blurRadius: 30, color: Color(0x443B82F6)),
                      ],
                    ),
                    child: QrImageView(
                      data: data,
                      version: QrVersions.auto,
                      size: min(MediaQuery.sizeOf(context).width - 76, 330),
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
                  const _SecureBadge(
                    icon: Icons.key_rounded,
                    title: 'Ключ комнаты передаётся только визуально',
                    subtitle:
                        'Интернет, Wi‑Fi и Bluetooth для подключения не используются.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpticalRoomScannerScreen extends StatefulWidget {
  const OpticalRoomScannerScreen({super.key});

  @override
  State<OpticalRoomScannerScreen> createState() =>
      _OpticalRoomScannerScreenState();
}

class _OpticalRoomScannerScreenState extends State<OpticalRoomScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finished = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_finished) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final room = OpticalInviteCodec.decodeRoom(raw);
      if (room == null) {
        if (mounted) setState(() => _error = 'Это не QR комнаты Чернограма');
        continue;
      }
      _finished = true;
      _controller.stop();
      Navigator.pop(context, room);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: const Text('Сканировать комнату'),
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
        const _ScannerFrame(),
        Positioned(
          left: 20,
          right: 20,
          bottom: 28,
          child: _ScannerCaption(
            title: _error ?? 'Наведите камеру на QR комнаты',
            subtitle: 'Телефоны могут быть полностью без сети.',
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

class OpticalTransmitScreen extends StatefulWidget {
  final OpticalEncodedTransfer transfer;
  final String roomName;

  const OpticalTransmitScreen({
    super.key,
    required this.transfer,
    required this.roomName,
  });

  @override
  State<OpticalTransmitScreen> createState() => _OpticalTransmitScreenState();
}

class _OpticalTransmitScreenState extends State<OpticalTransmitScreen> {
  Timer? _timer;
  int _frameIndex = 0;
  int _cycles = 0;
  double _fps = 8;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    final milliseconds = (1000 / _fps).round();
    _timer = Timer.periodic(Duration(milliseconds: milliseconds), (_) {
      if (!mounted || widget.transfer.frames.isEmpty) return;
      setState(() {
        _frameIndex++;
        if (_frameIndex >= widget.transfer.frames.length) {
          _frameIndex = 0;
          _cycles++;
        }
      });
    });
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return minutes > 0 ? '$minutes мин $seconds сек' : '$seconds сек';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final qrSize = min(media.width - 22, media.height * .61);
    final transfer = widget.transfer;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const ChernogramLogo(size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ОПТИЧЕСКАЯ ПЕРЕДАЧА',
                          style: TextStyle(
                            color: Color(0xFF9C8CFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.3,
                          ),
                        ),
                        Text(
                          widget.roomName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<double>(
                    tooltip: 'Скорость кадров',
                    initialValue: _fps,
                    icon: const Icon(Icons.speed_rounded, color: Colors.white),
                    onSelected: (value) {
                      setState(() => _fps = value);
                      _restartTimer();
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<double>>[
                      PopupMenuItem(value: 5, child: Text('5 FPS — надёжно')),
                      PopupMenuItem(value: 8, child: Text('8 FPS — обычно')),
                      PopupMenuItem(value: 10, child: Text('10 FPS — быстро')),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: qrSize,
                  height: qrSize,
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: QrImageView(
                    key: ValueKey<int>(_frameIndex),
                    data: transfer.frames[_frameIndex],
                    version: QrVersions.auto,
                    gapless: true,
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                    padding: EdgeInsets.zero,
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: transfer.frames.length <= 1
                              ? 1
                              : (_frameIndex + 1) / transfer.frames.length,
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_frameIndex + 1}/${transfer.frames.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Цикл ${_cycles + 1} • $_fps FPS • примерно ${_durationLabel(transfer.estimateAt(_fps))} за один цикл',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'На втором телефоне откройте эту комнату и нажмите кнопку камеры. Держите экран полностью в рамке.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, height: 1.3),
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
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }
}

class OpticalReceiveScreen extends StatefulWidget {
  final OpticalRoom room;

  const OpticalReceiveScreen({super.key, required this.room});

  @override
  State<OpticalReceiveScreen> createState() => _OpticalReceiveScreenState();
}

class _OpticalReceiveScreenState extends State<OpticalReceiveScreen> {
  late final OpticalFrameAccumulator _accumulator = OpticalFrameAccumulator(
    expectedRoomId: widget.room.id,
  );
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
    autoZoom: true,
  );

  OpticalFrameProgress _progress = const OpticalFrameProgress(
    accepted: false,
    complete: false,
    received: 0,
    total: 0,
  );
  bool _decoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_decoding) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final result = _accumulator.add(raw);
      if (!result.accepted && result.error == null) continue;
      if (mounted) {
        setState(() {
          _progress = result;
          _error = result.error;
        });
      }
      if (result.complete) {
        _decoding = true;
        unawaited(_finish());
        return;
      }
    }
  }

  Future<void> _finish() async {
    await _controller.stop();
    try {
      final packed = await _accumulator.assembleAndVerify();
      final payload = await OpticalTransferCodec.decode(
        room: widget.room,
        packedBytes: packed,
      );
      var message = payload.message;
      if (message.isFile) {
        final file = await OpticalStore.persistFile(
          roomId: widget.room.id,
          messageId: message.id,
          fileName: message.fileName ?? 'file.bin',
          bytes: payload.fileBytes,
        );
        message = message.copyWith(filePath: file.path, state: 'received');
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context, message);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error = 'Не удалось восстановить пакет: $error';
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress.ratio * 100).clamp(0, 100).round();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          const _ScannerFrame(),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: 10),
                    const ChernogramLogo(size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ПРИЁМ ОПТИЧЕСКОГО ПОТОКА',
                            style: TextStyle(
                              color: Color(0xFFA897FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            widget.room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _controller.toggleTorch,
                      icon: const Icon(Icons.flashlight_on_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 26,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xE6111420),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x556B5CFF)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _progress.total == 0 ? null : _progress.ratio,
                          minHeight: 9,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _progress.total == 0 ? 'ПОИСК' : '$percent%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _decoding
                        ? 'Проверяем шифрование и собираем данные…'
                        : _progress.total == 0
                        ? 'Наведите камеру на движущийся QR-поток'
                        : 'Получено ${_progress.received} из ${_progress.total} уникальных кадров',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFF9C9C)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: min(MediaQuery.sizeOf(context).width - 42, 390),
        height: min(MediaQuery.sizeOf(context).width - 42, 390),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF8A7BFF), width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x668A7BFF),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ScannerCaption extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ScannerCaption({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xE6111420),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );
}

class _SecureBadge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SecureBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF8A7BFF)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
