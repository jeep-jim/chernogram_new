from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write_if_changed(path: str, source: str, original: str) -> bool:
    if source == original:
        return False
    Path(path).write_text(source, encoding='utf-8')
    print(f'Patched {path}')
    return True


def patch_brand() -> bool:
    path = 'lib/brand.dart'
    source = read(path)
    original = source
    if "import 'dart:math' as math;" not in source:
        source = source.replace("import 'dart:ui';\n", "import 'dart:math' as math;\nimport 'dart:ui';\n", 1)

    start = source.find('class ChernogramLogo extends StatelessWidget')
    if start < 0:
        raise RuntimeError('ChernogramLogo block was not found')
    replacement = r'''class ChernogramLogo extends StatelessWidget {
  final double size;
  final bool withPlate;
  final double progress;

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
    this.progress = 1,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _ChernogramFacePainter(
        dark: Theme.of(context).brightness == Brightness.dark,
        progress: progress.clamp(0.0, 1.0).toDouble(),
      ),
    );
    if (!withPlate) return mark;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ChernogramColors.orange.withValues(alpha: .13),
              blurRadius: size * .42,
              spreadRadius: -size * .12,
            ),
          ],
        ),
        child: mark,
      ),
    );
  }
}

class _ChernogramFacePainter extends CustomPainter {
  final bool dark;
  final double progress;

  const _ChernogramFacePainter({required this.dark, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stripeCount = size.width < 52 ? 11 : 15;
    final lineWidth = size.width / (stripeCount * 3.15);
    final topBase = size.height * .11;
    final centerY = size.height * .48;
    final faceHeight = size.height * .72;
    final mainShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB9A8FF), Color(0xFF7B5CFF), Color(0xFF20C7FF)],
    ).createShader(rect);

    for (var index = 0; index < stripeCount; index++) {
      final t = stripeCount == 1 ? .5 : index / (stripeCount - 1);
      final normalizedX = t * 2 - 1;
      final x = size.width * (.14 + t * .72);
      final ellipse = math.sqrt(math.max(0, 1 - normalizedX * normalizedX));
      final top = topBase + (1 - ellipse) * size.height * .12;
      final jaw = ellipse * faceHeight * .50 - normalizedX.abs() * size.height * .035;
      final bottom = centerY + jaw;
      final stagger = (progress * 1.42 - t * .34).clamp(0.0, 1.0).toDouble();
      final eased = Curves.easeOutCubic.transform(stagger);
      if (eased <= 0) continue;
      final animatedTop = centerY + (top - centerY) * eased;
      final animatedBottom = centerY + (bottom - centerY) * eased;
      final alpha = (255 * eased).round();

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth * 2.25
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF6E65FF).withAlpha((alpha * .22).round())
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .035);
      final main = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..shader = mainShader
        ..color = Colors.white.withAlpha(alpha);

      final gaps = <(double, double)>[];
      if (normalizedX.abs() > .17 && normalizedX.abs() < .72) {
        gaps.add((size.height * .37, size.height * .445));
      }
      if (normalizedX.abs() < .44) {
        gaps.add((size.height * .625, size.height * .67));
      }
      var cursor = animatedTop;
      for (final gap in gaps) {
        final gapStart = gap.$1.clamp(animatedTop, animatedBottom).toDouble();
        final gapEnd = gap.$2.clamp(animatedTop, animatedBottom).toDouble();
        if (gapStart > cursor) {
          canvas.drawLine(Offset(x, cursor), Offset(x, gapStart), glow);
          canvas.drawLine(Offset(x, cursor), Offset(x, gapStart), main);
        }
        cursor = math.max(cursor, gapEnd).toDouble();
      }
      if (cursor < animatedBottom) {
        canvas.drawLine(Offset(x, cursor), Offset(x, animatedBottom), glow);
        canvas.drawLine(Offset(x, cursor), Offset(x, animatedBottom), main);
      }
    }

    final detailProgress = ((progress - .46) / .54).clamp(0.0, 1.0).toDouble();
    if (detailProgress > 0) {
      final detail = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .025
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF9BE7FF).withValues(alpha: detailProgress);
      canvas.drawLine(
        Offset(size.width * .50, size.height * .455),
        Offset(size.width * .47, size.height * .57),
        detail,
      );
      canvas.drawLine(
        Offset(size.width * .42, size.height * .69),
        Offset(size.width * .58, size.height * .69),
        detail,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChernogramFacePainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.progress != progress;
}

class BrandHeader extends StatelessWidget {
  final String? subtitle;
  final bool ru;

  const BrandHeader({super.key, this.subtitle, this.ru = true});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 39),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ru ? 'Чернограм' : 'Cernogram',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.45,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .46),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

class ChernogramAnimatedIntro extends StatefulWidget {
  final bool ru;
  final VoidCallback onDone;

  const ChernogramAnimatedIntro({
    super.key,
    required this.ru,
    required this.onDone,
  });

  @override
  State<ChernogramAnimatedIntro> createState() =>
      _ChernogramAnimatedIntroState();
}

class _ChernogramAnimatedIntroState extends State<ChernogramAnimatedIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final markProgress = CurvedAnimation(
                parent: _controller,
                curve: const Interval(0, .76, curve: Curves.easeOutCubic),
              ).value;
              final textProgress = CurvedAnimation(
                parent: _controller,
                curve: const Interval(.42, 1, curve: Curves.easeOut),
              ).value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: .90 + markProgress * .10,
                    child: ChernogramLogo(size: 150, progress: markProgress),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: textProgress,
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - textProgress)),
                      child: Column(
                        children: [
                          Text(
                            widget.ru ? 'ЧЕРНОГРАМ' : 'CERNOGRAM',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.0,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            widget.ru
                                ? 'СВЯЗЬ БЕЗ ГРАНИЦ'
                                : 'CONNECTION WITHOUT BORDERS',
                            style: const TextStyle(
                              color: ChernogramColors.goldLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}
'''
    source = source[:start] + replacement
    return write_if_changed(path, source, original)


