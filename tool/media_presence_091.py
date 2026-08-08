from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:320]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_block(path: str, start: str, end: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    a = text.find(start)
    if a < 0:
        raise SystemExit(f'Start not found in {path}: {start!r}')
    b = text.find(end, a)
    if b < 0:
        raise SystemExit(f'End not found in {path}: {end!r}')
    file.write_text(text[:a] + new + text[b:], encoding='utf-8')


def _find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    i = open_index
    quote = None
    triple = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if quote is not None:
            if triple:
                if text.startswith(quote * 3, i):
                    i += 3
                    quote = None
                    triple = False
                    continue
                i += 1
                continue
            if ch == '\\':
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            if text.startswith(ch * 3, i):
                quote = ch
                triple = True
                i += 3
            else:
                quote = ch
                i += 1
            continue
        if ch == '/' and nxt == '/':
            eol = text.find('\n', i + 2)
            i = len(text) if eol < 0 else eol + 1
            continue
        if ch == '/' and nxt == '*':
            end = text.find('*/', i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise SystemExit('Unbalanced Scaffold parentheses')


def wrap_chat_scaffold() -> None:
    path = Path('lib/chat_screen.dart')
    text = path.read_text(encoding='utf-8')
    anchor = '  Widget build(BuildContext context) {\n    final scheme = Theme.of(context).colorScheme;\n    final canInvite = _isOwner || !_tunnel.isPrivate;\n'
    anchor_at = text.find(anchor)
    if anchor_at < 0:
        raise SystemExit('Chat build anchor not found')
    return_at = text.find('    return Scaffold(', anchor_at)
    if return_at < 0:
        raise SystemExit('Chat Scaffold not found')
    scaffold_at = return_at + len('    return ')
    open_at = text.find('(', scaffold_at)
    close_at = _find_matching_paren(text, open_at)
    semi_at = close_at + 1
    while semi_at < len(text) and text[semi_at].isspace():
        semi_at += 1
    if semi_at >= len(text) or text[semi_at] != ';':
        raise SystemExit('Chat Scaffold semicolon not found')
    scaffold_expr = text[scaffold_at:close_at + 1]
    replacement = '''    return DropTarget(
      onDragEntered: (_) {
        if (Platform.isWindows && !_dragActive && mounted) {
          setState(() => _dragActive = true);
        }
      },
      onDragExited: (_) {
        if (_dragActive && mounted) setState(() => _dragActive = false);
      },
      onDragDone: (details) {
        if (_dragActive && mounted) setState(() => _dragActive = false);
        unawaited(_sendDroppedFiles(details.files));
      },
      child: Stack(
        children: <Widget>[
''' + scaffold_expr + ''',
          if (_dragActive)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0xAA111829),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE222B40),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF7B68FF),
                          width: 2,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.file_download_outlined, size: 30),
                          SizedBox(width: 12),
                          Text(
                            'Отпустите файлы — отправим в чат',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );'''
    path.write_text(text[:return_at] + replacement + text[semi_at + 1:], encoding='utf-8')


# ---------------------------------------------------------------------------
# 0.91: media rendering + Windows drop + reliable Android background delivery.
# Transport endpoints/routing are not changed.
# ---------------------------------------------------------------------------
replace_once('pubspec.yaml', 'version: 0.90.0+90', 'version: 0.91.0+91')
replace_once(
    'pubspec.yaml',
    '  cryptography: ^2.9.0\n',
    '  cryptography: ^2.9.0\n  cross_file: ^0.3.5+4\n  desktop_drop: ^0.7.1\n',
)

# ---------------------------------------------------------------------------
# Windows drag & drop: any regular files dropped onto an open chat are sent.
# ---------------------------------------------------------------------------
chat = Path('lib/chat_screen.dart')
text = chat.read_text(encoding='utf-8')
if "import 'package:desktop_drop/desktop_drop.dart';" not in text:
    text = text.replace(
        "import 'package:file_picker/file_picker.dart';\n",
        "import 'package:file_picker/file_picker.dart';\n"
        "import 'package:cross_file/cross_file.dart';\n"
        "import 'package:desktop_drop/desktop_drop.dart';\n",
        1,
    )
chat.write_text(text, encoding='utf-8')
replace_once(
    'lib/chat_screen.dart',
    '  bool _sendingFile = false;\n',
    '  bool _sendingFile = false;\n  bool _dragActive = false;\n',
)
replace_once(
    'lib/chat_screen.dart',
    '  Future<void> _showAttachmentMenu() async {\n',
    r'''  Future<void> _sendDroppedFiles(List<XFile> files) async {
    if (!Platform.isWindows || files.isEmpty || _sendingFile) return;
    setState(() => _sendingFile = true);
    var sent = 0;
    try {
      for (final dropped in files) {
        final path = dropped.path.trim();
        if (path.isEmpty) continue;
        final source = File(path);
        if (!await source.exists()) continue;
        final id = CgIds.random(20);
        final name = dropped.name.trim().isEmpty
            ? path.split(RegExp(r'[\\/]')).last
            : dropped.name;
        final local = await CgMediaStore.persistFile(
          attachmentId: id,
          name: name,
          source: source,
        );
        final size = await local.length();
        await _sendAttachment(
          CgAttachment(
            id: id,
            name: name,
            size: size,
            kind: _attachmentKind(name),
            localPath: local.path,
          ),
        );
        sent += 1;
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
    if (mounted && sent > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Отправлено файлов: $sent')),
      );
    }
  }

  Future<void> _showAttachmentMenu() async {
''',
)
wrap_chat_scaffold()

# ---------------------------------------------------------------------------
# Inline media: local-path images/GIFs always show a preview; video has a real
# first-frame preview; all media opens in the Chernogram full-screen viewer.
# Circle waits for the completed remote transfer and re-initializes on update.
# ---------------------------------------------------------------------------
media_block = r'''class CgInlineAttachment extends StatefulWidget {
  final CgAttachment attachment;
  final bool hidden;

  const CgInlineAttachment({
    super.key,
    required this.attachment,
    required this.hidden,
  });

  @override
  State<CgInlineAttachment> createState() => _CgInlineAttachmentState();
}

class _CgInlineAttachmentState extends State<CgInlineAttachment> {
  final AudioPlayer _audio = AudioPlayer();
  File? _file;
  bool _loading = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prime());
  }

  @override
  void didUpdateWidget(covariant CgInlineAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.localPath != widget.attachment.localPath ||
        oldWidget.attachment.dataBase64 != widget.attachment.dataBase64) {
      _file = null;
      unawaited(_prime());
    }
  }

  @override
  void dispose() {
    unawaited(_audio.dispose());
    super.dispose();
  }

  Uint8List? get _bytes {
    final raw = widget.attachment.dataBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _prime() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (!mounted) return;
    if (file != null && await file.exists()) setState(() => _file = file);
  }

  Future<File?> _ensure() async {
    if (_file != null && await _file!.exists()) return _file;
    if (mounted) setState(() => _loading = true);
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (mounted) {
      setState(() {
        _file = file;
        _loading = false;
      });
    }
    return file;
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final saved = await CgMediaStore.downloadToSystem(widget.attachment);
    if (!mounted) return;
    setState(() => _downloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == null ? 'Не удалось сохранить файл' : 'Сохранено: $saved',
        ),
      ),
    );
  }

  Widget _withDownload(Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      child,
      const SizedBox(height: 2),
      TextButton.icon(
        onPressed: _downloading ? null : _download,
        icon: _downloading
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_rounded, size: 18),
        label: Text(_downloading ? 'Сохраняем…' : 'Скачать'),
      ),
    ],
  );

  Future<void> _openImage() async {
    final bytes = _bytes;
    final file = bytes == null ? await _ensure() : _file;
    if (!mounted || (bytes == null && file == null)) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgImageViewer(
          bytes: bytes,
          file: bytes == null ? file : null,
          title: widget.attachment.name,
        ),
      ),
    );
  }

  Future<void> _playAudio() async {
    if (_audio.playing) {
      await _audio.pause();
      return;
    }
    final file = await _ensure();
    if (file == null) return;
    if (_audio.audioSource == null) await _audio.setFilePath(file.path);
    await _audio.play();
  }

  Future<void> _openGeneric() async {
    final file = await _ensure();
    if (file == null || !mounted) return;
    await OpenFilex.open(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final bytes = _bytes;
    final local = _file ??
        ((attachment.localPath?.isNotEmpty ?? false)
            ? File(attachment.localPath!)
            : null);
    final hasLocal = local?.existsSync() == true;

    // Visual media is never hidden behind a generic document card.
    if (attachment.kind == 'image') {
      final preview = bytes != null
          ? Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)
          : hasLocal
          ? Image.file(local!, fit: BoxFit.contain, gaplessPlayback: true)
          : const Center(child: CircularProgressIndicator(strokeWidth: 2));
      return _withDownload(
        GestureDetector(
          onTap: _openImage,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 120,
              maxWidth: 290,
              minHeight: 90,
              maxHeight: 380,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: preview,
          ),
        ),
      );
    }
    if (attachment.kind == 'video') {
      return _withDownload(_CgInlineVideoPreview(attachment: attachment));
    }
    if (attachment.kind == 'circle') {
      return _withDownload(_CgInlineCircle(attachment: attachment));
    }

    if (widget.hidden) {
      return Container(
        width: 250,
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.visibility_off_outlined, color: Colors.white70),
      );
    }

    if (CgMediaStore.isAudio(attachment)) {
      return _withDownload(
        Container(
          width: 278,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              StreamBuilder<PlayerState>(
                stream: _audio.playerStateStream,
                builder: (_, snapshot) => IconButton.filledTonal(
                  onPressed: _loading ? null : _playAudio,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          snapshot.data?.playing == true
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      attachment.kind == 'voice'
                          ? 'Голосовое сообщение'
                          : attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    StreamBuilder<Duration>(
                      stream: _audio.positionStream,
                      builder: (_, position) => StreamBuilder<Duration?>(
                        stream: _audio.durationStream,
                        builder: (_, duration) {
                          final total = duration.data ?? Duration.zero;
                          final current = position.data ?? Duration.zero;
                          final max = math.max(1, total.inMilliseconds).toDouble();
                          return Slider(
                            min: 0,
                            max: max,
                            value: current.inMilliseconds
                                .clamp(0, max.toInt())
                                .toDouble(),
                            onChanged: total == Duration.zero
                                ? null
                                : (value) => _audio.seek(
                                    Duration(milliseconds: value.round()),
                                  ),
                          );
                        },
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

    return _withDownload(
      InkWell(
        onTap: _loading ? null : _openGeneric,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 270,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                attachment.kind == 'archive'
                    ? Icons.folder_zip_outlined
                    : Icons.description_outlined,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      attachment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      CgMediaStore.fileSize(attachment.size),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              Icon(_loading ? Icons.hourglass_top_rounded : Icons.open_in_new),
            ],
          ),
        ),
      ),
    );
  }
}

class _CgInlineVideoPreview extends StatefulWidget {
  final CgAttachment attachment;

  const _CgInlineVideoPreview({required this.attachment});

  @override
  State<_CgInlineVideoPreview> createState() => _CgInlineVideoPreviewState();
}

class _CgInlineVideoPreviewState extends State<_CgInlineVideoPreview> {
  VideoPlayerController? _controller;
  Timer? _retry;
  File? _file;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant _CgInlineVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.localPath != widget.attachment.localPath ||
        oldWidget.attachment.id != widget.attachment.id) {
      unawaited(_resetAndInitialize());
    }
  }

  Future<void> _resetAndInitialize() async {
    _retry?.cancel();
    final old = _controller;
    _controller = null;
    _ready = false;
    if (old != null) await old.dispose();
    await _initialize();
  }

  Future<void> _initialize() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !await file.exists()) {
      _retry = Timer(const Duration(milliseconds: 650), () {
        if (mounted) unawaited(_initialize());
      });
      return;
    }
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _file = file;
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      _retry = Timer(const Duration(milliseconds: 750), () {
        if (mounted) unawaited(_initialize());
      });
    }
  }

  Future<void> _open() async {
    final file = _file ?? await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgVideoPlayerScreen(
          file: file,
          circle: false,
          title: widget.attachment.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return GestureDetector(
      onTap: _open,
      child: SizedBox(
        width: 286,
        height: 190,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: Colors.black,
            child: !_ready || controller == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      const Center(
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _retry?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

class _CgInlineCircle extends StatefulWidget {
  final CgAttachment attachment;

  const _CgInlineCircle({required this.attachment});

  @override
  State<_CgInlineCircle> createState() => _CgInlineCircleState();
}

class _CgInlineCircleState extends State<_CgInlineCircle> {
  VideoPlayerController? _controller;
  Timer? _retry;
  File? _file;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant _CgInlineCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.localPath != widget.attachment.localPath ||
        oldWidget.attachment.id != widget.attachment.id) {
      unawaited(_resetAndInitialize());
    }
  }

  Future<void> _resetAndInitialize() async {
    _retry?.cancel();
    final old = _controller;
    _controller = null;
    _ready = false;
    if (old != null) await old.dispose();
    await _initialize();
  }

  Future<void> _initialize() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !await file.exists()) {
      _retry = Timer(const Duration(milliseconds: 600), () {
        if (mounted) unawaited(_initialize());
      });
      return;
    }
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _file = file;
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      _retry = Timer(const Duration(milliseconds: 700), () {
        if (mounted) unawaited(_initialize());
      });
    }
  }

  Future<void> _open() async {
    final file = _file ?? await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgVideoPlayerScreen(
          file: file,
          circle: true,
          title: widget.attachment.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return GestureDetector(
      onTap: _open,
      child: SizedBox.square(
        dimension: 176,
        child: ClipOval(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: !_ready || controller == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _retry?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

'''
replace_block(
    'lib/chat_media.dart',
    'class CgInlineAttachment extends StatefulWidget {',
    'class CgMediaLibraryScreen extends StatefulWidget {',
    media_block + 'class CgMediaLibraryScreen extends StatefulWidget {',
)

# Full screen images support both in-memory and transferred local files.
replace_block(
    'lib/chat_media.dart',
    'class CgImageViewer extends StatelessWidget {',
    'class CgVideoPlayerScreen extends StatefulWidget {',
    r'''class CgImageViewer extends StatelessWidget {
  final Uint8List? bytes;
  final File? file;
  final String title;

  const CgImageViewer({
    super.key,
    this.bytes,
    this.file,
    required this.title,
  }) : assert(bytes != null || file != null);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: InteractiveViewer(
      minScale: .5,
      maxScale: 6,
      child: Center(
        child: file != null
            ? Image.file(file!, fit: BoxFit.contain, gaplessPlayback: true)
            : Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    ),
  );
}

class CgVideoPlayerScreen extends StatefulWidget {''',
)

# Real previews in Files & Media list: local image/GIF and first video frame.
replace_block(
    'lib/chat_media.dart',
    'class _MediaLeading extends StatelessWidget {',
    'class CgImageViewer extends StatelessWidget {',
    r'''class _MediaLeading extends StatelessWidget {
  final CgMediaItem item;

  const _MediaLeading({required this.item});

  @override
  Widget build(BuildContext context) {
    final attachment = item.attachment;
    final localPath = attachment.localPath;
    if (attachment.kind == 'image') {
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }
      }
      if (attachment.dataBase64 != null) {
        try {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              base64Decode(attachment.dataBase64!),
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        } catch (_) {}
      }
    }
    if (CgMediaStore.isVideo(attachment)) {
      return _CgMediaVideoThumb(attachment: attachment);
    }
    return CircleAvatar(
      child: Icon(
        CgMediaStore.isAudio(attachment)
            ? Icons.graphic_eq_rounded
            : Icons.description_outlined,
      ),
    );
  }
}

class _CgMediaVideoThumb extends StatefulWidget {
  final CgAttachment attachment;

  const _CgMediaVideoThumb({required this.attachment});

  @override
  State<_CgMediaVideoThumb> createState() => _CgMediaVideoThumbState();
}

class _CgMediaVideoThumbState extends State<_CgMediaVideoThumb> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !await file.exists()) return;
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.square(
        dimension: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: Icon(Icons.play_arrow_rounded),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 58,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

class CgImageViewer extends StatelessWidget {''',
)

# Media-library image opening must also work for local-path-only transfers.
lib = Path('lib/chat_media.dart')
text = lib.read_text(encoding='utf-8')
old_open = '''    if (item.attachment.kind == 'image' && item.attachment.dataBase64 != null) {
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
if old_open in text:
    text = text.replace(old_open, '''    if (item.attachment.kind == 'image') {
      Uint8List? bytes;
      final raw = item.attachment.dataBase64;
      if (raw != null && raw.isNotEmpty) {
        try {
          bytes = base64Decode(raw);
        } catch (_) {}
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CgImageViewer(
            bytes: bytes,
            file: bytes == null ? file : null,
            title: item.attachment.name,
          ),
        ),
      );
      return;
    }
''', 1)
lib.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Android: background receiver is enabled by default after the UI is alive,
# survives normal minimize/lock/close, watches every room, and lock-screen
# message notifications expose sender/text. Force-stop remains an OS boundary.
# ---------------------------------------------------------------------------
bg = Path('lib/background_runtime.dart')
text = bg.read_text(encoding='utf-8')
if "import 'dart:typed_data';" not in text:
    text = text.replace("import 'dart:io';\n", "import 'dart:io';\nimport 'dart:typed_data';\n", 1)
text = text.replace("const String _messageChannelId = 'chernogram_messages';", "const String _messageChannelId = 'chernogram_messages_v2';")
text = text.replace("const String _callChannelId = 'chernogram_calls_v2';", "const String _callChannelId = 'chernogram_calls_v3';")
text = text.replace('        autoStartOnBoot: false,', '        autoStartOnBoot: true,', 1)
text = text.replace('    return prefs.getBool(_backgroundEnabledKey) ?? false;', '    return prefs.getBool(_backgroundEnabledKey) ?? true;', 1)
text = text.replace('  for (final tunnel in recent.take(12)) {', '  for (final tunnel in recent) {', 1)
text = text.replace('          visibility: NotificationVisibility.private,', '          visibility: NotificationVisibility.public,', 1)
# Ensure call notification sound repeats until call notification is cancelled/times out.
call_anchor = '''          icon: 'chernogram_launcher_icon',
          playSound: true,
          sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
          enableVibration: true,
'''
if call_anchor in text:
    text = text.replace(call_anchor, '''          icon: 'chernogram_launcher_icon',
          playSound: true,
          sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          additionalFlags: Int32List.fromList(<int>[4]),
''', 1)
bg.write_text(text, encoding='utf-8')

# Start background delivery only after the first UI frames, not before runApp.
main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
old_push_only = '''  unawaited(() async {
    try {
      await CgPushService.initialize();
    } catch (_) {}
  }());
'''
new_background = '''  unawaited(() async {
    if (Platform.isAndroid) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        await CgBackgroundRuntime.initialize();
        if (await CgBackgroundRuntime.isEnabled()) {
          await CgBackgroundRuntime.setEnabled(true);
        }
        CgBackgroundRuntime.setAppVisible(true);
      } catch (_) {}
    }
    try {
      await CgPushService.initialize();
    } catch (_) {}
  }());
