import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'core_models.dart';
import 'shared_library.dart';

class CgMusicTrack {
  final String id;
  final String title;
  final String subtitle;
  final String path;
  final String source;

  const CgMusicTrack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.source,
  });
}

class CgMusicHub {
  CgMusicHub._();

  static final CgMusicHub instance = CgMusicHub._();

  static const String _queueKey = 'cg_music_queue_v2';
  static const String _activePathKey = 'cg_music_active_path_v2';
  static const String _positionKey = 'cg_music_position_ms_v2';
  static const String _loopKey = 'cg_music_loop_v2';
  static const String _shuffleKey = 'cg_music_shuffle_v2';

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<List<CgMusicTrack>> queue =
      ValueNotifier<List<CgMusicTrack>>(const <CgMusicTrack>[]);
  final ValueNotifier<String?> activeTrackId = ValueNotifier<String?>(null);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier<LoopMode>(LoopMode.off);
  final ValueNotifier<bool> shuffleEnabled = ValueNotifier<bool>(false);

  StreamSubscription<int?>? _indexSubscription;
  Timer? _persistenceTimer;
  bool _restoreAttempted = false;

  CgMusicTrack? get activeTrack {
    final current = queue.value;
    final index = player.currentIndex;
    if (index == null || index < 0 || index >= current.length) return null;
    return current[index];
  }

  Future<void> playQueue(
    List<CgMusicTrack> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    final existing = queue.value;
    final sameQueue = existing.length == tracks.length &&
        List<int>.generate(tracks.length, (index) => index)
            .every((index) => existing[index].path == tracks[index].path);
    final safeIndex = initialIndex.clamp(0, tracks.length - 1).toInt();
    if (!sameQueue) {
      queue.value = List<CgMusicTrack>.unmodifiable(tracks);
      await _indexSubscription?.cancel();
      _indexSubscription = player.currentIndexStream.listen((index) {
        final current = queue.value;
        if (index == null || index < 0 || index >= current.length) return;
        activeTrackId.value = current[index].id;
        unawaited(_persistState());
      });
      final sources = tracks
          .map(
            (track) => AudioSource.uri(
              Uri.file(track.path),
              tag: MediaItem(
                id: track.id,
                album: track.subtitle,
                title: track.title,
                extras: <String, dynamic>{
                  'path': track.path,
                  'source': track.source,
                },
              ),
            ),
          )
          .toList(growable: false);
      await player.setAudioSources(
        sources,
        initialIndex: safeIndex,
        initialPosition: initialPosition,
      );
    } else {
      await player.seek(initialPosition, index: safeIndex);
    }
    activeTrackId.value = tracks[safeIndex].id;
    _startPersistenceTimer();
    await _persistState();
    if (autoPlay) {
      await player.play();
    } else {
      await player.pause();
    }
  }

  Future<void> playSingle(CgMusicTrack track) async {
    if (activeTrackId.value == track.id && player.audioSource != null) {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      await _persistState();
      return;
    }
    await playQueue(<CgMusicTrack>[track]);
  }

  Future<void> playFile({
    required String id,
    required String title,
    required String subtitle,
    required String path,
    String source = 'chat',
  }) =>
      playSingle(
        CgMusicTrack(
          id: id,
          title: title,
          subtitle: subtitle,
          path: path,
          source: source,
        ),
      );