def patch_v12() -> bool:
    path = 'lib/v12.dart'
    source = read(path)
    original = source
    source = source.replace(
        "        title: BrandHeader(\n          subtitle:",
        "        title: BrandHeader(\n          ru: widget.ru,\n          subtitle:",
        1,
    )
    source = source.replace(', withPlate: true', '')
    source = source.replace("'Chernogram build'", "'Cernogram build'")
    source = source.replace('Install Chernogram for Android', 'Install Cernogram for Android')
    return write_if_changed(path, source, original)


def patch_main_lifecycle() -> bool:
    path = 'lib/main.dart'
    source = read(path)
    original = source
    source = source.replace(
        'class _ChernogramAppState extends State<ChernogramApp> {',
        'class _ChernogramAppState extends State<ChernogramApp>\n'
        '    with WidgetsBindingObserver {',
        1,
    )
    source = source.replace(
        "  void initState() {\n    super.initState();\n    unawaited(_loadSettings());\n  }",
        "  void initState() {\n"
        "    super.initState();\n"
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    unawaited(setChernogramAppForeground(true));\n"
        "    unawaited(_loadSettings());\n"
        "  }\n\n"
        "  @override\n"
        "  void didChangeAppLifecycleState(AppLifecycleState state) {\n"
        "    final foreground = state == AppLifecycleState.resumed;\n"
        "    unawaited(setChernogramAppForeground(foreground));\n"
        "  }",
        1,
    )
    build_marker = '  @override\n  Widget build(BuildContext context) {'
    if 'WidgetsBinding.instance.removeObserver(this);' not in source:
        source = source.replace(
            build_marker,
            "  @override\n"
            "  void dispose() {\n"
            "    WidgetsBinding.instance.removeObserver(this);\n"
            "    unawaited(setChernogramAppForeground(false));\n"
            "    super.dispose();\n"
            "  }\n\n" + build_marker,
            1,
        )
    source = source.replace("      title: 'Чернограм',", "      title: _ru == false ? 'Cernogram' : 'Чернограм',", 1)
    source = source.replace(', withPlate: true', '')
    return write_if_changed(path, source, original)


