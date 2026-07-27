import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'brand.dart';
import 'core_models.dart';

class CgMediaItem {
  final String tunnelId;
  final String tunnelName;
  final String messageId;
  final String authorName;
  final DateTime sentAt;
  final CgAttachment attachment;

  const CgMediaItem({
    required this.tunnelId,
    required this.tunnelName,
    required this.messageId,
    required this.authorName,
    required this.sentAt,
    required this.attachment,
  });
}

class CgStorageStats {
  final int freeBytes;
  final int totalBytes;
  final int mediaBytes;

  const CgStorageStats({
    required this.freeBytes,
    required this.totalBytes,
    required this.mediaBytes,
  });
}

class CgMediaStore {
  static const MethodChannel _storageChannel =
      MethodChannel('chernogram/storage');

  static Future<Directory> rootDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/media_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  static Future<File> persistBytes({
    required String attachmentId,
    required String name,
    required List<int> bytes,
  }) async {
    final root = await rootDirectory();
    final file = File(
      '${root.path}/${_safeName(attachmentId)}_${_safeName(name)}',
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }

  static Future<File?> existingFile(CgAttachment attachment) async {
    final local = attachment.localPath;
    if (local != null && local.isNotEmpty) {
      final file = File(local);
      if (await file.exists()) return file;
    }
    final root = await rootDirectory();
    final candidate = File(
      '${root.path}/${_safeName(attachment.id)}_${_safeName(attachment.name)}',
    );
    return await candidate.exists() ? candidate : null;
  }

  static Future<File?> ensureFile(CgAttachment attachment) async {
    final existing = await existingFile(attachment);
    if (existing != null) return existing;
    final raw = attachment.dataBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = await Isolate.run<List<int>>(() => base64Decode(raw));
      return persistBytes(
        attachmentId: attachment.id,
        name: attachment.name,
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<CgMessage> cacheIncomingMessage(CgMessage message) async {
    final attachment = message.attachment;
    if (attachment == null) return message;
    final existing = await existingFile(attachment);
    if (existing != null) {
      return message.copyWith(
        attachment: attachment.copyWith(
          localPath: existing.path,
          clearData: true,
        ),
      );
    }
    final raw = attachment.dataBase64;
    if (raw == null || raw.isEmpty) {
      return message.copyWith(
        attachment: attachment.copyWith(clearData: true),
      );
    }
    final file = await ensureFile(attachment);
    return message.copyWith(
      attachment: attachment.copyWith(
        localPath: file?.path,
        clearData: true,
      ),
    );
  }

  static List<CgMediaItem> collect(List<CgTunnel> tunnels) {
    final result = <CgMediaItem>[];
    for (final tunnel in tunnels) {
      for (final message in tunnel.messages) {
        final attachment = message.attachment;
        if (message.deleted ||
            message.meta['localHidden'] == true ||
            attachment == null ||
            message.meta['localPurged'] == true) {
          continue;
        }
        result.add(
          CgMediaItem(
            tunnelId: tunnel.id,
            tunnelName: tunnel.displayName,
            messageId: message.id,
            authorName: message.authorName,
            sentAt: message.sentAt,
            attachment: attachment,
          ),
        );
      }
    }
    result.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return result;
  }

  static CgMessage preserveLocalPurge(
    CgMessage? existing,
    CgMessage incoming,
  ) {
    if (existing?.meta['localPurged'] != true ||
        existing?.attachment?.id != incoming.attachment?.id) {
      return incoming;
    }
    final attachment = incoming.attachment;
    if (attachment == null) return existing!;
    return incoming.copyWith(
      attachment: CgAttachment(
        id: attachment.id,
        name: attachment.name,
        size: attachment.size,
        kind: attachment.kind,
      ),
      meta: <String, dynamic>{...incoming.meta, 'localPurged': true},
    );
  }

  static Future<List<CgTunnel>> purgeItem(
    List<CgTunnel> tunnels,
    CgMediaItem item,
  ) async {
    final file = await existingFile(item.attachment);
    if (file != null) {
      try {
        final root = await rootDirectory();
        if (file.path.startsWith(root.path) && await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    final result = <CgTunnel>[];
    for (final tunnel in tunnels) {
      if (tunnel.id != item.tunnelId) {
        result.add(tunnel);
        continue;
      }
      final messages = <CgMessage>[];
      for (final message in tunnel.messages) {
        if (message.id != item.messageId || message.attachment == null) {
          messages.add(message);
          continue;
        }
        final attachment = message.attachment!;
        messages.add(
          message.copyWith(
            attachment: CgAttachment(
              id: attachment.id,
              name: attachment.name,
              size: attachment.size,
              kind: attachment.kind,
            ),
            meta: <String, dynamic>{...message.meta, 'localPurged': true},
          ),
        );
      }
      result.add(tunnel.copyWith(messages: messages));
    }
    await CgStore.saveTunnels(result);
    return result;
  }

  static Future<List<CgTunnel>> purgeAll(List<CgTunnel> tunnels) async {
    var current = tunnels;
    for (final item in collect(tunnels)) {
      current = await purgeItem(current, item);
    }
    return current;
  }

  static Future<int> mediaBytes() async {
    final root = await rootDirectory();
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<CgStorageStats> storageStats() async {
    final media = await mediaBytes();
    try {
      final raw = await _storageChannel.invokeMapMethod<String, dynamic>(
        'getStorageStats',
      );
      return CgStorageStats(
        freeBytes: int.tryParse(raw?['freeBytes']?.toString() ?? '') ?? -1,
        totalBytes: int.tryParse(raw?['totalBytes']?.toString() ?? '') ?? -1,
        mediaBytes: media,
      );
    } catch (_) {
      return CgStorageStats(
        freeBytes: -1,
        totalBytes: -1,
        mediaBytes: media,
      );
    }
  }

  static bool isAudio(CgAttachment attachment) =>
      attachment.kind == 'audio' || attachment.kind == 'voice';

  static bool isVideo(CgAttachment attachment) =>
      attachment.kind == 'video' || attachment.kind == 'circle';

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static Future<void> open(CgAttachment attachment) async {
    final file = await ensureFile(attachment);
    if (file != null) await OpenFilex.open(file.path);
  }

  static Future<void> share(CgAttachment attachment) async {
    final file = await ensureFile(attachment);
    if (file != null) {
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
    }
  }

  static Future<bool> saveToDevice(CgAttachment attachment) async {
    final file = await ensureFile(attachment);
    if (file == null) return false;
    final target = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить файл',
      fileName: attachment.name,
    );
    if (target == null || target.isEmpty) return false;
    try {
      await file.copy(target);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class CgVoiceRecordButton extends StatefulWidget {
  final bool ru;
  final bool enabled;
  final Future<void> Function(File file, Duration duration) onRecorded;

  const CgVoiceRecordButton({
    super.key,
    required this.ru,
    required this.enabled,
    required this.onRecorded,
  });

  @override
  State<CgVoiceRecordButton> createState() => _CgVoiceRecordButtonState();
}

class _CgVoiceRecordButtonState extends State<CgVoiceRecordButton> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _cancel = false;

  Future<void> _start() async {
    if (!widget.enabled || _recording) return;
    if (!await _recorder.hasPermission()) return;
    final root = await CgMediaStore.rootDirectory();
    final path =
        '${root.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: path,
    );
    if (!mounted) return;
    _startedAt = DateTime.now();
    setState(() {
      _recording = true;
      _cancel = false;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      if (_elapsed >= const Duration(minutes: 10)) unawaited(_finish());
    });
  }

  Future<void> _finish() async {
    if (!_recording) return;
    _timer?.cancel();
    _timer = null;
    final duration = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    String? path;
    if (_cancel || duration < const Duration(milliseconds: 500)) {
      await _recorder.cancel();
    } else {
      path = await _recorder.stop();
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _cancel = false;
        _elapsed = Duration.zero;
      });
    }
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await widget.onRecorded(file, duration);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        '${_elapsed.inMinutes.toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: _recording ? 164 : 48,
      height: 48,
      decoration: BoxDecoration(
        color: _cancel
            ? ChernogramColors.danger.withValues(alpha: .22)
            : Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => unawaited(_start()),
        onLongPressMoveUpdate: (details) {
          if (!_recording) return;
          final cancel = details.localPosition.dx < -45;
          if (cancel != _cancel) setState(() => _cancel = cancel);
        },
        onLongPressEnd: (_) => unawaited(_finish()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _cancel ? Icons.delete_outline_rounded : Icons.mic_rounded,
                color: Colors.white,
              ),
              if (_recording) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cancel
                        ? (widget.ru ? 'Отпустите — отмена' : 'Release to cancel')
                        : '$label  ← ${widget.ru ? 'отмена' : 'cancel'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CgInlineAttachment extends StatefulWidget {
  final CgAttachment attachment;
  final bool hidden;
  final bool ru;
  final Future<File?> Function(CgAttachment attachment)? onEnsure;
  final Future<void> Function(CgAttachment attachment, File file)? onPlayAudio;
  final Future<void> Function()? onDelete;
  final bool canDownload;

  const CgInlineAttachment({
    super.key,
    required this.attachment,
    required this.hidden,
    required this.ru,
    this.onEnsure,
    this.onPlayAudio,
    this.onDelete,
    this.canDownload = true,
  });

  @override
  State<CgInlineAttachment> createState() => _CgInlineAttachmentState();
}

class _CgInlineAttachmentState extends State<CgInlineAttachment> {
  File? _file;
  bool _loading = false;
  bool _revealed = false;

  Future<File?> _ensure() async {
    if (_file != null && await _file!.exists()) return _file;
    if (mounted) setState(() => _loading = true);
    _file = await CgMediaStore.existingFile(widget.attachment);
    _file ??= await widget.onEnsure?.call(widget.attachment);
    _file ??= await CgMediaStore.ensureFile(widget.attachment);
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
    if (widget.attachment.kind == 'image' && !_revealed) {
      setState(() => _revealed = true);
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
      if (file != null) {
        await Share.shareXFiles(<XFile>[XFile(file.path)]);
      }
    }
    if (value == 'delete') await widget.onDelete?.call();
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
    if (_revealed && attachment.kind == 'image' && _file != null) {
      return GestureDetector(
        onTap: _showImage,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            _file!,
            width: 280,
            height: 210,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: 700,
          ),
        ),
      );
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

class CgMediaLibraryScreen extends StatefulWidget {
  final bool ru;
  final List<CgTunnel> tunnels;
  final ValueChanged<List<CgTunnel>> onTunnelsChanged;
  final String initialFilter;

  const CgMediaLibraryScreen({
    super.key,
    required this.ru,
    required this.tunnels,
    required this.onTunnelsChanged,
    this.initialFilter = 'all',
  });

  @override
  State<CgMediaLibraryScreen> createState() => _CgMediaLibraryScreenState();
}

class _CgMediaLibraryScreenState extends State<CgMediaLibraryScreen> {
  final AudioPlayer _player = AudioPlayer();
  late List<CgTunnel> _tunnels;
  List<CgMediaItem> _items = const <CgMediaItem>[];
  CgStorageStats? _stats;
  CgMediaItem? _playing;
  late String _filter;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tunnels = widget.tunnels;
    _filter = widget.initialFilter;
    _reload();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _reload() async {
    final stats = await CgMediaStore.storageStats();
    if (!mounted) return;
    setState(() {
      _items = CgMediaStore.collect(_tunnels);
      _stats = stats;
    });
  }

  List<CgMediaItem> get _visible => _items.where((item) {
        if (_filter == 'all') return true;
        if (_filter == 'audio') return CgMediaStore.isAudio(item.attachment);
        if (_filter == 'video') return CgMediaStore.isVideo(item.attachment);
        if (_filter == 'image') return item.attachment.kind == 'image';
        return !CgMediaStore.isAudio(item.attachment) &&
            !CgMediaStore.isVideo(item.attachment) &&
            item.attachment.kind != 'image';
      }).toList();

  Future<void> _play(CgMediaItem item) async {
    final file = await CgMediaStore.ensureFile(item.attachment);
    if (file == null) return;
    await _player.setFilePath(file.path);
    await _player.play();
    if (mounted) setState(() => _playing = item);
  }

  Future<void> _open(CgMediaItem item) async {
    if (CgMediaStore.isAudio(item.attachment)) {
      await _play(item);
      return;
    }
    final file = await CgMediaStore.ensureFile(item.attachment);
    if (file == null || !mounted) return;
    if (CgMediaStore.isVideo(item.attachment)) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CgVideoPlayerScreen(
            file: file,
            circle: item.attachment.kind == 'circle',
            title: item.attachment.name,
          ),
        ),
      );
      return;
    }
    if (item.attachment.kind == 'image' &&
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
    await OpenFilex.open(file.path);
  }

  Future<void> _delete(CgMediaItem item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Удалить локальный файл?' : 'Delete local file?'),
        content: Text(
          widget.ru
              ? 'Файл исчезнет с этого устройства, но текст сообщения останется в истории.'
              : 'The file is removed from this device, while the message remains in history.',
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
    setState(() => _busy = true);
    _tunnels = await CgMediaStore.purgeItem(_tunnels, item);
    widget.onTunnelsChanged(_tunnels);
    if (_playing?.messageId == item.messageId) {
      await _player.stop();
      _playing = null;
    }
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clearAll() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Очистить все локальные файлы?' : 'Clear all local files?'),
        content: Text(
          widget.ru
              ? 'Фото, видео, аудио и документы удалятся с устройства. Сообщения и названия файлов останутся.'
              : 'Photos, videos, audio and documents are removed from the device. Messages and filenames remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Очистить' : 'Clear'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => _busy = true);
    await _player.stop();
    _playing = null;
    _tunnels = await CgMediaStore.purgeAll(_tunnels);
    widget.onTunnelsChanged(_tunnels);
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final free = stats?.freeBytes ?? -1;
    final total = stats?.totalBytes ?? -1;
    final usedRatio = free >= 0 && total > 0
        ? ((total - free) / total).clamp(0.0, 1.0)
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialFilter == 'audio'
              ? (widget.ru ? 'Музыкальный плеер' : 'Music player')
              : (widget.ru ? 'Файлы и медиа' : 'Files and media'),
        ),
        actions: [
          IconButton(
            tooltip: widget.ru ? 'Очистить' : 'Clear',
            onPressed: _busy || _items.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storage_rounded),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          stats == null
                              ? (widget.ru ? 'Считаем место…' : 'Calculating storage…')
                              : '${widget.ru ? 'Медиа Чернограма' : 'Chernogram media'}: ${CgMediaStore.fileSize(stats.mediaBytes)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (free >= 0)
                        Text(
                          '${widget.ru ? 'свободно' : 'free'} ${CgMediaStore.fileSize(free)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(value: usedRatio),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <(String, String, IconData)>[
                ('all', widget.ru ? 'Все' : 'All', Icons.folder_copy_outlined),
                ('image', widget.ru ? 'Фото' : 'Photos', Icons.photo_outlined),
                ('video', widget.ru ? 'Видео' : 'Video', Icons.movie_outlined),
                ('audio', widget.ru ? 'Музыка' : 'Audio', Icons.headphones_outlined),
                ('files', widget.ru ? 'Файлы' : 'Files', Icons.description_outlined),
              ].map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: FilterChip(
                    selected: _filter == entry.$1,
                    avatar: Icon(entry.$3, size: 18),
                    label: Text(entry.$2),
                    onSelected: (_) => setState(() => _filter = entry.$1),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? Center(
                        child: Text(widget.ru ? 'Файлов пока нет' : 'No files yet'),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          4,
                          12,
                          _playing == null ? 24 : 112,
                        ),
                        itemCount: _visible.length,
                        itemBuilder: (_, index) {
                          final item = _visible[index];
                          return Card(
                            child: ListTile(
                              onTap: () => _open(item),
                              leading: _MediaLeading(item: item),
                              title: Text(
                                item.attachment.kind == 'voice'
                                    ? (widget.ru ? 'Голосовое сообщение' : 'Voice message')
                                    : item.attachment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              subtitle: Text(
                                '${item.tunnelName} • ${CgMediaStore.fileSize(item.attachment.size)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'share') {
                                    CgMediaStore.share(item.attachment);
                                  } else if (value == 'delete') {
                                    _delete(item);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'share',
                                    child: ListTile(
                                      leading: const Icon(Icons.share_outlined),
                                      title: Text(widget.ru ? 'Поделиться' : 'Share'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: ChernogramColors.danger,
                                      ),
                                      title: Text(widget.ru ? 'Удалить локально' : 'Delete locally'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomSheet: _playing == null
          ? null
          : SafeArea(
              top: false,
              child: Material(
                elevation: 12,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (_, snapshot) => IconButton.filled(
                          onPressed: () => snapshot.data?.playing == true
                              ? _player.pause()
                              : _player.play(),
                          icon: Icon(
                            snapshot.data?.playing == true
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _playing!.attachment.kind == 'voice'
                                  ? (widget.ru ? 'Голосовое сообщение' : 'Voice message')
                                  : _playing!.attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            StreamBuilder<Duration>(
                              stream: _player.positionStream,
                              builder: (_, position) => StreamBuilder<Duration?>(
                                stream: _player.durationStream,
                                builder: (_, duration) {
                                  final total = duration.data ?? Duration.zero;
                                  final current = position.data ?? Duration.zero;
                                  final max = math.max(1, total.inMilliseconds).toDouble();
                                  return Slider(
                                    min: 0,
                                    max: max,
                                    value: current.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                                    onChanged: total == Duration.zero
                                        ? null
                                        : (value) => _player.seek(
                                              Duration(milliseconds: value.round()),
                                            ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await _player.stop();
                          if (mounted) setState(() => _playing = null);
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _MediaLeading extends StatelessWidget {
  final CgMediaItem item;

  const _MediaLeading({required this.item});

  @override
  Widget build(BuildContext context) {
    final attachment = item.attachment;
    if (attachment.kind == 'image' && attachment.dataBase64 != null) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            base64Decode(attachment.dataBase64!),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      child: Icon(
        CgMediaStore.isAudio(attachment)
            ? Icons.graphic_eq_rounded
            : CgMediaStore.isVideo(attachment)
                ? Icons.play_arrow_rounded
                : Icons.description_outlined,
      ),
    );
  }
}

class CgImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String title;

  const CgImageViewer({super.key, required this.bytes, required this.title});

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
          maxScale: 5,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      );
}

class CgVideoPlayerScreen extends StatefulWidget {
  final File file;
  final bool circle;
  final String title;

  const CgVideoPlayerScreen({
    super.key,
    required this.file,
    required this.circle,
    required this.title,
  });

  @override
  State<CgVideoPlayerScreen> createState() => _CgVideoPlayerScreenState();
}

class _CgVideoPlayerScreenState extends State<CgVideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        unawaited(_controller.play());
      });
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: Center(
          child: !_ready
              ? const CircularProgressIndicator()
              : GestureDetector(
                  onTap: () => setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  }),
                  child: widget.circle
                      ? ClipOval(
                          child: SizedBox.square(
                            dimension: math.min(
                              MediaQuery.sizeOf(context).width - 34,
                              420.0,
                            ).toDouble(),
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _controller.value.size.width,
                                height: _controller.value.size.height,
                                child: VideoPlayer(_controller),
                              ),
                            ),
                          ),
                        )
                      : AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                ),
        ),
        floatingActionButton: _ready
            ? FloatingActionButton(
                onPressed: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: Icon(
                  _controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              )
            : null,
      );
}

class CgCircleRecorderScreen extends StatefulWidget {
  final bool ru;

  const CgCircleRecorderScreen({super.key, required this.ru});

  @override
  State<CgCircleRecorderScreen> createState() => _CgCircleRecorderScreenState();
}

class _CgCircleRecorderScreenState extends State<CgCircleRecorderScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Camera not found');
      _camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _busy = false;
      });
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.description ?? error.code;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(controller.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _camera != null) {
      unawaited(_initialize());
    }
  }

  Future<void> _toggleRecord() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_recording) {
      await controller.startVideoRecording();
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed >= const Duration(seconds: 60)) unawaited(_finish());
      });
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (!_recording) return;
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    if (controller == null) return;
    final xfile = await controller.stopVideoRecording();
    final source = File(xfile.path);
    final bytes = await source.readAsBytes();
    const maxBytes = 24 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Кружок получился больше 24 МБ. Запишите короче.'
                  : 'The circle is larger than 24 MB. Record a shorter one.',
            ),
          ),
        );
      }
      return;
    }
    final id = CgIds.random(20);
    final saved = await CgMediaStore.persistBytes(
      attachmentId: id,
      name: 'circle.mp4',
      bytes: bytes,
    );
    if (!mounted) return;
    Navigator.pop(
      context,
      CgAttachment(
        id: id,
        name: 'Кружок ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}.mp4',
        size: bytes.length,
        kind: 'circle',
        dataBase64: base64Encode(bytes),
        localPath: saved.path,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF050711),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(widget.ru ? 'Записать кружок' : 'Record a circle'),
        ),
        body: Center(
          child: _busy
              ? const CircularProgressIndicator()
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Builder(
                          builder: (context) {
                            final diameter = math.min(
                              MediaQuery.sizeOf(context).width - 48,
                              410.0,
                            ).toDouble();
                            final progress = (_elapsed.inMilliseconds / 60000)
                                .clamp(0.0, 1.0);
                            return SizedBox.square(
                              dimension: diameter + 14,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ClipOval(
                                    child: SizedBox.square(
                                      dimension: diameter,
                                      child: CameraPreview(_controller!),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CircularProgressIndicator(
                                      value: _recording ? progress : 0,
                                      strokeWidth: 7,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                  if (_recording)
                                    Positioned(
                                      bottom: 18,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${60 - _elapsed.inSeconds} сек',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${_elapsed.inMinutes.toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _toggleRecord,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: _recording ? 74 : 82,
                            height: _recording ? 74 : 82,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _recording
                                  ? ChernogramColors.danger
                                  : Theme.of(context).colorScheme.primary,
                              border: Border.all(color: Colors.white, width: 5),
                            ),
                            child: Icon(
                              _recording ? Icons.stop_rounded : Icons.videocam_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      );
}