  Future<void> next() async {
    if (player.hasNext) {
      await player.seekToNext();
    } else if (loopMode.value == LoopMode.all && queue.value.isNotEmpty) {
      await player.seek(Duration.zero, index: 0);
    }
    await _persistState();
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 4)) {
      await player.seek(Duration.zero);
    } else if (player.hasPrevious) {
      await player.seekToPrevious();
    }
    await _persistState();
  }

  Future<void> cycleLoopMode() async {
    final next = switch (loopMode.value) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    loopMode.value = next;
    await player.setLoopMode(next);
    await _persistState();
  }

  Future<void> toggleShuffle() async {
    final enabled = !shuffleEnabled.value;
    shuffleEnabled.value = enabled;
    if (enabled) await player.shuffle();
    await player.setShuffleModeEnabled(enabled);
    await _persistState();
  }

  Future<void> restoreFromTracks(List<CgMusicTrack> available) async {
    if (_restoreAttempted || available.isEmpty || queue.value.isNotEmpty) return;
    _restoreAttempted = true;
    final prefs = await SharedPreferences.getInstance();
    final rawQueue = prefs.getString(_queueKey);
    final savedPaths = <String>[];
    if (rawQueue != null && rawQueue.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawQueue);
        if (decoded is List) {
          savedPaths.addAll(
            decoded.map((item) => item.toString()).where((item) => item.isNotEmpty),
          );
        }
      } catch (_) {}
    }
    final byPath = <String, CgMusicTrack>{
      for (final track in available) track.path: track,
    };
    final restoredQueue = savedPaths
        .map((path) => byPath[path])
        .whereType<CgMusicTrack>()
        .toList(growable: false);
    final activePath = prefs.getString(_activePathKey) ?? '';
    final fallback = byPath[activePath];
    final tracks = restoredQueue.isNotEmpty
        ? restoredQueue
        : fallback == null
            ? const <CgMusicTrack>[]
            : <CgMusicTrack>[fallback];
    if (tracks.isEmpty) return;

    final index = math.max(
      0,
      tracks.indexWhere((track) => track.path == activePath),
    );
    final position = Duration(milliseconds: prefs.getInt(_positionKey) ?? 0);
    final loopName = prefs.getString(_loopKey) ?? LoopMode.off.name;
    final loop = LoopMode.values.firstWhere(
      (value) => value.name == loopName,
      orElse: () => LoopMode.off,
    );
    final shuffle = prefs.getBool(_shuffleKey) == true;
    loopMode.value = loop;
    shuffleEnabled.value = shuffle;
    await player.setLoopMode(loop);
    await player.setShuffleModeEnabled(shuffle);
    await playQueue(
      tracks,
      initialIndex: index,
      initialPosition: position,
      autoPlay: false,
    );
  }

  Future<void> stopAndClear() async {
    await player.stop();
    queue.value = const <CgMusicTrack>[];
    activeTrackId.value = null;
    _persistenceTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait<void>(<Future<void>>[
      prefs.remove(_queueKey),
      prefs.remove(_activePathKey),
      prefs.remove(_positionKey),
    ]);
  }

  void _startPersistenceTimer() {
    _persistenceTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (queue.value.isNotEmpty) unawaited(_persistState());
    });
  }

  Future<void> _persistState() async {
    final tracks = queue.value;
    if (tracks.isEmpty) return;
    final index = (player.currentIndex ?? 0).clamp(0, tracks.length - 1).toInt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _queueKey,
      jsonEncode(tracks.map((track) => track.path).toList(growable: false)),
    );
    await prefs.setString(_activePathKey, tracks[index].path);
    await prefs.setInt(_positionKey, player.position.inMilliseconds);
    await prefs.setString(_loopKey, loopMode.value.name);
    await prefs.setBool(_shuffleKey, shuffleEnabled.value);
  }
}

class CgPlayingBars extends StatefulWidget {
  final bool active;
  final double size;

  const CgPlayingBars({super.key, required this.active, this.size = 24});

  @override
  State<CgPlayingBars> createState() => _CgPlayingBarsState();
}

class _CgPlayingBarsState extends State<CgPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant CgPlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final value = widget.active ? _controller.value : .20;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(7, (index) {
                final phase = (value + index * .16) % 1.0;
                final arch = 1 - ((index - 3).abs() / 4);
                final motion = .45 + .55 * (1 - (phase - .5).abs() * 2);
                final height = widget.size * (.25 + .65 * arch * motion);
                return Container(
                  width: widget.size * .075,
                  height: math.max(widget.size * .20, height),
                  margin: EdgeInsets.symmetric(horizontal: widget.size * .025),
                  decoration: BoxDecoration(
                    color: index == 2 || index == 4
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            );
          },
        ),
      );
}

class CgMusicPlayerScreen extends StatefulWidget {
  final bool ru;
  final List<CgTunnel> tunnels;

  const CgMusicPlayerScreen({
    super.key,
    required this.ru,
    required this.tunnels,
  });

  @override
  State<CgMusicPlayerScreen> createState() => _CgMusicPlayerScreenState();
}

class _CgMusicPlayerScreenState extends State<CgMusicPlayerScreen> {
  final TextEditingController _search = TextEditingController();
  final CgMusicHub _hub = CgMusicHub.instance;
  List<CgMusicTrack> _tracks = const <CgMusicTrack>[];
  List<String> _folders = const <String>[];
  bool _loading = true;
  String? _permissionError;
  String _sourceFilter = 'all';

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<List<CgMusicTrack>> _chatTracks() async {
    final tracks = <CgMusicTrack>[];
    for (final tunnel in widget.tunnels) {
      for (final message in tunnel.messages) {
        final attachment = message.attachment;
        if (message.deleted ||
            attachment == null ||
            attachment.kind != 'audio' ||
            message.meta['localPurged'] == true) {
          continue;
        }
        final path = attachment.localPath;
        if (path == null || path.isEmpty) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        tracks.add(
          CgMusicTrack(
            id: 'chat:${tunnel.id}:${attachment.id}',
            title: attachment.name,
            subtitle: tunnel.displayName,
            path: file.path,
            source: 'chat',
          ),
        );
      }
    }
    return tracks;
  }