def patch_background_service() -> bool:
    path = 'lib/background_realtime_service.dart'
    source = read(path)
    original = source

    constants = "const String _foregroundStateKey = 'cg_app_foreground_v1';\n"
    helper = constants + r'''

Future<void> setChernogramAppForeground(bool foreground) async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_foregroundStateKey, foreground);
  FlutterBackgroundService().invoke(
    'appState',
    <String, dynamic>{'foreground': foreground},
  );
}
'''
    if 'Future<void> setChernogramAppForeground' not in source:
        source = source.replace(constants, helper, 1)

    source = source.replace("initialNotificationTitle: 'Чернограм на связи',", "initialNotificationTitle: 'Чернограм',")
    source = source.replace(
        "initialNotificationContent: 'Сообщения и звонки работают в фоне',",
        "initialNotificationContent: 'Фоновая связь активна',",
    )

    start = source.find('  Future<void> syncSessions() async {')
    end = source.find("  service.on('refresh')", start)
    if start < 0 or end < 0:
        raise RuntimeError('background syncSessions block was not found')
    new_sync = r'''  Future<void> closeSessions() async {
    for (final subscription in subscriptions.values) {
      await subscription.cancel();
    }
    subscriptions.clear();
    for (final session in sessions.values) {
      await session.close();
    }
    sessions.clear();
  }

  Future<void> syncSessions() async {
    if (syncingSessions) return;
    syncingSessions = true;
    try {
      final foreground = await appIsForeground();
      if (foreground) {
        await closeSessions();
        if (service is AndroidServiceInstance &&
            await service.isForegroundService()) {
          await service.setAsBackgroundService();
        }
        return;
      }

      if (service is AndroidServiceInstance &&
          !await service.isForegroundService()) {
        await service.setAsForegroundService();
      }

      profile = await CgStore.loadOrCreateProfile();
      tunnels = await CgStore.loadTunnels();
      final currentProfile = profile;
      if (currentProfile == null) return;
      final activeIds = tunnels.map((item) => item.id).toSet();

      final stale = sessions.keys.where((id) => !activeIds.contains(id)).toList();
      for (final id in stale) {
        await subscriptions.remove(id)?.cancel();
        await sessions.remove(id)?.close();
      }

      for (final tunnel in tunnels) {
        if (sessions.containsKey(tunnel.id)) continue;
        try {
          final session = await InternetRelay.open(
            tunnelId: tunnel.id,
            secret: tunnel.secret,
            profileId: currentProfile.id,
            nickname: currentProfile.nickname,
            history: const <Map<String, dynamic>>[],
          );
          sessions[tunnel.id] = session;
          subscriptions[tunnel.id] = session.events.listen(
            (event) => unawaited(handleEvent(tunnel.id, tunnel, event)),
          );
        } catch (_) {}
      }

      if (service is AndroidServiceInstance &&
          await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'Чернограм',
          content: 'Фоновая связь активна',
        );
      }
    } catch (_) {
      // Keep the background isolate alive across temporary radio/storage errors.
    } finally {
      syncingSessions = false;
    }
  }

  service.on('appState').listen((event) async {
    final foreground = event?['foreground'] == true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foregroundStateKey, foreground);
    await syncSessions();
  });

'''
    source = source[:start] + new_sync + source[end:]
    source = source.replace(
        "  Timer.periodic(const Duration(seconds: 20), (_) => unawaited(syncSessions()));",
        "  Timer.periodic(const Duration(seconds: 30), (_) {\n"
        "    unawaited(syncSessions().catchError((_) {}));\n"
        "  });",
    )
    return write_if_changed(path, source, original)


