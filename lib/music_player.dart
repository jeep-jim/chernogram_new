import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import 'brand.dart';
import 'core_models.dart';
import 'music_library.dart';
import 'shared_library.dart';

class CgMusicHub {
  CgMusicHub._();

  static final CgMusicHub instance = CgMusicHub._();

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<List<CgMusicTrack>> queue =
      ValueNotifier<List<CgMusicTrack>>(const <CgMusicTrack>[]);
  final ValueNotifier<String?> activeTrackId = ValueNotifier<String?>(null);
  final ValueNotifier<bool> shuffleEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier<LoopMode>(
    LoopMode.off,
  );

  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<LoopMode>? _loopSubscription;
  StreamSubscription<bool>? _shuffleSubscription;
  Timer? _persistTimer;
  bool _initialized = false;
  bool _restoring = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _wireStreams();
    final snapshot = await CgMusicLibraryStore.loadPlayerSnapshot();
    if (snapshot == null || snapshot.queue.isEmpty) return;
    final available = <CgMusicTrack>[];
    for (final track in snapshot.queue) {
      final file = File(track.path);
      if (await file.exists()) available.add(track);
    }
    if (available.isEmpty) {
      await CgMusicLibraryStore.clearPlayerSnapshot();
      return;
    }
    _restoring = true;
    try {
      queue.value = List<CgMusicTrack>.unmodifiable(available);
      final safeIndex = snapshot.index.clamp(0, available.length - 1).toInt();
      await player.setAudioSources(
        _sources(available),
        initialIndex: safeIndex,
        initialPosition: snapshot.position,
      );
      final restoredLoop = _parseLoop(snapshot.loopMode);
      await player.setLoopMode(restoredLoop);
      if (snapshot.shuffle) {
        await player.shuffle();
        await player.setShuffleModeEnabled(true);
      }
      loopMode.value = restoredLoop;
      shuffleEnabled.value = snapshot.shuffle;
      activeTrackId.value = available[safeIndex].id;
    } finally {
      _restoring = false;
    }
  }

  void _wireStreams() {
    _indexSubscription ??= player.currentIndexStream.listen((index) {
      final current = queue.value;
      if (index == null || index < 0 || index >= current.length) return;
      activeTrackId.value = current[index].id;
      _schedulePersist();
    });
    _positionSubscription ??= player.positionStream.listen((_) {
      _schedulePersist();
    });
    _loopSubscription ??= player.loopModeStream.listen((mode) {
      loopMode.value = mode;
      _schedulePersist();
    });
    _shuffleSubscription ??= player.shuffleModeEnabledStream.listen((enabled) {
      shuffleEnabled.value = enabled;
      _schedulePersist();
    });
  }

  List<AudioSource> _sources(List<CgMusicTrack> tracks) => tracks
      .map(
        (track) => AudioSource.uri(
          Uri.file(track.path),
          tag: MediaItem(
            id: track.id,
            album: track.subtitle,
            artist: track.author.isEmpty ? null : track.author,
            title: track.title,
            extras: <String, dynamic>{
              'source': track.source.name,
              'path': track.path,
            },
          ),
        ),
      )
      .toList();

  Future<void> playQueue(
    List<CgMusicTrack> tracks, {
    int initialIndex = 0,
  }) async {
    await initialize();
    if (tracks.isEmpty) return;
    final existing = queue.value;
    final sameQueue =
        existing.length == tracks.length &&
        List<int>.generate(
          tracks.length,
          (index) => index,
        ).every((index) => existing[index].path == tracks[index].path);
    final safeIndex = initialIndex.clamp(0, tracks.length - 1).toInt();
    if (!sameQueue) {
      queue.value = List<CgMusicTrack>.unmodifiable(tracks);
      await player.setAudioSources(_sources(tracks), initialIndex: safeIndex);
      if (shuffleEnabled.value) await player.shuffle();
    } else {
      await player.seek(Duration.zero, index: safeIndex);
    }
    activeTrackId.value = tracks[safeIndex].id;
    await player.play();
    await _persistNow();
  }

  Future<void> playSingle(CgMusicTrack track) async {
    await initialize();
    if (activeTrackId.value == track.id && player.audioSource != null) {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }
    await playQueue(<CgMusicTrack>[track]);
  }

  Future<void> playFile({
    required String id,
    required String title,
    required String subtitle,
    required String path,
  }) => playSingle(
    CgMusicTrack(
      id: id,
      title: title,
      subtitle: subtitle,
      path: path,
      source: CgMusicSource.chats,
      addedAt: DateTime.now().toUtc(),
    ),
  );

  Future<void> next() async {
    await initialize();
    if (player.hasNext) await player.seekToNext();
  }

  Future<void> previous() async {
    await initialize();
    if (player.position > const Duration(seconds: 4)) {
      await player.seek(Duration.zero);
    } else if (player.hasPrevious) {
      await player.seekToPrevious();
    }
  }

  Future<void> toggleShuffle() async {
    await initialize();
    final next = !player.shuffleModeEnabled;
    if (next) await player.shuffle();
    await player.setShuffleModeEnabled(next);
    await _persistNow();
  }

  Future<void> cycleLoopMode() async {
    await initialize();
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    await _persistNow();
  }

  Future<void> stopAndClear() async {
    _persistTimer?.cancel();
    await player.stop();
    await player.setAudioSource(
      AudioSource.asset('assets/audio/chernogram_incoming.mp3'),
    );
    await player.stop();
    queue.value = const <CgMusicTrack>[];
    activeTrackId.value = null;
    shuffleEnabled.value = false;
    loopMode.value = LoopMode.off;
    await player.setShuffleModeEnabled(false);
    await player.setLoopMode(LoopMode.off);
    await CgMusicLibraryStore.clearPlayerSnapshot();
  }

  void _schedulePersist() {
    if (_restoring || queue.value.isEmpty) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), _persistNow);
  }

  Future<void> _persistNow() async {
    if (_restoring || queue.value.isEmpty) return;
    final index = (player.currentIndex ?? 0)
        .clamp(0, queue.value.length - 1)
        .toInt();
    await CgMusicLibraryStore.savePlayerSnapshot(
      CgPlayerSnapshot(
        queue: queue.value,
        index: index,
        position: player.position,
        loopMode: player.loopMode.name,
        shuffle: player.shuffleModeEnabled,
      ),
    );
  }

  LoopMode _parseLoop(String value) => switch (value) {
    'one' => LoopMode.one,
    'all' => LoopMode.all,
    _ => LoopMode.off,
  };
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
  List<CgPlaylist> _playlists = const <CgPlaylist>[];
  CgMusicSource _source = CgMusicSource.device;
  String? _playlistId;
  bool _globalSearch = true;
  bool _loading = true;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    unawaited(_hub.initialize());
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
        final voice =
            message.type == 'voice' ||
            message.type == 'voice_note' ||
            message.meta['voice'] == true ||
            message.meta['voiceNote'] == true ||
            message.meta['circle'] == true;
        if (voice ||
            message.deleted ||
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
            source: CgMusicSource.chats,
            author: message.authorName,
            permissions: const CgMediaPermissions(
              canDownload: true,
              canShare: true,
              canSave: true,
            ),
            addedAt: message.sentAt.toUtc(),
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
    final assets = await paths.first.getAssetListPaged(page: 0, size: 3000);
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
            source: CgMusicSource.device,
            addedAt: asset.createDateSecond == null
                ? DateTime.now().toUtc()
                : DateTime.fromMillisecondsSinceEpoch(
                    asset.createDateSecond! * 1000,
                  ).toUtc(),
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
            source: CgMusicSource.folders,
            addedAt: DateTime.now().toUtc(),
          ),
        )
        .toList();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    _folders = await CgSharedLibraryStore.loadMusicFolders();
    final values = await Future.wait<List<CgMusicTrack>>([
      _chatTracks(),
      _deviceTracks(),
      _folderTracks(),
      CgMusicLibraryStore.loadSaved(),
      CgMusicLibraryStore.loadPublished(),
    ]);
    _playlists = await CgMusicLibraryStore.loadPlaylists();
    final unique = <String, CgMusicTrack>{};
    for (final track in values.expand((item) => item)) {
      final key = '${track.source.name}:${track.path}';
      unique[key] = track;
    }
    final tracks = unique.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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
    Iterable<CgMusicTrack> result = _tracks;
    if (_playlistId != null) {
      final playlist = _playlists
          .where((item) => item.id == _playlistId)
          .firstOrNull;
      final ids = playlist?.trackIds.toSet() ?? <String>{};
      result = result.where((track) => ids.contains(track.id));
    } else if (query.isEmpty || !_globalSearch) {
      result = result.where((track) => track.source == _source);
    }
    if (query.isNotEmpty) {
      result = result.where(
        (track) =>
            track.title.toLowerCase().contains(query) ||
            track.subtitle.toLowerCase().contains(query) ||
            track.author.toLowerCase().contains(query),
      );
    }
    return result.toList();
  }

  Future<void> _play(CgMusicTrack track) async {
    final visible = _visible.where((item) => item.permissions.canPlay).toList();
    final index = visible.indexWhere((item) => item.id == track.id);
    await _hub.playQueue(visible, initialIndex: math.max(0, index));
    if (mounted) setState(() {});
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Новый плейлист' : 'New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.ru ? 'Название' : 'Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(widget.ru ? 'Создать' : 'Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final playlist = await CgMusicLibraryStore.createPlaylist(name);
    _playlists = await CgMusicLibraryStore.loadPlaylists();
    if (mounted) setState(() => _playlistId = playlist.id);
  }

  Future<void> _addToPlaylist(CgMusicTrack track) async {
    if (_playlists.isEmpty) {
      await _createPlaylist();
      if (_playlistId == null) return;
      await CgMusicLibraryStore.addToPlaylist(_playlistId!, track.id);
      _playlists = await CgMusicLibraryStore.loadPlaylists();
      if (mounted) setState(() {});
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(widget.ru ? 'Новый плейлист' : 'New playlist'),
              onTap: () => Navigator.pop(context, '__new__'),
            ),
            ..._playlists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                subtitle: Text('${playlist.trackIds.length}'),
                onTap: () => Navigator.pop(context, playlist.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (id == null) return;
    if (id == '__new__') {
      await _createPlaylist();
      return;
    }
    await CgMusicLibraryStore.addToPlaylist(id, track.id);
    _playlists = await CgMusicLibraryStore.loadPlaylists();
    if (mounted) setState(() {});
  }

  Future<void> _publish(CgMusicTrack track) async {
    var canDownload = true;
    var canShare = true;
    var canSave = true;
    final permissions = await showModalBottomSheet<CgMediaPermissions>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.ru ? 'Опубликовать трек' : 'Publish track',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.ru
                      ? 'Трек появится в публичном каталоге Cernogram. Вы управляете разрешениями.'
                      : 'The track will appear in the Cernogram public catalog. You control permissions.',
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.ru ? 'Разрешить скачивание' : 'Allow download',
                  ),
                  value: canDownload,
                  onChanged: (value) =>
                      setSheetState(() => canDownload = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.ru ? 'Разрешить делиться' : 'Allow sharing',
                  ),
                  value: canShare,
                  onChanged: (value) => setSheetState(() => canShare = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.ru
                        ? 'Разрешить «Добавить к себе»'
                        : 'Allow save to library',
                  ),
                  value: canSave,
                  onChanged: (value) => setSheetState(() => canSave = value),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      CgMediaPermissions(
                        canDownload: canDownload,
                        canShare: canShare,
                        canSave: canSave,
                        canIndex: true,
                      ),
                    ),
                    icon: const Icon(Icons.public_rounded),
                    label: Text(widget.ru ? 'Опубликовать' : 'Publish'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (permissions == null) return;
    await CgMusicLibraryStore.publish(track, permissions: permissions);
    await _load();
  }

  Future<void> _trackMenu(CgMusicTrack track) async {
    final published = _tracks.any(
      (item) => item.source == CgMusicSource.public && item.path == track.path,
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (track.permissions.canSave)
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: Text(
                  widget.ru ? 'Добавить к себе' : 'Add to my library',
                ),
                onTap: () => Navigator.pop(context, 'save'),
              ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(
                widget.ru ? 'Добавить в плейлист' : 'Add to playlist',
              ),
              onTap: () => Navigator.pop(context, 'playlist'),
            ),
            if (track.permissions.canShare)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(widget.ru ? 'Поделиться файлом' : 'Share file'),
                onTap: () => Navigator.pop(context, 'share'),
              ),
            if (track.source != CgMusicSource.public)
              ListTile(
                leading: Icon(
                  published ? Icons.public_off_rounded : Icons.public_rounded,
                ),
                title: Text(
                  published
                      ? (widget.ru
                            ? 'Убрать из публичного поиска'
                            : 'Remove from public search')
                      : (widget.ru
                            ? 'Опубликовать в поиске'
                            : 'Publish to search'),
                ),
                onTap: () =>
                    Navigator.pop(context, published ? 'unpublish' : 'publish'),
              ),
            if (track.source == CgMusicSource.saved)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(
                  widget.ru ? 'Удалить из сохранённого' : 'Remove from saved',
                ),
                onTap: () => Navigator.pop(context, 'removeSaved'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'save':
        await CgMusicLibraryStore.saveTrack(track);
        await _load();
      case 'playlist':
        await _addToPlaylist(track);
      case 'share':
        await Share.shareXFiles(<XFile>[XFile(track.path)], text: track.title);
      case 'publish':
        await _publish(track);
      case 'unpublish':
        await CgMusicLibraryStore.unpublish(track.path);
        await _load();
      case 'removeSaved':
        await CgMusicLibraryStore.removeSaved(track.id);
        await _load();
    }
  }

  Future<void> _showRecognition() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChernogramLogo(size: 94),
              const SizedBox(height: 12),
              Text(
                widget.ru ? 'Распознавание музыки' : 'Music recognition',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'Поиск по публичному каталогу уже заложен. Следующим этапом подключается нативный Chromaprint: 12 секунд с микрофона, локальный отпечаток и поиск без хранения записи.'
                    : 'Public catalog lookup is ready. The next step connects native Chromaprint: a 12-second microphone sample, local fingerprinting and lookup without retaining the recording.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _source = CgMusicSource.public;
                    _playlistId = null;
                    _globalSearch = true;
                  });
                },
                icon: const Icon(Icons.public_rounded),
                label: Text(
                  widget.ru
                      ? 'Открыть публичный каталог'
                      : 'Open public catalog',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(CgMusicSource source) => switch (source) {
    CgMusicSource.device => widget.ru ? 'Устройство' : 'Device',
    CgMusicSource.chats => widget.ru ? 'Из чатов' : 'Chats',
    CgMusicSource.folders => widget.ru ? 'Папки' : 'Folders',
    CgMusicSource.saved => widget.ru ? 'Сохранённое' : 'Saved',
    CgMusicSource.public => widget.ru ? 'Публичное' : 'Public',
  };

  IconData _sourceIcon(CgMusicSource source) => switch (source) {
    CgMusicSource.device => Icons.smartphone_rounded,
    CgMusicSource.chats => Icons.forum_outlined,
    CgMusicSource.folders => Icons.folder_outlined,
    CgMusicSource.saved => Icons.bookmark_outline_rounded,
    CgMusicSource.public => Icons.public_rounded,
  };

  int _count(CgMusicSource source) =>
      _tracks.where((item) => item.source == source).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Музыка' : 'Music'),
        actions: [
          IconButton(
            tooltip: widget.ru ? 'Распознать музыку' : 'Recognize music',
            onPressed: _showRecognition,
            icon: const Icon(Icons.graphic_eq_rounded),
          ),
          IconButton(
            tooltip: widget.ru ? 'Новый плейлист' : 'New playlist',
            onPressed: _createPlaylist,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
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
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: widget.ru
                    ? 'Глобальный поиск музыки'
                    : 'Global music search',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: widget.ru
                          ? 'Искать во всех источниках'
                          : 'Search all sources',
                      onPressed: () =>
                          setState(() => _globalSearch = !_globalSearch),
                      icon: Icon(
                        _globalSearch
                            ? Icons.travel_explore_rounded
                            : Icons.filter_alt_outlined,
                        color: _globalSearch ? scheme.primary : null,
                      ),
                    ),
                    if (_search.text.isNotEmpty)
                      IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemCount: CgMusicSource.values.length,
              itemBuilder: (context, index) {
                final source = CgMusicSource.values[index];
                final selected = _playlistId == null && _source == source;
                return ChoiceChip(
                  selected: selected,
                  avatar: Icon(_sourceIcon(source), size: 17),
                  label: Text('${_sourceLabel(source)} · ${_count(source)}'),
                  onSelected: (_) => setState(() {
                    _source = source;
                    _playlistId = null;
                  }),
                );
              },
            ),
          ),
          if (_playlists.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  return InputChip(
                    selected: _playlistId == playlist.id,
                    avatar: const Icon(Icons.queue_music_rounded, size: 17),
                    label: Text(
                      '${playlist.name} · ${playlist.trackIds.length}',
                    ),
                    onPressed: () => setState(() {
                      _playlistId = _playlistId == playlist.id
                          ? null
                          : playlist.id;
                    }),
                    onDeleted: () async {
                      await CgMusicLibraryStore.removePlaylist(playlist.id);
                      _playlists = await CgMusicLibraryStore.loadPlaylists();
                      if (mounted) setState(() => _playlistId = null);
                    },
                  );
                },
              ),
            ),
          ],
          if (_folders.isNotEmpty && _source == CgMusicSource.folders) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _folders.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  return InputChip(
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    label: Text(folder.split(Platform.pathSeparator).last),
                    onDeleted: () => _removeFolder(folder),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                ? _EmptyMusic(
                    ru: widget.ru,
                    message: _permissionError,
                    source: _source,
                    onAddFolder: _addFolder,
                  )
                : ValueListenableBuilder<String?>(
                    valueListenable: _hub.activeTrackId,
                    builder: (context, activeId, _) => ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 210),
                      itemCount: _visible.length,
                      itemBuilder: (context, index) {
                        final track = _visible[index];
                        final active = activeId == track.id;
                        return Material(
                          color: active
                              ? scheme.primary.withValues(alpha: .11)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            onTap: track.permissions.canPlay
                                ? () => _play(track)
                                : null,
                            leading: StreamBuilder<PlayerState>(
                              stream: _hub.player.playerStateStream,
                              builder: (context, state) => SizedBox(
                                width: 44,
                                height: 44,
                                child: active
                                    ? _MaskEqualizer(
                                        active: state.data?.playing == true,
                                        size: 42,
                                      )
                                    : DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
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
                              track.author.isEmpty
                                  ? track.subtitle
                                  : '${track.author} · ${track.subtitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              onPressed: () => _trackMenu(track),
                              icon: const Icon(Icons.more_vert_rounded),
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

class _EmptyMusic extends StatelessWidget {
  final bool ru;
  final String? message;
  final CgMusicSource source;
  final VoidCallback onAddFolder;

  const _EmptyMusic({
    required this.ru,
    required this.message,
    required this.source,
    required this.onAddFolder,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 68,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .18),
          ),
          const SizedBox(height: 12),
          Text(
            message ?? (ru ? 'В этом разделе пока пусто' : 'Nothing here yet'),
            textAlign: TextAlign.center,
          ),
          if (source == CgMusicSource.folders) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAddFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(ru ? 'Добавить папку с музыкой' : 'Add music folder'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MusicNowPlaying extends StatefulWidget {
  final bool ru;

  const _MusicNowPlaying({required this.ru});

  @override
  State<_MusicNowPlaying> createState() => _MusicNowPlayingState();
}

class _MusicNowPlayingState extends State<_MusicNowPlaying> {
  bool _remaining = false;

  String _time(Duration value) {
    final total = value.inSeconds.abs();
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${value.isNegative ? '-' : ''}$minutes:${seconds.toString().padLeft(2, '0')}';
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
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 7),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .24),
                  blurRadius: 24,
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
                          builder: (context, state) => _MaskEqualizer(
                            active: state.data?.playing == true,
                            size: 52,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                track.author.isEmpty
                                    ? track.subtitle
                                    : '${track.author} · ${track.subtitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
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
                              final total =
                                  durationSnapshot.data ?? Duration.zero;
                              final position =
                                  positionSnapshot.data ?? Duration.zero;
                              final maxValue = math
                                  .max(1, total.inMilliseconds)
                                  .toDouble();
                              final right = _remaining
                                  ? position - total
                                  : total;
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
                                            Duration(
                                              milliseconds: value.round(),
                                            ),
                                          ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _time(position),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        InkWell(
                                          onTap: () => setState(
                                            () => _remaining = !_remaining,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              _time(right),
                                              style: const TextStyle(
                                                fontSize: 10,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: hub.shuffleEnabled,
                          builder: (context, active, _) => IconButton(
                            tooltip: widget.ru
                                ? 'Случайный порядок'
                                : 'Shuffle',
                            onPressed: hub.toggleShuffle,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: active ? scheme.primary : null,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: hub.previous,
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 30,
                          ),
                        ),
                        StreamBuilder<PlayerState>(
                          stream: hub.player.playerStateStream,
                          builder: (context, state) => IconButton.filled(
                            onPressed: () => state.data?.playing == true
                                ? hub.player.pause()
                                : hub.player.play(),
                            iconSize: 32,
                            icon: Icon(
                              state.data?.playing == true
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: hub.next,
                          icon: const Icon(Icons.skip_next_rounded, size: 30),
                        ),
                        ValueListenableBuilder<LoopMode>(
                          valueListenable: hub.loopMode,
                          builder: (context, mode, _) => IconButton(
                            tooltip: widget.ru ? 'Повтор' : 'Repeat',
                            onPressed: hub.cycleLoopMode,
                            icon: Icon(
                              mode == LoopMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: mode == LoopMode.off
                                  ? null
                                  : scheme.primary,
                            ),
                          ),
                        ),
                      ],
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

class _MaskEqualizer extends StatefulWidget {
  final bool active;
  final double size;

  const _MaskEqualizer({required this.active, required this.size});

  @override
  State<_MaskEqualizer> createState() => _MaskEqualizerState();
}

class _MaskEqualizerState extends State<_MaskEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _MaskEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = .18;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _MaskEqualizerPainter(
          phase: _controller.value,
          active: widget.active,
        ),
      ),
    ),
  );
}

class _MaskEqualizerPainter extends CustomPainter {
  final double phase;
  final bool active;

  const _MaskEqualizerPainter({required this.phase, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB9A8FF), Color(0xFF7B5CFF), Color(0xFF20C7FF)],
    ).createShader(rect);
    const count = 13;
    final width = size.width / (count * 3.0);
    for (var index = 0; index < count; index++) {
      final t = index / (count - 1);
      final nx = t * 2 - 1;
      final ellipse = math.sqrt(math.max(0, 1 - nx * nx));
      final baseTop = size.height * (.14 + (1 - ellipse) * .11);
      final baseBottom = size.height * (.50 + ellipse * .34 - nx.abs() * .025);
      final wave = active
          ? .84 + .16 * math.sin((phase * math.pi * 2) + index * .78)
          : .92;
      final center = (baseTop + baseBottom) / 2;
      final half = (baseBottom - baseTop) * wave / 2;
      final top = center - half;
      final bottom = center + half;
      final paint = Paint()
        ..shader = shader
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      final x = size.width * (.14 + t * .72);
      final eyeGap = nx.abs() > .18 && nx.abs() < .72;
      if (eyeGap) {
        final gapStart = size.height * .38;
        final gapEnd = size.height * .45;
        if (top < gapStart) {
          canvas.drawLine(
            Offset(x, top),
            Offset(x, math.min(bottom, gapStart)),
            paint,
          );
        }
        if (bottom > gapEnd) {
          canvas.drawLine(
            Offset(x, math.max(top, gapEnd)),
            Offset(x, bottom),
            paint,
          );
        }
      } else {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskEqualizerPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.active != active;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
