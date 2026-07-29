import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'brand.dart';
import 'core_models.dart';
import 'media_library.dart';
import 'music_player.dart';

class CgMediaLibraryScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;

  const CgMediaLibraryScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnels,
  });

  @override
  State<CgMediaLibraryScreen> createState() => _CgMediaLibraryScreenState();
}

class _CgMediaLibraryScreenState extends State<CgMediaLibraryScreen> {
  final CgMediaLibraryStore _store = CgMediaLibraryStore.instance;
  final TextEditingController _search = TextEditingController();
  List<CgMediaLibraryAsset> _assets = const <CgMediaLibraryAsset>[];
  CgMediaLibrarySource? _source;
  String? _kind;
  bool _loading = true;
  bool _busy = false;
  bool _publicSearch = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    unawaited(_reload());
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

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    final assets = await _store.rebuildFromTunnels(
      tunnels: widget.tunnels,
      profile: widget.profile,
    );
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  List<CgMediaLibraryAsset> get _visible {
    final query = _search.text;
    if (_publicSearch) return _store.publicLocalSearch(query);
    return _store.search(query: query, source: _source, kind: _kind);
  }

  Future<void> _importFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _assets = await _store.importFiles(profile: widget.profile);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(CgMediaLibraryAsset asset) async {
    final path = asset.localPath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Файл не сохранён на этом устройстве.'
                : 'The file is not stored on this device.',
          ),
        ),
      );
      return;
    }
    if (asset.kind == 'audio' || asset.kind == 'voice') {
      await CgMusicHub.instance.playFile(
        id: 'library:${asset.id}',
        title: asset.name,
        subtitle: asset.tunnelName ?? asset.ownerName,
        path: path,
        source: asset.source.name,
      );
      return;
    }
    await OpenFilex.open(path);
  }

  Future<void> _share(CgMediaLibraryAsset asset) async {
    if (!asset.rights.canShare || asset.localPath == null) return;
    final file = File(asset.localPath!);
    if (!await file.exists()) return;
    await Share.shareXFiles(
      <XFile>[XFile(file.path)],
      text: '${asset.name}\n${asset.ownerName}',
    );
  }

  Future<void> _save(CgMediaLibraryAsset asset) async {
    final saved = await _store.saveToLibrary(
      asset,
      profile: widget.profile,
    );
    if (!mounted) return;
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Владелец запретил сохранение или файл недоступен.'
                : 'The owner disabled saving or the file is unavailable.',
          ),
        ),
      );
      return;
    }
    setState(() => _assets = _store.all());
  }

  Future<void> _delete(CgMediaLibraryAsset asset) async {
    if (asset.source != CgMediaLibrarySource.saved &&
        asset.source != CgMediaLibrarySource.device) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Удалить из медиатеки?' : 'Remove from library?'),
        content: Text(
          widget.ru
              ? 'Локальная копия будет удалена. Исходное сообщение в чате не изменится.'
              : 'The local copy will be deleted. The original chat message is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Удалить' : 'Delete'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _store.remove(asset.id);
    if (mounted) setState(() => _assets = _store.all());
  }

  Future<void> _editRights(CgMediaLibraryAsset asset) async {
    var rights = asset.rights;
    final result = await showModalBottomSheet<CgMediaRights>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.ru ? 'Доступ к файлу' : 'File access',
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(asset.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                SegmentedButton<CgMediaVisibility>(
                  segments: [
                    ButtonSegment(
                      value: CgMediaVisibility.private,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: Text(widget.ru ? 'Только я' : 'Private'),
                    ),
                    ButtonSegment(
                      value: CgMediaVisibility.contacts,
                      icon: const Icon(Icons.people_outline_rounded),
                      label: Text(widget.ru ? 'Контакты' : 'Contacts'),
                    ),
                    ButtonSegment(
                      value: CgMediaVisibility.public,
                      icon: const Icon(Icons.public_rounded),
                      label: Text(widget.ru ? 'Публичный' : 'Public'),
                    ),
                  ],
                  selected: <CgMediaVisibility>{rights.visibility},
                  onSelectionChanged: (selected) => setSheetState(() {
                    final visibility = selected.first;
                    rights = rights.copyWith(
                      visibility: visibility,
                      indexed: visibility == CgMediaVisibility.public
                          ? rights.indexed
                          : false,
                    );
                  }),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: rights.canDownload,
                  onChanged: (value) => setSheetState(
                    () => rights = rights.copyWith(canDownload: value),
                  ),
                  title: Text(widget.ru ? 'Разрешить скачивание' : 'Allow download'),
                ),
                SwitchListTile(
                  value: rights.canShare,
                  onChanged: (value) => setSheetState(
                    () => rights = rights.copyWith(canShare: value),
                  ),
                  title: Text(widget.ru ? 'Разрешить делиться' : 'Allow sharing'),
                ),
                SwitchListTile(
                  value: rights.canSave,
                  onChanged: (value) => setSheetState(
                    () => rights = rights.copyWith(canSave: value),
                  ),
                  title: Text(widget.ru ? 'Разрешить добавить к себе' : 'Allow save to library'),
                ),
                SwitchListTile(
                  value: rights.indexed,
                  onChanged: rights.visibility == CgMediaVisibility.public
                      ? (value) => setSheetState(
                            () => rights = rights.copyWith(indexed: value),
                          )
                      : null,
                  title: Text(widget.ru ? 'Показывать в глобальном поиске' : 'Show in global search'),
                  subtitle: Text(
                    widget.ru
                        ? 'Индексируется только после явного включения владельцем.'
                        : 'Indexing is enabled only by an explicit owner choice.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, rights),
                    icon: const Icon(Icons.save_rounded),
                    label: Text(widget.ru ? 'Сохранить права' : 'Save permissions'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    await _store.updateRights(asset.id, result);
    if (mounted) setState(() => _assets = _store.all());
  }

  String _sourceName(CgMediaLibrarySource source) => switch (source) {
        CgMediaLibrarySource.device => widget.ru ? 'Устройство' : 'Device',
        CgMediaLibrarySource.chat => widget.ru ? 'Чаты' : 'Chats',
        CgMediaLibrarySource.voice => widget.ru ? 'Голосовые' : 'Voice',
        CgMediaLibrarySource.saved => widget.ru ? 'Сохранённое' : 'Saved',
        CgMediaLibrarySource.publicCatalog => widget.ru ? 'Публичное' : 'Public',
      };

  IconData _sourceIcon(CgMediaLibrarySource source) => switch (source) {
        CgMediaLibrarySource.device => Icons.devices_rounded,
        CgMediaLibrarySource.chat => Icons.forum_outlined,
        CgMediaLibrarySource.voice => Icons.graphic_eq_rounded,
        CgMediaLibrarySource.saved => Icons.bookmark_outline_rounded,
        CgMediaLibrarySource.publicCatalog => Icons.public_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Медиатека' : 'Media library'),
        actions: [
          IconButton(
            tooltip: widget.ru ? 'Добавить файлы' : 'Add files',
            onPressed: _busy ? null : _importFiles,
            icon: const Icon(Icons.add_to_photos_outlined),
          ),
          IconButton(
            tooltip: widget.ru ? 'Обновить' : 'Refresh',
            onPressed: _busy ? null : _reload,
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
                prefixIcon: Icon(
                  _publicSearch ? Icons.travel_explore_rounded : Icons.search_rounded,
                ),
                hintText: _publicSearch
                    ? (widget.ru ? 'Поиск опубликованных файлов' : 'Search published files')
                    : (widget.ru ? 'Название, автор или чат' : 'Name, author or chat'),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.folder_copy_outlined),
                        label: Text(widget.ru ? 'Мои файлы' : 'My files'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.public_rounded),
                        label: Text(widget.ru ? 'Глобальный поиск' : 'Global search'),
                      ),
                    ],
                    selected: <bool>{_publicSearch},
                    onSelectionChanged: (value) => setState(() {
                      _publicSearch = value.first;
                      if (_publicSearch) {
                        _source = null;
                        _kind = null;
                      }
                    }),
                  ),
                ),
              ],
            ),
          ),
          if (!_publicSearch) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemCount: CgMediaLibrarySource.values.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return FilterChip(
                      selected: _source == null,
                      avatar: const Icon(Icons.apps_rounded, size: 17),
                      label: Text(widget.ru ? 'Все' : 'All'),
                      onSelected: (_) => setState(() => _source = null),
                    );
                  }
                  final source = CgMediaLibrarySource.values[index - 1];
                  return FilterChip(
                    selected: _source == source,
                    avatar: Icon(_sourceIcon(source), size: 17),
                    label: Text(_sourceName(source)),
                    onSelected: (_) => setState(() => _source = source),
                  );
                },
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemCount: const <String?>[null, 'image', 'video', 'audio', 'voice', 'file'].length,
                itemBuilder: (context, index) {
                  final kind = const <String?>[
                    null,
                    'image',
                    'video',
                    'audio',
                    'voice',
                    'file',
                  ][index];
                  final label = switch (kind) {
                    'image' => widget.ru ? 'Фото' : 'Photos',
                    'video' => widget.ru ? 'Видео' : 'Video',
                    'audio' => widget.ru ? 'Музыка' : 'Music',
                    'voice' => widget.ru ? 'Голосовые' : 'Voice',
                    'file' => widget.ru ? 'Документы' : 'Documents',
                    _ => widget.ru ? 'Все типы' : 'All types',
                  };
                  return FilterChip(
                    selected: _kind == kind,
                    label: Text(label),
                    onSelected: (_) => setState(() => _kind = kind),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: _loading || _busy
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            _publicSearch
                                ? (widget.ru
                                    ? 'Опубликованных файлов по этому запросу пока нет. После подключения Media Gateway здесь появятся результаты других пользователей.'
                                    : 'No published files match yet. Other users appear here after Media Gateway integration.')
                                : (widget.ru
                                    ? 'В этом разделе пока нет файлов.'
                                    : 'There are no files in this section yet.'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 340,
                          mainAxisExtent: 142,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final asset = visible[index];
                          return _MediaAssetCard(
                            asset: asset,
                            ru: widget.ru,
                            onOpen: () => _open(asset),
                            onShare: asset.rights.canShare ? () => _share(asset) : null,
                            onSave: asset.rights.canSave &&
                                    asset.source != CgMediaLibrarySource.saved
                                ? () => _save(asset)
                                : null,
                            onRights: asset.ownerId == widget.profile.id
                                ? () => _editRights(asset)
                                : null,
                            onDelete: asset.source == CgMediaLibrarySource.saved ||
                                    asset.source == CgMediaLibrarySource.device
                                ? () => _delete(asset)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomSheet: const _LibraryPlayerSheet(),
    );
  }
}

class _MediaAssetCard extends StatelessWidget {
  final CgMediaLibraryAsset asset;
  final bool ru;
  final VoidCallback onOpen;
  final VoidCallback? onShare;
  final VoidCallback? onSave;
  final VoidCallback? onRights;
  final VoidCallback? onDelete;

  const _MediaAssetCard({
    required this.asset,
    required this.ru,
    required this.onOpen,
    this.onShare,
    this.onSave,
    this.onRights,
    this.onDelete,
  });

  IconData get _icon => switch (asset.kind) {
        'image' => Icons.image_outlined,
        'video' => Icons.movie_outlined,
        'audio' => Icons.music_note_rounded,
        'voice' => Icons.graphic_eq_rounded,
        _ => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 7, 8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 78,
                child: _AssetPreview(asset: asset, fallback: _icon),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      asset.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      asset.tunnelName ?? asset.ownerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .56),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          asset.published ? Icons.public_rounded : Icons.lock_outline_rounded,
                          size: 13,
                          color: asset.published ? ChernogramColors.success : null,
                        ),
                        Text(
                          asset.published
                              ? (ru ? 'опубликован' : 'published')
                              : asset.source.name,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'share':
                      onShare?.call();
                      break;
                    case 'save':
                      onSave?.call();
                      break;
                    case 'rights':
                      onRights?.call();
                      break;
                    case 'delete':
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (onSave != null)
                    PopupMenuItem(
                      value: 'save',
                      child: ListTile(
                        leading: const Icon(Icons.bookmark_add_outlined),
                        title: Text(ru ? 'Добавить к себе' : 'Save to library'),
                      ),
                    ),
                  if (onShare != null)
                    PopupMenuItem(
                      value: 'share',
                      child: ListTile(
                        leading: const Icon(Icons.share_outlined),
                        title: Text(ru ? 'Поделиться' : 'Share'),
                      ),
                    ),
                  if (onRights != null)
                    PopupMenuItem(
                      value: 'rights',
                      child: ListTile(
                        leading: const Icon(Icons.admin_panel_settings_outlined),
                        title: Text(ru ? 'Доступ и публикация' : 'Access and publishing'),
                      ),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: Text(ru ? 'Удалить локально' : 'Delete locally'),
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

class _AssetPreview extends StatelessWidget {
  final CgMediaLibraryAsset asset;
  final IconData fallback;

  const _AssetPreview({required this.asset, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final path = asset.thumbnailPath ?? asset.localPath;
    final file = path == null ? null : File(path);
    if (asset.kind == 'image' && file != null && file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(file, fit: BoxFit.cover, cacheWidth: 240),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        fallback,
        size: 36,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _LibraryPlayerSheet extends StatelessWidget {
  const _LibraryPlayerSheet();

  @override
  Widget build(BuildContext context) {
    final hub = CgMusicHub.instance;
    return ValueListenableBuilder<List<CgMusicTrack>>(
      valueListenable: hub.queue,
      builder: (context, queue, _) {
        if (queue.isEmpty) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                StreamBuilder<PlayerState>(
                  stream: hub.player.playerStateStream,
                  builder: (context, state) => CgPlayingBars(
                    active: state.data?.playing == true,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hub.activeTrack?.title ?? queue.first.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                StreamBuilder<PlayerState>(
                  stream: hub.player.playerStateStream,
                  builder: (context, state) => IconButton.filled(
                    onPressed: state.data?.playing == true
                        ? hub.player.pause
                        : hub.player.play,
                    icon: Icon(
                      state.data?.playing == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close player',
                  onPressed: hub.stopAndClear,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