def patch_chat_media() -> bool:
    path = 'lib/chat_media.dart'
    source = read(path)
    original = source

    start = source.find('class _CgInlineAttachmentState extends State<CgInlineAttachment> {')
    end = source.find('class CgMediaLibraryScreen extends StatefulWidget', start)
    if start < 0 or end < 0:
        raise RuntimeError('CgInlineAttachment state block was not found')
    inline = r'''class _CgInlineAttachmentState extends State<CgInlineAttachment> {
  File? _file;
  VideoPlayerController? _previewController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareLocalPreview());
  }

  @override
  void didUpdateWidget(covariant CgInlineAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id) {
      unawaited(_previewController?.dispose());
      _previewController = null;
      _file = null;
      unawaited(_prepareLocalPreview());
    }
  }

  Future<void> _prepareLocalPreview() async {
    final file = await CgMediaStore.existingFile(widget.attachment) ??
        await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !mounted) return;
    _file = file;
    if (CgMediaStore.isVideo(widget.attachment)) {
      final controller = VideoPlayerController.file(file);
      try {
        await controller.initialize();
        await controller.setVolume(0);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        _previewController = controller;
      } catch (_) {
        await controller.dispose();
      }
    }
    if (mounted) setState(() {});
  }

  Future<File?> _ensure() async {
    if (_file != null && await _file!.exists()) return _file;
    if (mounted) setState(() => _loading = true);
    _file = await CgMediaStore.existingFile(widget.attachment);
    _file ??= await widget.onEnsure?.call(widget.attachment);
    _file ??= await CgMediaStore.ensureFile(widget.attachment);
    if (_file != null &&
        CgMediaStore.isVideo(widget.attachment) &&
        _previewController == null) {
      await _prepareLocalPreview();
    }
    if (mounted) setState(() => _loading = false);
    return _file;
  }

  Future<void> _activate() async {
    final file = await _ensure();
    if (file == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Файл запрошен у отправителя. Он появится после передачи.'
                  : 'The file was requested from the sender.',
            ),
          ),
        );
      }
      return;
    }
    if (CgMediaStore.isAudio(widget.attachment)) {
      await widget.onPlayAudio?.call(widget.attachment, file);
      return;
    }
    if (widget.attachment.kind == 'image') {
      await _showImage();
      return;
    }
    if (CgMediaStore.isVideo(widget.attachment)) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CgVideoPlayerScreen(
            file: file,
            circle: widget.attachment.kind == 'circle',
            title: widget.attachment.name,
          ),
        ),
      );
      return;
    }
    await OpenFilex.open(file.path);
  }

  Future<void> _showImage() async {
    final file = await _ensure();
    if (file == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text(widget.attachment.name)),
          body: InteractiveViewer(
            minScale: .5,
            maxScale: 5,
            child: Center(child: Image.file(file, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  Future<void> _menu(String value) async {
    if (value == 'open') await _activate();
    if (value == 'save') {
      final file = await _ensure();
      if (file == null) return;
      final ok = await CgMediaStore.saveToDevice(
        widget.attachment.copyWith(localPath: file.path, clearData: true),
      );
      if (mounted && ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.ru ? 'Файл сохранён' : 'File saved')),
        );
      }
    }
    if (value == 'share') {
      final file = await _ensure();
      if (file != null) await Share.shareXFiles(<XFile>[XFile(file.path)]);
    }
    if (value == 'delete') await widget.onDelete?.call();
  }

  Widget _imagePreview(File file) => GestureDetector(
        onTap: _showImage,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            file,
            width: 286,
            height: 214,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: 760,
          ),
        ),
      );

  Widget _videoPreview(VideoPlayerController controller) {
    final preview = Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .56),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 31),
        ),
      ],
    );
    if (widget.attachment.kind == 'circle') {
      return GestureDetector(
        onTap: _activate,
        child: ClipOval(child: SizedBox.square(dimension: 170, child: preview)),
      );
    }
    return GestureDetector(
      onTap: _activate,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(width: 286, height: 190, child: preview),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_previewController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) {
      return Container(
        width: 250,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.lock_outline_rounded),
      );
    }
    final attachment = widget.attachment;
    if (attachment.kind == 'image' && _file != null) {
      return _imagePreview(_file!);
    }
    final preview = _previewController;
    if (CgMediaStore.isVideo(attachment) &&
        preview != null &&
        preview.value.isInitialized) {
      return _videoPreview(preview);
    }

    final icon = CgMediaStore.isAudio(attachment)
        ? Icons.headphones_rounded
        : attachment.kind == 'image'
            ? Icons.image_outlined
            : CgMediaStore.isVideo(attachment)
                ? Icons.play_circle_outline_rounded
                : attachment.kind == 'archive'
                    ? Icons.folder_zip_outlined
                    : Icons.insert_drive_file_outlined;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loading ? null : _activate,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: .45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(icon, size: 30),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.kind == 'voice'
                          ? (widget.ru ? 'Голосовое сообщение' : 'Voice message')
                          : attachment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${CgMediaStore.fileSize(attachment.size)} • ${widget.ru ? 'нажмите, чтобы открыть' : 'tap to open'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .56),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: widget.ru ? 'Действия' : 'Actions',
                onSelected: _menu,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: Text(widget.ru ? 'Открыть' : 'Open'),
                    ),
                  ),
                  if (widget.canDownload)
                    PopupMenuItem(
                      value: 'save',
                      child: ListTile(
                        leading: const Icon(Icons.download_rounded),
                        title: Text(widget.ru ? 'Сохранить' : 'Save'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      leading: const Icon(Icons.ios_share_rounded),
                      title: Text(widget.ru ? 'Поделиться' : 'Share'),
                    ),
                  ),
                  if (widget.onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(
                          Icons.delete_outline_rounded,
                          color: ChernogramColors.danger,
                        ),
                        title: Text(
                          widget.ru ? 'Удалить сообщение' : 'Delete message',
                          style: const TextStyle(color: ChernogramColors.danger),
                        ),
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
}

'''
    source = source[:start] + inline + source[end:]

    open_old = r'''    if (item.attachment.kind == 'image' &&
        item.attachment.dataBase64 != null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CgImageViewer(
            bytes: base64Decode(item.attachment.dataBase64!),
            title: item.attachment.name,
          ),
        ),
      );
      return;
    }
'''
    open_new = r'''    if (item.attachment.kind == 'image') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(item.attachment.name),
            ),
            body: InteractiveViewer(
              minScale: .5,
              maxScale: 5,
              child: Center(child: Image.file(file, fit: BoxFit.contain)),
            ),
          ),
        ),
      );
      return;
    }
'''
    if open_old in source:
        source = source.replace(open_old, open_new, 1)

    lead_start = source.find('class _MediaLeading extends StatelessWidget')
    lead_end = source.find('class CgImageViewer extends StatelessWidget', lead_start)
    if lead_start < 0 or lead_end < 0:
        raise RuntimeError('_MediaLeading block was not found')
    leading = r'''class _MediaLeading extends StatefulWidget {
  final CgMediaItem item;

  const _MediaLeading({required this.item});

  @override
  State<_MediaLeading> createState() => _MediaLeadingState();
}

class _MediaLeadingState extends State<_MediaLeading> {
  File? _file;
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final attachment = widget.item.attachment;
    final file = await CgMediaStore.existingFile(attachment) ??
        await CgMediaStore.ensureFile(attachment);
    if (file == null || !mounted) return;
    _file = file;
    if (CgMediaStore.isVideo(attachment)) {
      final controller = VideoPlayerController.file(file);
      try {
        await controller.initialize();
        await controller.setVolume(0);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        _controller = controller;
      } catch (_) {
        await controller.dispose();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.item.attachment;
    if (attachment.kind == 'image' && _file != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          _file!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 180,
        ),
      );
    }
    final controller = _controller;
    if (CgMediaStore.isVideo(attachment) &&
        controller != null &&
        controller.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
              const Center(
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 25),
              ),
            ],
          ),
        ),
      );
    }
    return CircleAvatar(
      child: Icon(
        CgMediaStore.isAudio(attachment)
            ? Icons.graphic_eq_rounded
            : CgMediaStore.isVideo(attachment)
                ? Icons.play_arrow_rounded
                : attachment.kind == 'image'
                    ? Icons.image_outlined
                    : Icons.description_outlined,
      ),
    );
  }
}

'''
    source = source[:lead_start] + leading + source[lead_end:]
    source = source.replace("'Chernogram media'", "'Cernogram media'")
    return write_if_changed(path, source, original)


