import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import 'brand.dart';

enum GramMode { instagram, telegram }

class MediaLibraryScreen extends StatefulWidget {
  final bool ru;
  final ValueChanged<AssetEntity>? onSendToTunnel;

  const MediaLibraryScreen({
    super.key,
    required this.ru,
    this.onSendToTunnel,
  });

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  final _scroll = ScrollController();
  PermissionState? _permission;
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 500) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    _permission = permission;
    if (!permission.hasAccess) {
      setState(() => _loading = false);
      return;
    }
    _albums = await PhotoManager.getAssetPathList(
      hasAll: true,
      type: RequestType.common,
    );
    _album = _albums.isEmpty ? null : _albums.first;
    await _firstPage();
  }

  Future<void> _firstPage() async {
    _page = 0;
    final items = _album == null
        ? <AssetEntity>[]
        : await _album!.getAssetListPaged(page: 0, size: 90);
    if (!mounted) return;
    setState(() {
      _assets = items;
      _hasMore = items.length == 90;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _album == null) return;
    setState(() => _loadingMore = true);
    final items = await _album!.getAssetListPaged(page: _page + 1, size: 90);
    if (!mounted) return;
    setState(() {
      _page++;
      _assets.addAll(items);
      _hasMore = items.length == 90;
      _loadingMore = false;
    });
  }

  Future<void> _pickAlbum() async {
    final selected = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _albums.length,
          itemBuilder: (_, index) => ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(_albums[index].name),
            trailing: _albums[index].id == _album?.id
                ? const Icon(Icons.check_circle, color: ChernogramColors.orange)
                : null,
            onTap: () => Navigator.pop(context, _albums[index]),
          ),
        ),
      ),
    );
    if (selected == null || selected.id == _album?.id) return;
    setState(() {
      _album = selected;
      _loading = true;
    });
    await _firstPage();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!(_permission?.hasAccess ?? false)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 62),
              const SizedBox(height: 16),
              Text(
                widget.ru
                    ? 'Разрешите доступ к фото и видео — файлы останутся только на устройстве.'
                    : 'Allow access to photos and videos. Files stay on your device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.lock_open),
                label: Text(widget.ru ? 'Разрешить доступ' : 'Allow access'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Column(
            children: [
              _CapabilityStrip(ru: widget.ru),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickAlbum,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: ChernogramColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_open_outlined, size: 20),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _album?.name ??
                                    (widget.ru ? 'Все медиа' : 'All media'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _assets.isEmpty
              ? Center(
                  child: Text(widget.ru ? 'Медиа не найдено' : 'No media found'),
                )
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: _assets.length + (_loadingMore ? 3 : 0),
                  itemBuilder: (_, index) {
                    if (index >= _assets.length) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    final asset = _assets[index];
                    return _AssetThumb(
                      asset: asset,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MediaEditorScreen(
                            asset: asset,
                            ru: widget.ru,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CapabilityStrip extends StatelessWidget {
  final bool ru;

  const _CapabilityStrip({required this.ru});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1307), Color(0xFF21180D)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF5C3516)),
      ),
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          const ChernogramLogo(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ru ? 'Выберите фото или видео' : 'Choose a photo or video',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  ru
                      ? 'Предпросмотр Instagram/Telegram • фильтры • текст • экспорт'
                      : 'Instagram/Telegram preview • filters • text • export',
                  style: const TextStyle(
                    fontSize: 11,
                    color: ChernogramColors.textSoft,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 15),
        ],
      ),
    );
  }
}