'''
if old_push_only not in text:
    raise SystemExit('0.88 push-only startup block not found for 0.91')
main.write_text(text.replace(old_push_only, new_background, 1), encoding='utf-8')

# Push/local notification channels mirror background-service channels.
push = Path('lib/push_service.dart')
text = push.read_text(encoding='utf-8')
if "import 'dart:typed_data';" not in text:
    text = text.replace("import 'dart:io';\n", "import 'dart:io';\nimport 'dart:typed_data';\n", 1)
text = text.replace("'chernogram_messages',", "'chernogram_messages_v2',")
text = text.replace("'chernogram_calls_v2',", "'chernogram_calls_v3',")
text = text.replace('        visibility: NotificationVisibility.private,', '        visibility: NotificationVisibility.public,')
# Add insistent flag to the call notification details if not already present.
push_call = '''        sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
      ),
'''
if push_call in text:
    text = text.replace(push_call, '''        sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        additionalFlags: Int32List.fromList(<int>[4]),
      ),
''', 1)
push.write_text(text, encoding='utf-8')

# Wake lock permission helps keep the foreground remote-messaging service alive
# while the screen is off; actual OEM battery policy still belongs to Android.
manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')
if 'android.permission.WAKE_LOCK' not in text:
    marker = '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n'
    if marker in text:
        text = text.replace(marker, marker + '    <uses-permission android:name="android.permission.WAKE_LOCK" />\n', 1)
manifest.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Profile: compact @nickname on the home header, plus explicit photo removal.
# ---------------------------------------------------------------------------
light = Path('lib/light/light_chat_app.dart')
text = light.read_text(encoding='utf-8')
text = text.replace(
    "            subtitle: 'Комнаты, звонки и файлы через интернет',",
    "            subtitle: '@${widget.profile.nickname}',",
    1,
)
# Home-side removal method.
name_anchor = '  Future<void> _changeProfileName() async {\n'
if name_anchor not in text:
    raise SystemExit('Profile-name method anchor missing')
clear_method = r'''  Future<void> _clearProfilePhoto() async {
    final profile = _profile;
    if (profile == null || profile.avatarBase64 == null) return;
    final updated = CgProfile(
      id: profile.id,
      nickname: profile.nickname,
      createdAt: profile.createdAt,
    );
    await CgStore.saveProfile(updated);
    if (mounted) setState(() => _profile = updated);
    unawaited(_syncMonitor());
  }