  Future<List<CgMusicTrack>> _deviceTracks() async {
    if (!Platform.isAndroid) return const <CgMusicTrack>[];
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      _permissionError = widget.ru
          ? 'Разрешите доступ к музыке на устройстве.'
          : 'Allow access to music on this device.';
      return const <CgMusicTrack>[];
    }
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.audio,
      onlyAll: true,
    );
    if (paths.isEmpty) return const <CgMusicTrack>[];
    final assets = await paths.first.getAssetListPaged(page: 0, size: 2000);
    final tracks = <CgMusicTrack>[];
    for (final asset in assets) {
      try {
        final file = await asset.file;
        if (file == null || !await file.exists()) continue;
        final title = (await asset.titleAsync).trim();
        tracks.add(
          CgMusicTrack(
            id: 'device:${asset.id}',
            title: title.isEmpty
                ? file.path.split(Platform.pathSeparator).last
                : title,
            subtitle: widget.ru ? 'На устройстве' : 'On device',
            path: file.path,
            source: 'device',
          ),
        );
      } catch (_) {}
    }
    return tracks;
  }

  Future<List<CgMusicTrack>> _folderTracks() async {
    final files = await CgSharedLibraryStore.scanMusicFolders();
    return files
        .map(
          (file) => CgMusicTrack(
            id: 'folder:${file.path}',
            title: file.path.split(Platform.pathSeparator).last,
            subtitle: file.parent.path,
            path: file.path,
            source: 'folder',
          ),
        )
        .toList();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    _permissionError = null;
    _folders = await CgSharedLibraryStore.loadMusicFolders();
    final chat = await _chatTracks();
    final device = await _deviceTracks();
    final folders = await _folderTracks();
    final unique = <String, CgMusicTrack>{};
    for (final track in <CgMusicTrack>[...chat, ...device, ...folders]) {
      unique[track.path] = track;
    }
    final tracks = unique.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await _hub.restoreFromTracks(tracks);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  Future<void> _addFolder() async {
    _folders = await CgSharedLibraryStore.addMusicFolder();
    await _load();
  }

  Future<void> _removeFolder(String path) async {
    await CgSharedLibraryStore.removeMusicFolder(path);
    await _load();
  }

  List<CgMusicTrack> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _tracks.where((track) {
      if (_sourceFilter != 'all' && track.source != _sourceFilter) return false;
      if (query.isEmpty) return true;
      return track.title.toLowerCase().contains(query) ||
          track.subtitle.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _play(CgMusicTrack track) async {
    final visible = _visible;
    final index = visible.indexWhere((item) => item.id == track.id);
    await _hub.playQueue(visible, initialIndex: math.max(0, index));
    if (mounted) setState(() {});
  }

  String _sourceLabel(String source) => switch (source) {
        'device' => widget.ru ? 'Устройство' : 'Device',
        'chat' => widget.ru ? 'Чаты' : 'Chats',
        'folder' => widget.ru ? 'Папки' : 'Folders',
        _ => widget.ru ? 'Все' : 'All',
      };

  IconData _sourceIcon(String source) => switch (source) {
        'device' => Icons.smartphone_rounded,
        'chat' => Icons.forum_outlined,
        'folder' => Icons.folder_outlined,
        _ => Icons.library_music_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Музыка' : 'Music'),
        actions: [
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            IconButton(
              tooltip: widget.ru ? 'Добавить папку' : 'Add folder',
              onPressed: _addFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          IconButton(
            tooltip: widget.ru ? 'Обновить' : 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: widget.ru
                    ? 'Поиск по названию, чату или папке'
                    : 'Search title, chat or folder',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: const <String>['all', 'device', 'chat', 'folder'].length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final source = const <String>[
                  'all',
                  'device',
                  'chat',
                  'folder',
                ][index];
                return FilterChip(
                  selected: _sourceFilter == source,
                  avatar: Icon(_sourceIcon(source), size: 17),
                  label: Text(_sourceLabel(source)),
                  onSelected: (_) => setState(() => _sourceFilter = source),
                );
              },
            ),
          ),
          if (_folders.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _folders.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  return InputChip(
                    avatar: const Icon(Icons.folder_outlined, size: 17),
                    label: Text(
                      folder.split(Platform.pathSeparator).last,
                      maxLines: 1,
                    ),
                    onDeleted: () => _removeFolder(folder),
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.library_music_outlined,
                                size: 66,
                                color: scheme.onSurface.withValues(alpha: .18),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _permissionError ??
                                    (widget.ru
                                        ? 'Музыка пока не найдена'
                                        : 'No music found'),
                                textAlign: TextAlign.center,
                              ),
                              if (Platform.isWindows) ...[
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: _addFolder,
                                  icon: const Icon(Icons.folder_open_rounded),
                                  label: Text(
                                    widget.ru
                                        ? 'Добавить папку с музыкой'
                                        : 'Add music folder',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ValueListenableBuilder<String?>(
                        valueListenable: _hub.activeTrackId,
                        builder: (context, activeId, _) => ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 174),
                          itemCount: _visible.length,
                          itemBuilder: (context, index) {
                            final track = _visible[index];
                            final active = activeId == track.id;
                            return Material(
                              color: active
                                  ? scheme.primary.withValues(alpha: .11)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                onTap: () => _play(track),
                                leading: StreamBuilder<PlayerState>(
                                  stream: _hub.player.playerStateStream,
                                  builder: (context, state) => SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: Center(
                                      child: active
                                          ? CgPlayingBars(
                                              active: state.data?.playing == true,
                                              size: 30,
                                            )
                                          : Icon(
                                              _sourceIcon(track.source),
                                              color: scheme.primary,
                                            ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_sourceLabel(track.source)} • ${track.subtitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Icon(
                                  active
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 32,
                                  color: scheme.primary,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      bottomSheet: _MusicNowPlaying(ru: widget.ru),
    );
  }
}

class _MusicNowPlaying extends StatefulWidget {
  final bool ru;

  const _MusicNowPlaying({required this.ru});

  @override
  State<_MusicNowPlaying> createState() => _MusicNowPlayingState();
}

class _MusicNowPlayingState extends State<_MusicNowPlaying> {
  bool _showRemaining = false;

  String _format(Duration value) {
    final totalSeconds = math.max(0, value.inSeconds);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hub = CgMusicHub.instance;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<CgMusicTrack>>(
      valueListenable: hub.queue,
      builder: (context, queue, _) {
        if (queue.isEmpty) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .22),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: StreamBuilder<int?>(
              stream: hub.player.currentIndexStream,
              builder: (context, indexSnapshot) {
                final index = (indexSnapshot.data ?? 0)
                    .clamp(0, queue.length - 1)
                    .toInt();
                final track = queue[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        StreamBuilder<PlayerState>(
                          stream: hub.player.playerStateStream,
                          builder: (context, state) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: CgPlayingBars(
                              active: state.data?.playing == true,
                              size: 38,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                track.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: hub.previous,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        StreamBuilder<PlayerState>(
                          stream: hub.player.playerStateStream,
                          builder: (context, state) => IconButton.filled(
                            onPressed: () => state.data?.playing == true
                                ? hub.player.pause()
                                : hub.player.play(),
                            icon: Icon(
                              state.data?.playing == true
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: hub.next,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        IconButton(
                          tooltip: widget.ru ? 'Закрыть плеер' : 'Close player',
                          onPressed: hub.stopAndClear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    StreamBuilder<Duration>(
                      stream: hub.player.positionStream,
                      builder: (context, positionSnapshot) =>
                          StreamBuilder<Duration?>(
                        stream: hub.player.durationStream,
                        builder: (context, durationSnapshot) {
                          final total = durationSnapshot.data ?? Duration.zero;
                          final position = positionSnapshot.data ?? Duration.zero;
                          final maxValue =
                              math.max(1, total.inMilliseconds).toDouble();
                          final remaining = total - position;
                          return Column(
                            children: [
                              Slider(
                                min: 0,
                                max: maxValue,
                                value: position.inMilliseconds
                                    .clamp(0, maxValue.toInt())
                                    .toDouble(),
                                onChanged: total == Duration.zero
                                    ? null
                                    : (value) => hub.player.seek(
                                          Duration(milliseconds: value.round()),
                                        ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                                child: Row(
                                  children: [
                                    Text(
                                      _format(position),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    const Spacer(),
                                    ValueListenableBuilder<bool>(
                                      valueListenable: hub.shuffleEnabled,
                                      builder: (context, enabled, _) => IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: widget.ru
                                            ? 'Случайный порядок'
                                            : 'Shuffle',
                                        onPressed: hub.toggleShuffle,
                                        color: enabled ? scheme.primary : null,
                                        icon: const Icon(Icons.shuffle_rounded),
                                      ),
                                    ),
                                    ValueListenableBuilder<LoopMode>(
                                      valueListenable: hub.loopMode,
                                      builder: (context, mode, _) => IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: widget.ru
                                            ? 'Режим повтора'
                                            : 'Repeat mode',
                                        onPressed: hub.cycleLoopMode,
                                        color: mode != LoopMode.off
                                            ? scheme.primary
                                            : null,
                                        icon: Icon(
                                          mode == LoopMode.one
                                              ? Icons.repeat_one_rounded
                                              : Icons.repeat_rounded,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => setState(
                                        () => _showRemaining = !_showRemaining,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        child: Text(
                                          _showRemaining
                                              ? '-${_format(remaining.isNegative ? Duration.zero : remaining)}'
                                              : _format(total),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