class _AssetThumb extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _AssetThumb({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize.square(320),
              quality: 82,
            ),
            builder: (_, snapshot) => snapshot.data == null
                ? const ColoredBox(
                    color: ChernogramColors.surfaceHigh,
                    child: Icon(Icons.image_outlined),
                  )
                : Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
          if (asset.type == AssetType.video)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 13),
                    Text(
                      _durationText(asset.videoDuration),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MediaEditorScreen extends StatefulWidget {
  final AssetEntity asset;
  final bool ru;

  const MediaEditorScreen({
    super.key,
    required this.asset,
    required this.ru,
  });

  @override
  State<MediaEditorScreen> createState() => _MediaEditorScreenState();
}

class _MediaEditorScreenState extends State<MediaEditorScreen> {
  final _caption = TextEditingController();
  final _repaintKey = GlobalKey();
  GramMode _gram = GramMode.instagram;
  double _brightness = 0;
  double _contrast = 1;
  double _saturation = 1;
  bool _exporting = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  List<double> get _matrix {
    final s = _saturation;
    final c = _contrast;
    final b = _brightness * 255;
    const r = .213;
    const g = .715;
    const bl = .072;
    return <double>[
      (r * (1 - s) + s) * c,
      (g * (1 - s)) * c,
      (bl * (1 - s)) * c,
      0,
      b + 128 * (1 - c),
      (r * (1 - s)) * c,
      (g * (1 - s) + s) * c,
      (bl * (1 - s)) * c,
      0,
      b + 128 * (1 - c),
      (r * (1 - s)) * c,
      (g * (1 - s)) * c,
      (bl * (1 - s) + s) * c,
      0,
      b + 128 * (1 - c),
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Future<void> _exportPreview() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      if (widget.asset.type == AssetType.video) {
        final file = await widget.asset.file;
        if (file != null) {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: _caption.text.trim(),
          );
        }
        return;
      }
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/chernogram-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      await Share.shareXFiles([XFile(file.path)], text: _caption.text.trim());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _wrap(String left, String right) {
    final value = _caption.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final selected = value.text.substring(start, end);
    final replacement = '$left$selected$right';
    _caption.value = TextEditingValue(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    return Scaffold(
      appBar: AppBar(
        title: Text(ru ? 'Студия публикации' : 'Publishing studio'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            SegmentedButton<GramMode>(
              segments: const [
                ButtonSegment(
                  value: GramMode.instagram,
                  icon: Icon(Icons.photo_camera_outlined),
                  label: Text('Instagram'),
                ),
                ButtonSegment(
                  value: GramMode.telegram,
                  icon: Icon(Icons.send_outlined),
                  label: Text('Telegram'),
                ),
              ],
              selected: {_gram},
              onSelectionChanged: (value) => setState(() => _gram = value.first),
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              key: _repaintKey,
              child: Container(
                color: _gram == GramMode.instagram
                    ? const Color(0xFF111111)
                    : const Color(0xFF17212B),
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostHeader(gram: _gram, ru: ru),
                    AspectRatio(
                      aspectRatio: _gram == GramMode.instagram ? 1 : 1.35,
                      child: FutureBuilder<Uint8List?>(
                        future: widget.asset.thumbnailDataWithSize(
                          const ThumbnailSize(1400, 1400),
                          quality: 96,
                        ),
                        builder: (_, snapshot) {
                          if (snapshot.data == null) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          return ColorFiltered(
                            colorFilter: ColorFilter.matrix(_matrix),
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Text(
                        _caption.text.isEmpty
                            ? (ru
                                  ? 'Здесь сразу видно, как будет выглядеть подпись.'
                                  : 'See how your caption will look here.')
                            : _caption.text,
                        style: TextStyle(
                          fontSize: 13,
                          color: _caption.text.isEmpty
                              ? Colors.white38
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _EditorPanel(
              title: ru ? 'Обработка медиа' : 'Media filters',
              child: Column(
                children: [
                  _FilterSlider(
                    icon: Icons.brightness_6_outlined,
                    label: ru ? 'Яркость' : 'Brightness',
                    value: _brightness,
                    min: -.5,
                    max: .5,
                    onChanged: (value) => setState(() => _brightness = value),
                  ),
                  _FilterSlider(
                    icon: Icons.contrast,
                    label: ru ? 'Контраст' : 'Contrast',
                    value: _contrast,
                    min: .5,
                    max: 1.7,
                    onChanged: (value) => setState(() => _contrast = value),
                  ),
                  _FilterSlider(
                    icon: Icons.palette_outlined,
                    label: ru ? 'Насыщенность' : 'Saturation',
                    value: _saturation,
                    min: 0,
                    max: 2,
                    onChanged: (value) => setState(() => _saturation = value),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _brightness = 0;
                        _contrast = 1;
                        _saturation = 1;
                      }),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(ru ? 'Сбросить' : 'Reset'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _EditorPanel(
              title: ru ? 'Текст публикации' : 'Post text',
              child: Column(
                children: [
                  TextField(
                    controller: _caption,
                    minLines: 4,
                    maxLines: 8,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: ru
                          ? 'Напишите пост, подпись или сообщение…'
                          : 'Write a post, caption or message…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      IconButton.filledTonal(
                        tooltip: ru ? 'Жирный' : 'Bold',
                        onPressed: () => _wrap('**', '**'),
                        icon: const Icon(Icons.format_bold),
                      ),
                      IconButton.filledTonal(
                        tooltip: ru ? 'Курсив' : 'Italic',
                        onPressed: () => _wrap('_', '_'),
                        icon: const Icon(Icons.format_italic),
                      ),
                      IconButton.filledTonal(
                        tooltip: ru ? 'Цитата' : 'Quote',
                        onPressed: () => _wrap('> ', ''),
                        icon: const Icon(Icons.format_quote),
                      ),
                      for (final emoji in ['🔥', '❤️', '✨', '📸', '👇'])
                        ActionChip(
                          label: Text(emoji),
                          onPressed: () => _wrap(emoji, ''),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _exporting ? null : _exportPreview,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(
                ru
                    ? 'Экспортировать и поделиться'
                    : 'Export and share',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  final GramMode gram;
  final bool ru;

  const _PostHeader({required this.gram, required this.ru});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 17,
            backgroundColor: ChernogramColors.orange,
            child: ChernogramLogo(size: 23),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gram == GramMode.instagram ? 'your_profile' : 'Your channel',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  ru ? 'Предпросмотр публикации' : 'Post preview',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
          Icon(gram == GramMode.instagram ? Icons.more_horiz : Icons.visibility),
        ],
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _EditorPanel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChernogramColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF322A24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FilterSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _FilterSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        SizedBox(width: 102, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class DraftStudioScreen extends StatefulWidget {
  final bool ru;

  const DraftStudioScreen({super.key, required this.ru});

  @override
  State<DraftStudioScreen> createState() => _DraftStudioScreenState();
}

class _DraftStudioScreenState extends State<DraftStudioScreen> {
  final _controller = TextEditingController();
  GramMode _gram = GramMode.telegram;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _wrap(String left, String right) {
    final value = _controller.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0 ? value.text.length : value.selection.end;
    final selected = value.text.substring(start, end);
    final replacement = '$left$selected$right';
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        Text(
          ru ? 'Текстовый конструктор' : 'Text composer',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          ru
              ? 'Соберите текст и сразу проверьте его в стиле нужной соцсети.'
              : 'Compose text and preview it in the target social style.',
          style: const TextStyle(color: ChernogramColors.textSoft),
        ),
        const SizedBox(height: 14),
        SegmentedButton<GramMode>(
          segments: const [
            ButtonSegment(value: GramMode.instagram, label: Text('Instagram')),
            ButtonSegment(value: GramMode.telegram, label: Text('Telegram')),
          ],
          selected: {_gram},
          onSelectionChanged: (value) => setState(() => _gram = value.first),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gram == GramMode.telegram
                ? const Color(0xFF17212B)
                : ChernogramColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _controller.text.isEmpty
                ? (ru ? 'Предпросмотр текста появится здесь' : 'Text preview appears here')
                : _controller.text,
            style: TextStyle(
              color: _controller.text.isEmpty ? Colors.white38 : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          minLines: 8,
          maxLines: 16,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: ru ? 'Введите текст публикации…' : 'Enter post text…',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            IconButton.filledTonal(
              onPressed: () => _wrap('**', '**'),
              icon: const Icon(Icons.format_bold),
            ),
            IconButton.filledTonal(
              onPressed: () => _wrap('_', '_'),
              icon: const Icon(Icons.format_italic),
            ),
            IconButton.filledTonal(
              onPressed: () => _wrap('`', '`'),
              icon: const Icon(Icons.code),
            ),
            IconButton.filledTonal(
              onPressed: () => _wrap('> ', ''),
              icon: const Icon(Icons.format_quote),
            ),
            for (final emoji in ['🔥', '❤️', '✅', '🚀', '📌', '👇'])
              ActionChip(label: Text(emoji), onPressed: () => _wrap(emoji, '')),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _controller.text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ru ? 'Текст скопирован' : 'Text copied')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: Text(ru ? 'Копировать' : 'Copy'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Share.share(_controller.text),
                icon: const Icon(Icons.share),
                label: Text(ru ? 'Поделиться' : 'Share'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _durationText(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
