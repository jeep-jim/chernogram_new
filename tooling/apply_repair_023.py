from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    (ROOT / path).write_text(value, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def replace_range(text: str, start: str, end: str, replacement: str) -> str:
    if replacement.strip() in text:
        return text
    left = text.index(start)
    right = text.index(end, left)
    return text[:left] + replacement.rstrip() + "\n\n" + text[right:]


def restore_stable_transport() -> None:
    path = ROOT / "lib" / "internet_core.dart"
    current = path.read_text(encoding="utf-8")
    if "Temporary recovery transport" in current:
        return
    stable = subprocess.check_output(
        ["git", "show", "realtime-recovery-apk:lib/internet_core.dart"],
        cwd=ROOT,
        text=True,
    )
    stable = stable.replace(
        ".timeout(const Duration(seconds: 25));",
        ".timeout(const Duration(seconds: 18));",
    )
    stable = stable.replace(
        ".timeout(const Duration(seconds: 15));",
        ".timeout(const Duration(seconds: 7));",
    )
    path.write_text(stable, encoding="utf-8")


def patch_brand() -> None:
    path = "lib/brand.dart"
    text = read(path).replace("import 'dart:ui';\n", "")

    glass = r'''class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;
  final Color? color;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? scheme.surface.withValues(alpha: dark ? .94 : .98),
          borderRadius: borderRadius,
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: dark ? .055 : .045),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .10 : .035),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}'''
    text = replace_range(
        text,
        "class GlassPanel extends StatelessWidget",
        "class GlassIconButton extends StatelessWidget",
        glass,
    )

    logo = r'''class ChernogramLogo extends StatelessWidget {
  final double size;
  final bool withPlate;
  final double progress;
  final double wavePhase;
  final Color? tint;

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
    this.progress = 1,
    this.wavePhase = 0,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _ChernogramFacePainter(
        progress: progress.clamp(0.0, 1.0).toDouble(),
        wavePhase: wavePhase,
        tint: tint,
      ),
    );
    if (!withPlate) return mark;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: (tint ?? ChernogramColors.violet).withValues(alpha: .16),
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
  final double progress;
  final double wavePhase;
  final Color? tint;

  const _ChernogramFacePainter({
    required this.progress,
    required this.wavePhase,
    this.tint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stripeCount = size.width < 48 ? 11 : 15;
    final lineWidth = size.width / (stripeCount * 3.15);
    final topBase = size.height * .11;
    final centerY = size.height * .48;
    final faceHeight = size.height * .72;
    final shader = tint == null
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFFB9A8FF),
              Color(0xFF7B5CFF),
              Color(0xFF20C7FF),
            ],
          ).createShader(rect)
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.lerp(tint!, Colors.white, .34)!,
              tint!,
              Color.lerp(tint!, ChernogramColors.cyan, .38)!,
            ],
          ).createShader(rect);

    for (var index = 0; index < stripeCount; index++) {
      final t = index / (stripeCount - 1);
      final normalizedX = t * 2 - 1;
      final x = size.width * (.14 + t * .72);
      final ellipse = math.sqrt(math.max(0, 1 - normalizedX * normalizedX));
      final top = topBase + (1 - ellipse) * size.height * .12;
      final jaw =
          ellipse * faceHeight * .50 - normalizedX.abs() * size.height * .035;
      final bottom = centerY + jaw;
      final stagger = (progress * 1.42 - t * .34).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(stagger.toDouble());
      if (eased <= 0) continue;
      final pulse = wavePhase == 0
          ? 0.0
          : math.sin(wavePhase * math.pi * 2 + index * .88) *
                size.height *
                .042;
      final animatedTop = centerY + (top - centerY) * eased + pulse;
      final animatedBottom = centerY + (bottom - centerY) * eased - pulse;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader;

      final eyeGap = normalizedX.abs() > .17 && normalizedX.abs() < .72;
      if (!eyeGap) {
        canvas.drawLine(
          Offset(x, animatedTop),
          Offset(x, animatedBottom),
          paint,
        );
        continue;
      }
      final gapStart = (size.height * .37).clamp(animatedTop, animatedBottom);
      final gapEnd = (size.height * .445).clamp(animatedTop, animatedBottom);
      if (gapStart > animatedTop) {
        canvas.drawLine(
          Offset(x, animatedTop),
          Offset(x, gapStart.toDouble()),
          paint,
        );
      }
      if (gapEnd < animatedBottom) {
        canvas.drawLine(
          Offset(x, gapEnd.toDouble()),
          Offset(x, animatedBottom),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChernogramFacePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.tint != tint;
}'''
    text = replace_range(
        text,
        "class ChernogramLogo extends StatelessWidget",
        "class ChernogramAvatar extends StatelessWidget",
        logo,
    )

    equalizer = r'''class ChernogramEqualizerLogo extends StatefulWidget {
  final double size;
  final bool active;

  const ChernogramEqualizerLogo({
    super.key,
    required this.size,
    required this.active,
  });

  @override
  State<ChernogramEqualizerLogo> createState() =>
      _ChernogramEqualizerLogoState();
}

class _ChernogramEqualizerLogoState extends State<ChernogramEqualizerLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1180),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ChernogramEqualizerLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => ChernogramLogo(
        size: widget.size,
        progress: 1,
        wavePhase: widget.active ? _controller.value : 0,
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}'''
    text = replace_range(
        text,
        "class ChernogramEqualizerLogo extends StatefulWidget",
        "class BrandHeader extends StatelessWidget",
        equalizer,
    )

    waves = r'''class CgChatPatternBackground extends StatefulWidget {
  final Widget child;

  const CgChatPatternBackground({super.key, required this.child});

  @override
  State<CgChatPatternBackground> createState() =>
      _CgChatPatternBackgroundState();
}

class _CgChatPatternBackgroundState extends State<CgChatPatternBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _LivingWavePainter(
          animation: _controller,
          dark: theme.brightness == Brightness.dark,
          accent: theme.colorScheme.primary,
          secondary: theme.colorScheme.secondary,
        ),
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _LivingWavePainter extends CustomPainter {
  final Animation<double> animation;
  final bool dark;
  final Color accent;
  final Color secondary;

  _LivingWavePainter({
    required this.animation,
    required this.dark,
    required this.accent,
    required this.secondary,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    final baseAlpha = dark ? .050 : .044;
    for (var line = 0; line < 5; line++) {
      final path = Path();
      final baseY = size.height * (.13 + line * .19);
      final amplitude = 20.0 + line * 4.5;
      for (double x = -24; x <= size.width + 24; x += 12) {
        final y = baseY +
            math.sin(x / 92 + phase + line * .72) * amplitude +
            math.sin(x / 210 - phase * .62 + line) * amplitude * .42;
        if (x == -24) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line == 2 ? 1.5 : 1.05
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(accent, secondary, line / 4)!
            .withValues(alpha: baseAlpha + (line == 2 ? .018 : 0));
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LivingWavePainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.accent != accent ||
      oldDelegate.secondary != secondary;
}'''
    text = replace_range(
        text,
        "class CgChatPatternBackground extends StatelessWidget",
        "class ChernogramAnimatedIntro extends StatefulWidget",
        waves,
    )
    write(path, text)


def patch_monitor() -> None:
    path = "lib/app_monitor.dart"
    text = read(path)
    old = r'''    final activeIds = tunnels.map((tunnel) => tunnel.id).toSet();
    final obsolete = _subscriptions.keys
        .where((tunnelId) => !activeIds.contains(tunnelId))
        .toList();
    for (final tunnelId in obsolete) {
      await _subscriptions.remove(tunnelId)?.cancel();
      _sessions.remove(tunnelId);
    }

    for (final tunnel in tunnels) {
      await _ensureTunnel(tunnel);
    }
'''
    new = r'''    final recent = tunnels.toList()
      ..sort((a, b) {
        final aTime = a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
        final bTime = b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
        return bTime.compareTo(aTime);
      });
    final monitored = recent.take(8).toList(growable: false);
    final activeIds = monitored.map((tunnel) => tunnel.id).toSet();
    final obsolete = _subscriptions.keys
        .where((tunnelId) => !activeIds.contains(tunnelId))
        .toList();
    for (final tunnelId in obsolete) {
      await _subscriptions.remove(tunnelId)?.cancel();
      _sessions.remove(tunnelId);
      unawaited(InternetRelay.close(tunnelId));
    }

    await Future.wait(monitored.map(_ensureTunnel));
'''
    text = replace_once(text, old, new, "monitor recent tunnels")
    write(path, text)


def patch_shell() -> None:
    path = "lib/android_data_first.dart"
    text = read(path)
    if "import 'permission_center.dart';" not in text:
        text = replace_once(
            text,
            "import 'core_models.dart';\n",
            "import 'core_models.dart';\nimport 'permission_center.dart';\n",
            "permission center import",
        )
    if "const String _androidInstallUrl" not in text:
        text = replace_once(
            text,
            "const String _landingBase =\n"
            "    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';\n",
            "const String _landingBase =\n"
            "    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';\n"
            "const String _androidInstallUrl =\n"
            "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';\n",
            "install url",
        )

    old_bootstrap = r'''    final profile = await CgStore.loadOrCreateProfile();
    final tunnels = await CgStore.loadTunnels();
    final contacts = await CgStore.loadContacts();
    final privacyLens = await CgStore.loadPrivacyLens();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _tunnels = tunnels;
      _contacts = contacts;
      _privacyLens = privacyLens;
      _loading = false;
    });
    await _syncMonitor();
    await _listenLinks();
'''
    new_bootstrap = r'''    final values = await Future.wait<Object>(<Future<Object>>[
      CgStore.loadOrCreateProfile(),
      CgStore.loadTunnels(),
      CgStore.loadContacts(),
      CgStore.loadPrivacyLens(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = values[0] as CgProfile;
      _tunnels = values[1] as List<CgTunnel>;
      _contacts = values[2] as List<CgContact>;
      _privacyLens = values[3] as bool;
      _loading = false;
    });
    unawaited(_syncMonitor());
    unawaited(_listenLinks());
'''
    text = replace_once(text, old_bootstrap, new_bootstrap, "parallel bootstrap")

    text = text.replace(
        "    await _syncMonitor();\n",
        "    unawaited(_syncMonitor());\n",
    )
    text = text.replace(
        "      body: IndexedStack(index: _tab, children: pages),",
        "      body: CgChatPatternBackground(\n"
        "        child: IndexedStack(index: _tab, children: pages),\n"
        "      ),",
    )

    old_invite = r'''    await Share.share(
      widget.ru
          ? 'Присоединяйся ко мне в Чернограме: $url'
          : 'Join me on Chernogram: $url',
      subject: widget.ru ? 'Приглашение в Чернограм' : 'Chernogram invite',
    );
'''
    new_invite = r'''    await Share.share(
      widget.ru
          ? 'Присоединяйся ко мне в Чернограме: $url\n\nЕсли приложения ещё нет, установи его: $_androidInstallUrl'
          : 'Join me on Chernogram: $url\n\nIf the app is not installed yet: $_androidInstallUrl',
      subject: widget.ru ? 'Приглашение в Чернограм' : 'Chernogram invite',
    );
'''
    text = replace_once(text, old_invite, new_invite, "phone invite install link")

    permission_card = r'''      _ProfileAction(
        icon: Icons.admin_panel_settings_outlined,
        title: ru ? 'Разрешения и приватность' : 'Permissions and privacy',
        subtitle: ru
            ? 'Уведомления, микрофон, камера, контакты, файлы и фон.'
            : 'Notifications, microphone, camera, contacts, files and background.',
        onTap: () => CgPermissionCenter.open(context, ru: ru),
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.install_mobile_rounded,
        title: ru ? 'Отправить приложение' : 'Share the app',
        subtitle: ru
            ? 'Прямая ссылка на установку актуальной Android-версии.'
            : 'Direct link to install the current Android version.',
        onTap: () => Share.share(
          ru
              ? 'Установить Чернограм: $_androidInstallUrl'
              : 'Install Chernogram: $_androidInstallUrl',
        ),
      ),
      const SizedBox(height: 8),
'''
    anchor = r'''      _ProfileAction(
        icon: Icons.fingerprint_rounded,
'''
    if "Разрешения и приватность" not in text:
        text = replace_once(text, anchor, permission_card + anchor, "profile permissions")
    text = text.replace(
        "? 'Только Android до стабилизации связи.'\n"
        "            : 'Android only until realtime is stable.'",
        "? 'Обновления Android устанавливаются прямо из приложения.'\n"
        "            : 'Android updates install directly from the app.'",
    )

    # Files: selectable multi-actions.
    text = replace_once(
        text,
        "  bool _busy = false;\n\n  List<_FileEntry> get _entries",
        "  bool _busy = false;\n"
        "  final Set<String> _selectedFileIds = <String>{};\n\n"
        "  List<_FileEntry> get _entries",
        "file selection state",
    )
    file_methods = r'''  void _toggleFileSelection(_FileEntry entry) {
    setState(() {
      if (!_selectedFileIds.add(entry.message.id)) {
        _selectedFileIds.remove(entry.message.id);
      }
    });
  }

  List<_FileEntry> _selectedFiles(List<_FileEntry> entries) => entries
      .where((entry) => _selectedFileIds.contains(entry.message.id))
      .toList(growable: false);

  Future<void> _shareSelectedFiles(List<_FileEntry> entries) async {
    final files = <XFile>[];
    for (final entry in _selectedFiles(entries)) {
      final file = await _materialize(entry.attachment);
      if (file != null) files.add(XFile(file.path));
    }
    if (files.isNotEmpty) await Share.shareXFiles(files);
  }

  Future<void> _clearSelectedLocalFiles(List<_FileEntry> entries) async {
    var tunnels = widget.tunnels;
    for (final entry in _selectedFiles(entries)) {
      tunnels = await CgMediaStore.purgeItem(
        tunnels,
        CgMediaItem(
          tunnelId: entry.tunnel.id,
          tunnelName: entry.tunnel.displayName,
          messageId: entry.message.id,
          authorName: entry.message.authorName,
          sentAt: entry.message.sentAt,
          attachment: entry.attachment,
        ),
      );
    }
    for (final tunnel in tunnels) {
      widget.onTunnelChanged(tunnel);
    }
    if (mounted) setState(_selectedFileIds.clear);
  }

'''
    if "void _toggleFileSelection" not in text:
        text = replace_once(
            text,
            "  Future<File?> _materialize(CgAttachment attachment) async {\n",
            file_methods + "  Future<File?> _materialize(CgAttachment attachment) async {\n",
            "file selection methods",
        )

    file_toolbar_anchor = "        const SizedBox(height: 8),\n        Expanded(\n"
    file_toolbar = r'''        if (_selectedFileIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => setState(_selectedFileIds.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      widget.ru
                          ? 'Выбрано: ${_selectedFileIds.length}'
                          : 'Selected: ${_selectedFileIds.length}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.ru ? 'Отправить' : 'Share',
                    onPressed: () => _shareSelectedFiles(entries),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  IconButton(
                    tooltip: widget.ru ? 'Удалить локальные копии' : 'Remove local copies',
                    onPressed: () => _clearSelectedLocalFiles(entries),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
'''
    if "Выбрано: ${_selectedFileIds.length}" not in text:
        text = replace_once(
            text,
            file_toolbar_anchor,
            file_toolbar,
            "file selection toolbar",
        )

    old_file_item = r'''                    final entry = entries[index];
                    return Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: () => _openEntry(entry),
                        borderRadius: BorderRadius.circular(22),
'''
    new_file_item = r'''                    final entry = entries[index];
                    final selected = _selectedFileIds.contains(entry.message.id);
                    return Material(
                      color: selected
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: .14)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: () => _selectedFileIds.isEmpty
                            ? _openEntry(entry)
                            : _toggleFileSelection(entry),
                        onLongPress: () => _toggleFileSelection(entry),
                        borderRadius: BorderRadius.circular(22),
'''
    text = replace_once(text, old_file_item, new_file_item, "file selectable item")
    write(path, text)


def patch_chat() -> None:
    path = "lib/chat_screen.dart"
    text = read(path)
    if "const String _androidInstallUrl" not in text:
        text = replace_once(
            text,
            "const String _landingBase =\n"
            "    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';\n",
            "const String _landingBase =\n"
            "    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';\n"
            "const String _androidInstallUrl =\n"
            "    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';\n",
            "chat install url",
        )
    text = text.replace(
        "          _playIncomingMessageSound(raw);\n"
        "          _playIncomingMessageSound(raw);\n",
        "          _playIncomingMessageSound(raw);\n",
    )
    text = replace_once(
        text,
        "  CgMessage? _replyingTo;\n",
        "  CgMessage? _replyingTo;\n"
        "  final Set<String> _selectedMessageIds = <String>{};\n",
        "message selection state",
    )

    if "void _toggleMessageSelection" not in text:
        methods = r'''  void _toggleMessageSelection(CgMessage message) {
    if (message.deleted) return;
    setState(() {
      if (!_selectedMessageIds.add(message.id)) {
        _selectedMessageIds.remove(message.id);
      }
    });
  }

  List<CgMessage> get _selectedMessages => _tunnel.messages
      .where((message) => _selectedMessageIds.contains(message.id))
      .toList(growable: false);

  Future<void> _copySelectedMessages() async {
    final value = _selectedMessages
        .map((message) => message.text.trim().isNotEmpty
            ? message.text.trim()
            : message.attachment?.name ?? '')
        .where((value) => value.isNotEmpty)
        .join('\n\n');
    if (value.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: value));
    }
    if (mounted) setState(_selectedMessageIds.clear);
  }

  Future<void> _forwardSelectedMessages() async {
    final selected = _selectedMessages;
    for (final message in selected) {
      await _forward(message);
    }
    if (mounted) setState(_selectedMessageIds.clear);
  }

  Future<void> _deleteSelectedMessages() async {
    final selected = _selectedMessages
        .where((message) => message.authorId == widget.profile.id)
        .toList(growable: false);
    for (final message in selected) {
      await _deleteMessage(message);
    }
    if (mounted) setState(_selectedMessageIds.clear);
  }

  void _sendMessageBackground(CgMessage message) {
    final session = _session;
    if (session == null) {
      unawaited(_connect().then((_) => _session?.sendMessage(message.toJson())));
      return;
    }
    unawaited(
      session.sendMessage(message.toJson()).timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      ),
    );
  }

  void _sendControlBackground(Map<String, dynamic> control) {
    final session = _session;
    if (session == null) return;
    unawaited(
      session.sendControl(control).timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      ),
    );
  }

'''
        text = replace_once(
            text,
            "  Future<void> _connect() async {\n",
            methods + "  Future<void> _connect() async {\n",
            "message selection methods",
        )

    old_send = r'''    _appendLocal(message);
    await _session?.sendMessage(message.toJson());
'''
    text = text.replace(old_send, "    _appendLocal(message);\n    _sendMessageBackground(message);\n")
    text = text.replace(
        "    await _session?.sendControl({\n",
        "    _sendControlBackground({\n",
    )
    text = text.replace(
        "    });\n  }\n\n  Future<void> _toggleReaction",
        "    });\n  }\n\n  Future<void> _toggleReaction",
        1,
    )

    old_invite_button = r'''              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Открой чат в Чернограме: $_deepInvite\n\nЕсли приложение не открылось: $_inviteUrl'
                        : 'Open the Chernogram chat: $_deepInvite\n\nIf the app did not open: $_inviteUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(widget.ru ? 'Отправить ссылку' : 'Share invite'),
                ),
              ),
'''
    new_invite_button = r'''              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Открой чат в Чернограме: $_deepInvite\n\nСсылка через браузер: $_inviteUrl\n\nЕсли приложения ещё нет: $_androidInstallUrl'
                        : 'Open the Chernogram chat: $_deepInvite\n\nBrowser link: $_inviteUrl\n\nInstall the app: $_androidInstallUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(
                    widget.ru ? 'Отправить чат и установку' : 'Share chat and install',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Установить Чернограм: $_androidInstallUrl'
                        : 'Install Chernogram: $_androidInstallUrl',
                  ),
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: Text(
                    widget.ru ? 'Только ссылка на установку' : 'Installation link only',
                  ),
                ),
              ),
'''
    text = replace_once(
        text,
        old_invite_button,
        new_invite_button,
        "invite install buttons",
    )

    toolbar_anchor = r'''            Expanded(
              child: _tunnel.messages.isEmpty
'''
    toolbar = r'''            if (_selectedMessageIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 5),
                child: Material(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => setState(_selectedMessageIds.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          widget.ru
                              ? 'Выбрано: ${_selectedMessageIds.length}'
                              : 'Selected: ${_selectedMessageIds.length}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: widget.ru ? 'Копировать' : 'Copy',
                        onPressed: _copySelectedMessages,
                        icon: const Icon(Icons.copy_rounded),
                      ),
                      IconButton(
                        tooltip: widget.ru ? 'Переслать' : 'Forward',
                        onPressed: _forwardSelectedMessages,
                        icon: const Icon(Icons.forward_rounded),
                      ),
                      IconButton(
                        tooltip: widget.ru ? 'Удалить свои' : 'Delete mine',
                        onPressed: _deleteSelectedMessages,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _tunnel.messages.isEmpty
'''
    if "Выбрано: ${_selectedMessageIds.length}" not in text:
        text = replace_once(text, toolbar_anchor, toolbar, "message selection toolbar")

    old_bubble = r'''                        return _MessageBubble(
                          message: message,
                          mine: mine,
                          groupChat: _isGroupChat,
                          privacyLens: widget.privacyLens,
                          ru: widget.ru,
                          onLongPress: () => _showMessageActions(message),
                        );
'''
    new_bubble = r'''                        final selected =
                            _selectedMessageIds.contains(message.id);
                        final bubble = DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: selected
                                ? Border.all(color: scheme.primary, width: 2)
                                : null,
                          ),
                          child: _MessageBubble(
                            message: message,
                            mine: mine,
                            groupChat: _isGroupChat,
                            privacyLens: widget.privacyLens,
                            ru: widget.ru,
                            onLongPress: () => _toggleMessageSelection(message),
                          ),
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _selectedMessageIds.isEmpty
                              ? null
                              : () => _toggleMessageSelection(message),
                          child: _selectedMessageIds.isNotEmpty || message.deleted
                              ? bubble
                              : Dismissible(
                                  key: ValueKey<String>('swipe:${message.id}'),
                                  direction: DismissDirection.horizontal,
                                  confirmDismiss: (direction) async {
                                    if (direction == DismissDirection.startToEnd) {
                                      _replyTo(message);
                                    } else {
                                      await _forward(message);
                                    }
                                    return false;
                                  },
                                  background: const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 18),
                                      child: Icon(Icons.reply_rounded),
                                    ),
                                  ),
                                  secondaryBackground: const Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 18),
                                      child: Icon(Icons.forward_rounded),
                                    ),
                                  ),
                                  child: bubble,
                                ),
                        );
'''
    text = replace_once(text, old_bubble, new_bubble, "message swipe selection")
    write(path, text)


def patch_calls() -> None:
    path = "lib/call_service.dart"
    text = read(path)
    text = text.replace(
        "'width': <String, dynamic>{'ideal': 1280},\n"
        "                  'height': <String, dynamic>{'ideal': 720},\n"
        "                  'frameRate': <String, dynamic>{'ideal': 30, 'max': 30},",
        "'width': <String, dynamic>{'ideal': 640},\n"
        "                  'height': <String, dynamic>{'ideal': 480},\n"
        "                  'frameRate': <String, dynamic>{'ideal': 24, 'max': 24},",
    )
    text = text.replace(
        "      final stream = await navigator.mediaDevices.getUserMedia(\n",
        "      final stream = await navigator.mediaDevices.getUserMedia(\n",
    )
    old_media_end = r'''        },
      );

      final peer = await createPeerConnection(<String, dynamic>{
'''
    new_media_end = r'''        },
      ).timeout(const Duration(seconds: 9));

      final peer = await createPeerConnection(<String, dynamic>{
'''
    text = replace_once(text, old_media_end, new_media_end, "bounded media startup")
    text = text.replace(
        "      await Helper.setSpeakerphoneOn(true);",
        "      await Helper.setSpeakerphoneOn(true).timeout(\n"
        "        const Duration(seconds: 2),\n"
        "        onTimeout: () {},\n"
        "      );",
    )
    text = text.replace(
        "_inviteTimer = Timer.periodic(const Duration(seconds: 3),",
        "_inviteTimer = Timer.periodic(const Duration(seconds: 5),",
    )
    old_signal = r'''    await session.sendSignal(<String, dynamic>{
      ...data,
      'callId': _callId,
      'from': _profileId,
      'video': widget.video,
      if (_peerId != null && _peerId!.isNotEmpty) 'target': _peerId,
    });
'''
    new_signal = r'''    await session
        .sendSignal(<String, dynamic>{
          ...data,
          'callId': _callId,
          'from': _profileId,
          'video': widget.video,
          if (_peerId != null && _peerId!.isNotEmpty) 'target': _peerId,
        })
        .timeout(const Duration(seconds: 5), onTimeout: () {});
'''
    text = replace_once(text, old_signal, new_signal, "bounded call signaling")
    old_hangup = r'''  Future<void> _hangUp() async {
    if (_ended) return;
    await _sendSignal(<String, dynamic>{'action': 'call_end'});
    _finish(_connectedAt == null ? 'cancelled' : 'completed');
  }
'''
    new_hangup = r'''  Future<void> _hangUp() async {
    if (_ended) return;
    unawaited(_sendSignal(<String, dynamic>{'action': 'call_end'}));
    _finish(_connectedAt == null ? 'cancelled' : 'completed');
  }
'''
    text = replace_once(text, old_hangup, new_hangup, "instant hangup")
    write(path, text)


def patch_permission_font() -> None:
    path = "lib/permission_center.dart"
    text = read(path).replace("FontWeight.w850", "FontWeight.w800")
    write(path, text)


def main() -> None:
    restore_stable_transport()
    patch_brand()
    patch_monitor()
    patch_shell()
    patch_chat()
    patch_calls()
    patch_permission_font()
    print("Chernogram 0.23 repair applied")


if __name__ == "__main__":
    main()