def patch_transport() -> bool:
    changed = False

    path = 'lib/internet_core.dart'
    source = read(path)
    original = source
    connect_old = r'''      final completer = Completer<void>();
      var finished = 0;
      for (final host in relayHosts) {
        unawaited(
          _connectHost(host).then((ok) {
            finished++;
            if (ok && !completer.isCompleted) completer.complete();
            if (finished == relayHosts.length && !completer.isCompleted) {
              completer.complete();
            }
          }),
        );
      }
'''
    connect_new = r'''      final connectHosts = relayHosts.take(2).toList(growable: false);
      final completer = Completer<void>();
      var finished = 0;
      for (final host in connectHosts) {
        unawaited(
          _connectHost(host).then((ok) {
            finished++;
            if (ok && !completer.isCompleted) completer.complete();
            if (finished == connectHosts.length && !completer.isCompleted) {
              completer.complete();
            }
          }),
        );
      }
'''
    if connect_old in source:
        source = source.replace(connect_old, connect_new, 1)
    source = source.replace("'Priority': 'min',", "'Priority': 'high',")
    source = source.replace('const Duration(seconds: 15)', 'const Duration(seconds: 6)')
    source = source.replace(
        'final delay = Duration(seconds: 15 + (_reconnectAttempt * 5).clamp(0, 45).toInt());',
        'final delay = Duration(seconds: 4 + (_reconnectAttempt * 2).clamp(0, 12).toInt());',
    )
    source = source.replace(
        'final seconds = (10 + _reconnectAttempt * 8).clamp(10, 60).toInt();',
        'final seconds = (3 + _reconnectAttempt * 3).clamp(3, 18).toInt();',
    )
    changed |= write_if_changed(path, source, original)

    path = 'lib/chat_screen.dart'
    source = read(path)
    original = source
    source = source.replace(
        "    if (!_canCall || await _session?.waitUntilConnected() != true) {\n      _showNotConnected();\n      return;\n    }\n    final callId = CgIds.random(22);",
        "    if (!_canCall || _session == null) {\n"
        "      _showNotConnected();\n"
        "      return;\n"
        "    }\n"
        "    unawaited(_session!.connect());\n"
        "    final callId = CgIds.random(22);",
        1,
    )
    source = source.replace(
        "    if (!_canCall || await _session?.waitUntilConnected() != true) {\n      _showNotConnected();\n      return;\n    }\n    final callId = CgIds.random(22);",
        "    if (!_canCall || _session == null) {\n"
        "      _showNotConnected();\n"
        "      return;\n"
        "    }\n"
        "    unawaited(_session!.connect());\n"
        "    final callId = CgIds.random(22);",
        1,
    )
    source = source.replace(', withPlate: true', '')
    source = source.replace('Open the Chernogram chat', 'Open the Cernogram chat')
    source = source.replace('Install Chernogram for Android', 'Install Cernogram for Android')
    changed |= write_if_changed(path, source, original)
    return changed


