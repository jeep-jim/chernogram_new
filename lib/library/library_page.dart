import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../brand.dart';
import '../optical/optical_models.dart';
import 'library_models.dart';
import 'library_search.dart';
import 'library_store.dart';

class ChernogramLibraryPage extends StatefulWidget {
  final OpticalProfile profile;
  final List<OpticalRoom> rooms;
  final Future<void> Function(OpticalRoom room) onOpenRoom;

  const ChernogramLibraryPage({
    super.key,
    required this.profile,
    required this.rooms,
    required this.onOpenRoom,
  });

  @override
  State<ChernogramLibraryPage> createState() => _ChernogramLibraryPageState();
}

class _ChernogramLibraryPageState extends State<ChernogramLibraryPage> {
  final TextEditingController _search = TextEditingController();
  List<LibraryItem> _items = <LibraryItem>[];
  String? _kind;
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChernogramLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rooms, widget.rooms)) unawaited(_syncRooms());
  }

  Future<void> _load() async {
    var items = await LibraryStore.loadItems();
    items = await LibraryStore.syncRooms(
      rooms: widget.rooms,
      current: items,
      localDeviceId: widget.profile.id,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _syncRooms() async {
    final items = await LibraryStore.syncRooms(
      rooms: widget.rooms,
      current: _items,
      localDeviceId: widget.profile.id,
    );
    if (mounted) setState(() => _items = items);
  }

  Future<void> _importFiles() async {
    if (_importing) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _importing = true);
    try {
      final items = await LibraryStore.importFiles(
        files: result.files,
        current: _items,
        ownerId: widget.profile.id,
        ownerName: widget.profile.nickname,
        deviceId: widget.profile.id,
      );
      if (mounted) setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _remove(LibraryItem item) async {
    final imported = item.roomId == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать из библиотеки?'),
        content: Text(
          imported
              ? 'Можно удалить только запись или также локальную копию «${item.name}».'
              : 'Вложение останется в комнате. Из библиотеки удалится только индекс.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final items = await LibraryStore.removeItem(
      id: item.id,
      current: _items,
      deleteLocalCopy: imported,
    );
    if (mounted) setState(() => _items = items);
  }

  Future<void> _open(LibraryItem item) async {
    final path = item.localPath;
    if (path == null || !await File(path).exists()) {
      if (item.roomId != null) {
        final room = widget.rooms.where((value) => value.id == item.roomId).firstOrNull;
        if (room != null) await widget.onOpenRoom(room);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл сейчас недоступен.')),
        );
      }
      return;
    }
    if (!mounted) return;
    switch (item.kind) {
      case LibraryKinds.image:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => _ImageViewer(item: item)),
        );
      case LibraryKinds.audio:
      case LibraryKinds.voice:
        final audio = _items
            .where(
              (value) =>
                  value.available &&
                  (value.kind == LibraryKinds.audio || value.kind == LibraryKinds.voice),
            )
            .toList();
        final index = max(0, audio.indexWhere((value) => value.id == item.id));
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LibraryAudioPlayer(items: audio, initialIndex: index),
          ),
        );
      case LibraryKinds.video:
      case LibraryKinds.circle:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LibraryVideoPlayer(
              item: item,
              circular: item.kind == LibraryKinds.circle,
            ),
          ),
        );
      default:
        await OpenFilex.open(path);
    }
  }

  List<LibrarySearchResult> get _results => searchLibrary(
    query: _search.text,
    items: _items,
    kind: _kind,
  );

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Библиотека',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Импортировать файлы',
            onPressed: _importing ? null : _importFiles,
            icon: const Icon(Icons.add_to_drive_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Искать музыку, кино, фото, документы…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _KindChip(
                  label: 'Все',
                  icon: Icons.apps_rounded,
                  selected: _kind == null,
                  onTap: () => setState(() => _kind = null),
                ),
                _KindChip(
                  label: 'Музыка',
                  icon: Icons.library_music_rounded,
                  selected: _kind == LibraryKinds.audio,
                  onTap: () => setState(() => _kind = LibraryKinds.audio),
                ),
                _KindChip(
                  label: 'Видео',
                  icon: Icons.movie_outlined,
                  selected: _kind == LibraryKinds.video,
                  onTap: () => setState(() => _kind = LibraryKinds.video),
                ),
                _KindChip(
                  label: 'Фото',
                  icon: Icons.photo_library_outlined,
                  selected: _kind == LibraryKinds.image,
                  onTap: () => setState(() => _kind = LibraryKinds.image),
                ),
                _KindChip(
                  label: 'Документы',
                  icon: Icons.description_outlined,
                  selected: _kind == LibraryKinds.document,
                  onTap: () => setState(() => _kind = LibraryKinds.document),
                ),
                _KindChip(
                  label: 'Архивы',
                  icon: Icons.inventory_2_outlined,
                  selected: _kind == LibraryKinds.archive,
                  onTap: () => setState(() => _kind = LibraryKinds.archive),
                ),
                _KindChip(
                  label: 'Голос',
                  icon: Icons.graphic_eq_rounded,
                  selected: _kind == LibraryKinds.voice,
                  onTap: () => setState(() => _kind = LibraryKinds.voice),
                ),
                _KindChip(
                  label: 'Кружки',
                  icon: Icons.circle_outlined,
                  selected: _kind == LibraryKinds.circle,
                  onTap: () => setState(() => _kind = LibraryKinds.circle),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                Text(
                  '${results.length} объектов',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_importing)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : results.isEmpty
                ? _LibraryEmpty(
                    filtered: _search.text.isNotEmpty || _kind != null,
                    onImport: _importFiles,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index].item;
                        return _LibraryTile(
                          item: item,
                          onOpen: () => _open(item),
                          onRoom: item.roomId == null
                              ? null
                              : () {
                                  final room = widget.rooms
                                      .where((value) => value.id == item.roomId)
                                      .firstOrNull;
                                  if (room != null) widget.onOpenRoom(room);
                                },
                          onRemove: () => _remove(item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _KindChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}

class _LibraryTile extends StatelessWidget {
  final LibraryItem item;
  final VoidCallback onOpen;
  final VoidCallback? onRoom;
  final VoidCallback onRemove;

  const _LibraryTile({
    required this.item,
    required this.onOpen,
    required this.onRoom,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
        leading: _LibraryThumb(item: item),
        title: Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                item.available ? Icons.circle : Icons.cloud_off_rounded,
                size: item.available ? 8 : 14,
                color: item.available
                    ? const Color(0xFF42D3A7)
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${_kindLabel(item.kind)} • ${_formatBytes(item.size)} • ${item.ownerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'room') onRoom?.call();
            if (value == 'remove') onRemove();
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            if (onRoom != null)
              const PopupMenuItem(
                value: 'room',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.forum_outlined),
                  title: Text('Открыть комнату'),
                ),
              ),
            const PopupMenuItem(
              value: 'remove',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.remove_circle_outline_rounded),
                title: Text('Убрать из библиотеки'),
              ),
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _LibraryThumb extends StatelessWidget {
  final LibraryItem item;

  const _LibraryThumb({required this.item});

  @override
  Widget build(BuildContext context) {
    final path = item.localPath;
    if (item.kind == LibraryKinds.image && path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.file(
          File(path),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          cacheWidth: 160,
        ),
      );
    }
    final icon = switch (item.kind) {
      LibraryKinds.audio => Icons.music_note_rounded,
      LibraryKinds.video => Icons.movie_rounded,
      LibraryKinds.image => Icons.image_rounded,
      LibraryKinds.document => Icons.description_rounded,
      LibraryKinds.archive => Icons.inventory_2_rounded,
      LibraryKinds.voice => Icons.graphic_eq_rounded,
      LibraryKinds.circle => Icons.circle_rounded,
      LibraryKinds.link => Icons.link_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF6958D7), Color(0xFF267EAF)],
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _LibraryEmpty extends StatelessWidget {
  final bool filtered;
  final Future<void> Function() onImport;

  const _LibraryEmpty({required this.filtered, required this.onImport});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 82),
          const SizedBox(height: 14),
          Text(
            filtered ? 'Ничего не найдено' : 'Библиотека пока пустая',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            filtered
                ? 'Измени запрос или категорию.'
                : 'Импортируй файлы или отправь вложение в комнате — оно появится здесь автоматически.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!filtered) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить файлы'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ImageViewer extends StatelessWidget {
  final LibraryItem item;

  const _ImageViewer({required this.item});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.file(File(item.localPath!), fit: BoxFit.contain),
      ),
    ),
  );
}

class LibraryAudioPlayer extends StatefulWidget {
  final List<LibraryItem> items;
  final int initialIndex;

  const LibraryAudioPlayer({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<LibraryAudioPlayer> createState() => _LibraryAudioPlayerState();
}

class _LibraryAudioPlayerState extends State<LibraryAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  late int _index = widget.initialIndex.clamp(0, max(0, widget.items.length - 1));
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _speed = 1;
  bool _loading = true;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;

  LibraryItem get _item => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _durationSubscription = _player.durationStream.listen((value) {
      if (mounted) setState(() => _duration = value ?? Duration.zero);
    });
    _positionSubscription = _player.positionStream.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) unawaited(_next());
      if (mounted) setState(() {});
    });
    unawaited(_loadCurrent(autoplay: true));
  }

  Future<void> _loadCurrent({bool autoplay = false}) async {
    setState(() {
      _loading = true;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.setFilePath(_item.localPath!);
    await _player.setSpeed(_speed);
    if (autoplay) await _player.play();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _next() async {
    if (widget.items.isEmpty) return;
    _index = (_index + 1) % widget.items.length;
    await _loadCurrent(autoplay: true);
  }

  Future<void> _previous() async {
    if (widget.items.isEmpty) return;
    _index = (_index - 1 + widget.items.length) % widget.items.length;
    await _loadCurrent(autoplay: true);
  }

  @override
  Widget build(BuildContext context) {
    final playing = _player.playing;
    final maxMs = max(1, _duration.inMilliseconds);
    final value = _position.inMilliseconds.clamp(0, maxMs).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Аудиоплеер')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: min(MediaQuery.sizeOf(context).width - 70, 320),
                height: min(MediaQuery.sizeOf(context).width - 70, 320),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(42),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF6D55D9), Color(0xFF163E66)],
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x553A67FF), blurRadius: 42),
                  ],
                ),
                child: const Center(child: ChernogramLogo(size: 150)),
              ),
              const SizedBox(height: 28),
              Text(
                _item.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                _item.artist ?? _item.ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Slider(
                value: value,
                max: maxMs.toDouble(),
                onChanged: _loading
                    ? null
                    : (next) => _player.seek(Duration(milliseconds: next.round())),
              ),
              Row(
                children: [
                  Text(_formatDuration(_position)),
                  const Spacer(),
                  Text(_formatDuration(_duration)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 34,
                    onPressed: _previous,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    iconSize: 38,
                    onPressed: _loading
                        ? null
                        : () async {
                            if (playing) {
                              await _player.pause();
                            } else {
                              await _player.play();
                            }
                          },
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    iconSize: 34,
                    onPressed: _next,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SegmentedButton<double>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<double>>[
                  ButtonSegment(value: .75, label: Text('0.75×')),
                  ButtonSegment(value: 1, label: Text('1×')),
                  ButtonSegment(value: 1.25, label: Text('1.25×')),
                  ButtonSegment(value: 1.5, label: Text('1.5×')),
                ],
                selected: <double>{_speed},
                onSelectionChanged: (value) async {
                  _speed = value.first;
                  await _player.setSpeed(_speed);
                  if (mounted) setState(() {});
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}

class LibraryVideoPlayer extends StatefulWidget {
  final LibraryItem item;
  final bool circular;

  const LibraryVideoPlayer({
    super.key,
    required this.item,
    this.circular = false,
  });

  @override
  State<LibraryVideoPlayer> createState() => _LibraryVideoPlayerState();
}

class _LibraryVideoPlayerState extends State<LibraryVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.file(File(widget.item.localPath!));
    await controller.initialize();
    await controller.setLooping(widget.circular);
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _ready = true;
    });
    await controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: !_ready || controller == null
            ? const CircularProgressIndicator()
            : GestureDetector(
                onTap: () async {
                  if (controller.value.isPlaying) {
                    await controller.pause();
                  } else {
                    await controller.play();
                  }
                  if (mounted) setState(() {});
                },
                child: widget.circular
                    ? SizedBox.square(
                        dimension: min(MediaQuery.sizeOf(context).width - 44, 420),
                        child: ClipOval(child: _video(controller)),
                      )
                    : AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: _video(controller),
                      ),
              ),
      ),
      bottomNavigationBar: !_ready || controller == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Color(0xFF8C7BFF)),
                ),
              ),
            ),
    );
  }

  Widget _video(VideoPlayerController controller) => Stack(
    fit: StackFit.expand,
    children: [
      FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
      if (!controller.value.isPlaying)
        const Center(
          child: CircleAvatar(
            radius: 34,
            backgroundColor: Colors.black54,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 42),
          ),
        ),
    ],
  );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

String _kindLabel(String kind) => switch (kind) {
  LibraryKinds.audio => 'Музыка',
  LibraryKinds.video => 'Видео',
  LibraryKinds.image => 'Фото',
  LibraryKinds.document => 'Документ',
  LibraryKinds.archive => 'Архив',
  LibraryKinds.voice => 'Голосовое',
  LibraryKinds.circle => 'Кружок',
  LibraryKinds.link => 'Ссылка',
  _ => 'Файл',
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