'''
text = text.replace(name_anchor, clear_method + name_anchor, 1)
# Pass callback to profile page.
text = text.replace(
    '        onPhoto: _changeProfilePhoto,\n        onName: _changeProfileName,',
    '        onPhoto: _changeProfilePhoto,\n        onClearPhoto: _clearProfilePhoto,\n        onName: _changeProfileName,',
    1,
)
# Profile class callback field/constructor.
text = text.replace(
    '  final Future<void> Function() onPhoto;\n  final Future<void> Function() onName;',
    '  final Future<void> Function() onPhoto;\n  final Future<void> Function() onClearPhoto;\n  final Future<void> Function() onName;',
    1,
)
text = text.replace(
    '    required this.onPhoto,\n    required this.onName,',
    '    required this.onPhoto,\n    required this.onClearPhoto,\n    required this.onName,',
    1,
)
# Add delete-photo button under rename.
rename_button = '''                  OutlinedButton.icon(
                    onPressed: onName,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Изменить имя'),
                  ),
'''
if rename_button not in text:
    raise SystemExit('Rename profile button not found')
text = text.replace(rename_button, rename_button + '''                  if (profile.avatarBase64 != null) ...<Widget>[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: onClearPhoto,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Удалить фото профиля'),
                    ),
                  ],
''', 1)
light.write_text(text, encoding='utf-8')

print('Chernogram 0.91 media/background/profile patch applied')