def patch_native_brand() -> bool:
    changed = False
    launcher = '''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1080"
    android:viewportHeight="1080">
    <path android:fillColor="#090D18" android:pathData="M150,60 H930 A90,90 0,0 1,1020 150 V930 A90,90 0,0 1,930 1020 H150 A90,90 0,0 1,60 930 V150 A90,90 0,0 1,150 60 Z" />
    <path android:strokeColor="#B9A8FF" android:strokeWidth="38" android:strokeLineCap="round" android:pathData="M260,390 L260,700 M320,300 L320,785 M380,245 L380,835 M440,215 L440,870 M500,195 L500,895" />
    <path android:strokeColor="#7B5CFF" android:strokeWidth="38" android:strokeLineCap="round" android:pathData="M560,195 L560,895 M620,215 L620,870 M680,245 L680,835" />
    <path android:strokeColor="#20C7FF" android:strokeWidth="38" android:strokeLineCap="round" android:pathData="M740,300 L740,785 M800,390 L800,700" />
    <path android:strokeColor="#090D18" android:strokeWidth="54" android:strokeLineCap="round" android:pathData="M300,440 L465,440 M615,440 L780,440 M430,680 L650,680" />
    <path android:strokeColor="#9BE7FF" android:strokeWidth="24" android:strokeLineCap="round" android:pathData="M545,470 L520,600 M450,700 L630,700" />
</vector>\n'''
    splash = launcher.replace('android:width="108dp"', 'android:width="164dp"').replace('android:height="108dp"', 'android:height="164dp"')
    splash = re.sub(r'    <path android:fillColor="#090D18".*?/>\n', '', splash, count=1)
    for path, content in (
        ('android/app/src/main/res/drawable/chernogram_launcher_icon.xml', launcher),
        ('android/app/src/main/res/drawable/launch_logo.xml', splash),
    ):
        file = Path(path)
        original = file.read_text(encoding='utf-8') if file.exists() else ''
        if original != content:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(content, encoding='utf-8')
            print(f'Patched {path}')
            changed = True

    try:
        from PIL import Image, ImageDraw
        destination = Path('windows/runner/resources/app_icon.ico')
        if destination.parent.exists():
            size = 256
            image = Image.new('RGBA', (size, size), (9, 13, 24, 255))
            draw = ImageDraw.Draw(image)
            colors = [(185, 168, 255, 255), (123, 92, 255, 255), (32, 199, 255, 255)]
            count = 11
            for index in range(count):
                t = index / (count - 1)
                nx = t * 2 - 1
                x = int(size * (.18 + t * .64))
                ellipse = max(0.0, 1.0 - nx * nx) ** .5
                top = int(size * (.19 + (1 - ellipse) * .12))
                bottom = int(size * (.50 + ellipse * .36 - abs(nx) * .03))
                color = colors[min(2, int(t * 3))]
                width = 8
                gaps = []
                if .17 < abs(nx) < .72:
                    gaps.append((int(size * .39), int(size * .46)))
                if abs(nx) < .44:
                    gaps.append((int(size * .64), int(size * .68)))
                cursor = top
                for gs, ge in gaps:
                    if gs > cursor:
                        draw.line((x, cursor, x, gs), fill=color, width=width)
                    cursor = max(cursor, ge)
                if cursor < bottom:
                    draw.line((x, cursor, x, bottom), fill=color, width=width)
            draw.line((128, 116, 120, 153), fill=(155, 231, 255, 255), width=5)
            draw.line((108, 179, 150, 179), fill=(155, 231, 255, 255), width=5)
            image.save(destination, format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
            changed = True
    except Exception:
        pass
    return changed


def patch_metadata() -> bool:
    changed = False
    path = 'pubspec.yaml'
    source = read(path)
    original = source
    source = re.sub(
        r'^version:\s*0\.16\.[0-9]+\+[0-9]+\s*$',
        'version: 0.16.7+38',
        source,
        count=1,
        flags=re.M,
    )
    changed |= write_if_changed(path, source, original)

    path = 'docs/index.html'
    source = read(path)
    original = source
    source = re.sub(r'chernogram\.apk\?v=\d+', 'chernogram.apk?v=38', source)
    changed |= write_if_changed(path, source, original)

    path = 'roadmap.md'
    source = read(path)
    original = source
    if '`0.16.7+38`' not in source:
        source = source.rstrip() + (
            '\n- `0.16.7+38` — единый полосатый знак-лицо и загрузочная анимация, '
            'чистая шапка с названием Cernogram на английском, миниатюры фото и видео, '
            'медиа без лишнего скрытия, один realtime-набор соединений вместо дублирования '
            'в foreground/background и нейтральная системная индикация Android.\n'
        )
    changed |= write_if_changed(path, source, original)
    return changed


def main() -> None:
    changed = False
    changed |= patch_brand()
    changed |= patch_v12()
    changed |= patch_main_lifecycle()
    changed |= patch_background_service()
    changed |= patch_chat_media()
    changed |= patch_transport()
    changed |= patch_native_brand()
    changed |= patch_metadata()
    print(
        'Cernogram 0.16.7 brand, media and lifecycle fixes applied'
        if changed
        else 'Cernogram 0.16.7 fixes already applied'
    )


if __name__ == '__main__':
    main()
