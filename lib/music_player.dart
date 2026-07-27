import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'core_models.dart';

class CgMusicTrack {
  final String id;
  final String title;
  final String subtitle;
  final String path;

  const CgMusicTrack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.path,
  });
}

class CgMusicHub {
  CgMusicHub._();

  static final CgMusicHub instance = CgMusicHub._();

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<List<CgMusicTrack>> queue =
      ValueNotifier<List<CgMusicTrack>>(const <CgMusicTrack>[]);
  final ValueNotifier<String?> activeTrackId = ValueNotifier<String?>(null);

  StreamSubscription<int?>? _indexSubscription;

  Future<void> playQueue(
    List<CgMusicTrack> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, tracks.length - 1).toInt();
    queue.value = List<CgMusicTrack>.unmodifiable(tracks);
    await _indexSubscription?.cancel();
    _indexSubscription = player.currentIndexStream.listen((index) {
      final current = queue.value;
      if (index == null || index < 0 || index >= current.length) return;
      activeTrackId.value = current[index].id;
    });
    final sources = tracks
        .map(
          (track) => AudioSource.uri(
            Uri.file(track.path),
            tag: MediaItem(
              id: track.id,
              album: track.subtitle,
              title: track.title,
            ),
          ),
        )
        .toList();
    await player.setAudioSources(sources, initialIndex: safeIndex);
    activeTrackId.value = tracks[safeIndex].id;
    await player.play();
  }

  Future<void> playSingle(CgMusicTrack track) async {
    if (activeTrackId.value == track.id && queue.value.isNotEmpty) {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }
    await playQueue(<CgMusicTrack>[track]);
  }

  Future<void> next() async {
    if (player.hasNext) await player.seekToNext();
  }

  Future<void> previous() async {
    if (player.hasPrevious) await player.seekToPrevious();
  }
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
  bool _loading = true;
  String? _permissionError;

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

  Future<File?> _ensureAttachment(CgAttachment attachment) async {
    final local = attachment.localPath;
    if (local != null && local.isNotEmpty) {
      final file = File(local);
      if (await file.exists()) return file;
    }
    final raw = attachment.dataBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}/chernogram_music_cache');
      if (!await directory.exists()) await directory.create(recursive: true);
      final safeName = attachment.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]+'),
        '_',
      );
      final file = File('${directory.path}/${attachment.id}_$safeName');
      if (!await file.exists()) {
        await file.writeAsBytes(base64Decode(raw), flush: true);
      }
      return file;
    } catch (_) {
      return null;
    }
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
        final file = await _ensureAttachment(attachment);
        if (file == null) continue;
        tracks.add(
          CgMusicTrack(
            id: 'chat:${tunnel.id}:${attachment.id}',
            title: attachment.name,
            subtitle: '${widget.ru ? 'Чат' : 'Chat'}: ${tunnel.displayName}',
            path: file.path,
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
    final assets = await paths.first.getAssetListPaged(page: 0, size: 1000);
    final tracks = <CgMusicTrack>[];
    for (final asset in assets) {
      try {
        final file = await asset.file;
        if (file == null || !await file.exists()) continue;
        final title = ((await asset.titleAsync) ?? '').trim();
        tracks.add(
          CgMusicTrack(
            id: 'device:${asset.id}',
            title: title.isEmpty
                ? file.path.split(Platform.pathSeparator).last
                : title,
            subtitle: widget.ru ? 'Музыка на телефоне' : 'Music on device',
            path: file.path,
          ),
        );
      } catch (_) {}
    }
    return tracks;
  }

  Future<void> _load() async {
    final chat = await _chatTracks();
    final device = await _deviceTracks();
    final unique = <String, CgMusicTrack>{};
    for (final track in <CgMusicTrack>[...chat, ...device]) {
      unique[track.path] = track;
    }
    final tracks = unique.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  List<CgMusicTrack> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _tracks;
    return _tracks
        .where(
          (track) => track.title.toLowerCase().contains(query) ||
              track.subtitle.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _play(CgMusicTrack track) async {
    final visible = _visible;
    final index = visible.indexWhere((item) => item.id == track.id);
    await _hub.playQueue(visible, initialIndex: math.max(0, index));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Музыка' : 'Music'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: widget.ru
                    ? 'Поиск по музыке в чатах и на телефоне'
                    : 'Search music in chats and on device',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            _permissionError ??
                                (widget.ru
                                    ? 'Музыка пока не найдена'
                                    : 'No music found'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ValueListenableBuilder<String?>(
                        valueListenable: _hub.activeTrackId,
                        builder: (context, activeId, _) => ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 130),
                          itemCount: _visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final track = _visible[index];
                            final active = activeId == track.id;
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                onTap: () => _play(track),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      scheme.primary.withValues(alpha: .16),
                                  child: Icon(
                                    active
                                        ? Icons.graphic_eq_rounded
                                        : Icons.music_note_rounded,
                                    color: scheme.primary,
                                  ),
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  track.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: StreamBuilder<PlayerState>(
                                  stream: _hub.player.playerStateStream,
                                  builder: (context, state) => Icon(
                                    active && state.data?.playing == true
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_fill_rounded,
                                    size: 34,
                                    color: scheme.primary,
                                  ),
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

class _MusicNowPlaying extends StatelessWidget {
  final bool ru;

  const _MusicNowPlaying({required this.ru});

  @override
  Widget build(BuildContext context) {
    final hub = CgMusicHub.instance;
    return ValueListenableBuilder<List<CgMusicTrack>>(
      valueListenable: hub.queue,
      builder: (context, queue, _) {
        if (queue.isEmpty) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Material(
            elevation: 18,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                          IconButton(
                            onPressed: hub.previous,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          const SizedBox(width: 10),
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
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: hub.next,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                          const SizedBox(width: 10),
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
                                  track.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
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
                            return Slider(
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
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
