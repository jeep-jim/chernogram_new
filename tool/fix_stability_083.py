from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:220]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_block(path: str, start: str, end: str, new_block: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    start_at = text.find(start)
    if start_at < 0:
        raise SystemExit(f'Start marker not found in {path}: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End marker not found in {path}: {end!r}')
    file.write_text(text[:start_at] + new_block + text[end_at:], encoding='utf-8')


def replace_block_after(
    path: str,
    anchor: str,
    start: str,
    end: str,
    new_block: str,
) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    anchor_at = text.find(anchor)
    if anchor_at < 0:
        raise SystemExit(f'Anchor not found in {path}: {anchor!r}')
    start_at = text.find(start, anchor_at)
    if start_at < 0:
        raise SystemExit(f'Start marker after anchor not found in {path}: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End marker after anchor not found in {path}: {end!r}')
    file.write_text(text[:start_at] + new_block + text[end_at:], encoding='utf-8')


# Build 83 sits on top of the 0.81 + 0.82 generated client.
replace_once('pubspec.yaml', 'version: 0.82.0+82', 'version: 0.83.0+83')

# Persistent chat storage: never keep large attachment bodies in preferences.
# Old installs are migrated once at startup into the existing media directory.
replace_once(
    'lib/core_models.dart',
    "import 'dart:convert';\nimport 'dart:math';\n\nimport 'package:shared_preferences/shared_preferences.dart';\n",
    "import 'dart:convert';\nimport 'dart:io';\nimport 'dart:math';\n\nimport 'package:path_provider/path_provider.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
)

storage_helpers = r'''  static String _safeMediaName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  static Future<CgAttachment> _attachmentForStorage(
    CgAttachment attachment,
  ) async {
    final existingPath = attachment.localPath;
    if (existingPath != null && existingPath.isNotEmpty) {
      try {
        if (await File(existingPath).exists()) {
          return CgAttachment(
            id: attachment.id,
            name: attachment.name,
            size: attachment.size,
            kind: attachment.kind,
            localPath: existingPath,
          );
        }
      } catch (_) {}
    }

    final raw = attachment.dataBase64;
    if (raw == null || raw.isEmpty) return attachment;
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/chernogram_media');
      if (!await root.exists()) await root.create(recursive: true);
      final target = File(
        '${root.path}/${_safeMediaName(attachment.id)}_${_safeMediaName(attachment.name)}',
      );
      if (!await target.exists() || await target.length() == 0) {
        final sink = target.openWrite();
        const charsPerBlock = 256 * 1024;
        try {
          for (var start = 0; start < raw.length; start += charsPerBlock) {
            final end = (start + charsPerBlock < raw.length)
                ? start + charsPerBlock
                : raw.length;
            sink.add(base64Decode(raw.substring(start, end)));
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      return CgAttachment(
        id: attachment.id,
        name: attachment.name,
        size: attachment.size,
        kind: attachment.kind,
        localPath: target.path,
      );
    } catch (_) {
      return attachment;
    }
  }

  static Future<List<CgTunnel>> _tunnelsForStorage(
    List<CgTunnel> tunnels,
  ) async {
    final result = <CgTunnel>[];
    for (final tunnel in tunnels) {
      final messages = <CgMessage>[];
      for (final message in tunnel.messages) {
        final attachment = message.attachment;
        if (attachment == null) {
          messages.add(message);
          continue;
        }
        final stored = await _attachmentForStorage(attachment);
        messages.add(message.copyWith(attachment: stored));
      }
      result.add(tunnel.copyWith(messages: messages));
    }
    return result;
  }

  static Map<String, dynamic> _tunnelStorageJson(CgTunnel tunnel) {
    final json = tunnel.toJson();
    final messages = ((json['messages'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((raw) {
          final message = Map<String, dynamic>.from(raw);
          final rawAttachment = message['attachment'];
          if (rawAttachment is Map) {
            final attachment = Map<String, dynamic>.from(rawAttachment);
            final path = attachment['localPath']?.toString() ?? '';
            if (path.isNotEmpty) attachment.remove('dataBase64');
            message['attachment'] = attachment;
          }
          return message;
        })
        .toList(growable: false);
    json['messages'] = messages;
    return json;
  }

'''
replace_once(
    'lib/core_models.dart',
    '  static Future<List<CgTunnel>> loadTunnels() async {\n',
    storage_helpers + '  static Future<List<CgTunnel>> loadTunnels() async {\n',
)
replace_once(
    'lib/core_models.dart',
    '''      return decoded
          .whereType<Map>()
          .map((item) => CgTunnel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
''',
    '''      final loaded = decoded
          .whereType<Map>()
          .map((item) => CgTunnel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final prepared = await _tunnelsForStorage(loaded);
      await prefs.setString(
        tunnelsKey,
        jsonEncode(prepared.map(_tunnelStorageJson).toList()),
      );
      return prepared;
''',
)
replace_once(
    'lib/core_models.dart',
    '''  static Future<void> saveTunnels(List<CgTunnel> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      tunnelsKey,
      jsonEncode(tunnels.map((tunnel) => tunnel.toJson()).toList()),
    );
  }
''',
    '''  static Future<void> saveTunnels(List<CgTunnel> tunnels) async {
    final prepared = await _tunnelsForStorage(tunnels);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      tunnelsKey,
      jsonEncode(prepared.map(_tunnelStorageJson).toList()),
    );
  }
''',
)

# Media selection: copy selected files to app storage as streams instead of
# reading the whole file into RAM/base64.
persist_file = r'''  static Future<File> persistFile({
    required String attachmentId,
    required String name,
    required File source,
  }) async {
    final root = await rootDirectory();
    final target = File(
      '${root.path}/${_safeName(attachmentId)}_${_safeName(name)}',
    );
    if (source.absolute.path == target.absolute.path) return source;
    if (await target.exists()) await target.delete();
    await source.openRead().pipe(target.openWrite());
    return target;
  }

'''
replace_once(
    'lib/chat_media.dart',
    '  static Future<File?> ensureFile(CgAttachment attachment) async {\n',
    persist_file + '  static Future<File?> ensureFile(CgAttachment attachment) async {\n',
)

pick_function = r'''  Future<void> _pickAttachment(
    FileType type, {
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final sourcePath = picked.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Не удалось получить локальный путь к файлу.'
                  : 'Could not access the selected file.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _sendingFile = true);
    try {
      final id = CgIds.random(20);
      final local = await CgMediaStore.persistFile(
        attachmentId: id,
        name: picked.name,
        source: File(sourcePath),
      );
      final size = await local.length();
      final attachment = CgAttachment(
        id: id,
        name: picked.name,
        size: size,
        kind: _attachmentKind(picked.name),
        localPath: local.path,
      );
      await _sendAttachment(attachment);
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

'''
replace_block(
    'lib/chat_screen.dart',
    '  Future<void> _pickAttachment(',
    '  Future<void> _sendAttachment(CgAttachment attachment) async {',
    pick_function,
)

voice_function = r'''  Future<void> _sendVoice(File file, Duration duration) async {
    if (!await file.exists()) return;
    final id = CgIds.random(20);
    final local = await CgMediaStore.persistFile(
      attachmentId: id,
      name: 'voice.m4a',
      source: file,
    );
    final size = await local.length();
    await _sendAttachment(
      CgAttachment(
        id: id,
        name: 'Голосовое ${duration.inSeconds} сек.m4a',
        size: size,
        kind: 'voice',
        localPath: local.path,
      ),
    );
  }

'''
replace_block(
    'lib/chat_screen.dart',
    '  Future<void> _sendVoice(File file, Duration duration) async {',
    '  Future<void> _recordCircle() async {',
    voice_function,
)

circle_finish = r'''  Future<void> _finish() async {
    if (!_recording) return;
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    if (controller == null) return;
    final xfile = await controller.stopVideoRecording();
    final source = File(xfile.path);
    final id = CgIds.random(20);
    final saved = await CgMediaStore.persistFile(
      attachmentId: id,
      name: 'circle.mp4',
      source: source,
    );
    final size = await saved.length();
    if (!mounted) return;
    Navigator.pop(
      context,
      CgAttachment(
        id: id,
        name:
            'Кружок ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}.mp4',
        size: size,
        kind: 'circle',
        localPath: saved.path,
      ),
    );
  }

'''
replace_block_after(
    'lib/chat_media.dart',
    'class _CgCircleRecorderScreenState',
    '  Future<void> _finish() async {',
    '  @override\n  void dispose() {',
    circle_finish,
)

send_background = r'''  void _sendMessageBackground(CgMessage message) {
    Future<void> task() async {
      try {
        var session = _session;
        if (session == null) {
          await _connect().timeout(const Duration(seconds: 3));
          session = _session;
        }
        if (session == null) return;
        await session.sendMessage(message.toJson()).timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      } catch (_) {}
    }

    unawaited(task());
  }

'''
replace_block(
    'lib/chat_screen.dart',
    '  void _sendMessageBackground(CgMessage message) {',
    '  void _sendControlBackground(Map<String, dynamic> control) {',
    send_background,
)

# Internet core: non-blocking reconnect, clean outbox namespace and streaming
# file chunks from disk. Incoming chunks are written to disk at byte offsets.
replace_once(
    'lib/internet_core.dart',
    "import 'package:shared_preferences/shared_preferences.dart';\n",
    "import 'package:path_provider/path_provider.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
)
replace_once(
    'lib/internet_core.dart',
    '  static const int _fileChunkChars = 48000;\n',
    '  static const int _fileChunkChars = 48000;\n'
    '  static const int _fileChunkBytes = 36000;\n',
)
replace_once(
    'lib/internet_core.dart',
    "  String get _outboxKey => 'cg_impulse_outbox_v1_${tunnelId}_$profileId';\n",
    "  String get _outboxKey => 'cg_room_outbox_v83_${tunnelId}_$profileId';\n",
)
replace_once(
    'lib/internet_core.dart',
    "  final Map<String, List<String?>> _pendingFileChunks =\n"
    "      <String, List<String?>>{};\n",
    "  final Map<String, Set<int>> _pendingFileChunkIndexes =\n"
    "      <String, Set<int>>{};\n"
    "  final Map<String, int> _pendingFileChunkCounts = <String, int>{};\n"
    "  final Map<String, String> _pendingFilePaths = <String, String>{};\n"
    "  final Map<String, RandomAccessFile> _pendingFileHandles =\n"
    "      <String, RandomAccessFile>{};\n",
)
replace_once(
    'lib/internet_core.dart',
    r'''      case 'file_chunk':
        final transferId = data['transferId']?.toString() ?? '';
        final index = int.tryParse(data['index']?.toString() ?? '') ?? -1;
        final count = int.tryParse(data['count']?.toString() ?? '') ?? 0;
        final chunk = data['chunk']?.toString() ?? '';
        if (transferId.isEmpty || index < 0 || count <= 0 || chunk.isEmpty) {
          return;
        }
        final chunks = _pendingFileChunks.putIfAbsent(
          transferId,
          () => List<String?>.filled(count, null),
        );
        if (chunks.length != count || index >= chunks.length) return;
        chunks[index] = chunk;
        _emit('file_progress', <String, dynamic>{
          'transferId': transferId,
          'received': chunks.whereType<String>().length,
          'total': count,
        });
        _tryCompleteFile(transferId, sender, senderName, source);
        break;
''',
    r'''      case 'file_chunk':
        await _receiveFileChunk(data, sender, senderName, source);
        break;
''',
)
replace_once(
    'lib/internet_core.dart',
    '            _tryCompleteFile(transferId, sender, senderName, source);\n',
    '            unawaited(_tryCompleteFile(transferId, sender, senderName, source));\n',
)

file_receive_helpers = r'''  static String _safeIncomingName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  Future<String> _incomingPartPath(String transferId) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/chernogram_media');
    if (!await root.exists()) await root.create(recursive: true);
    return '${root.path}/.${_safeIncomingName(transferId)}.part';
  }

  Future<void> _receiveFileChunk(
    Map<String, dynamic> data,
    String sender,
    String senderName,
    String source,
  ) async {
    final transferId = data['transferId']?.toString() ?? '';
    final index = int.tryParse(data['index']?.toString() ?? '') ?? -1;
    final count = int.tryParse(data['count']?.toString() ?? '') ?? 0;
    final chunk = data['chunk']?.toString() ?? '';
    if (transferId.isEmpty || index < 0 || count <= 0 || chunk.isEmpty) {
      return;
    }
    List<int> bytes;
    try {
      bytes = base64Decode(chunk);
    } catch (_) {
      return;
    }

    var handle = _pendingFileHandles[transferId];
    if (handle == null) {
      final path = await _incomingPartPath(transferId);
      final file = File(path);
      if (await file.exists()) await file.delete();
      handle = await file.open(mode: FileMode.write);
      _pendingFileHandles[transferId] = handle;
      _pendingFilePaths[transferId] = path;
    }

    final byteOffset =
        int.tryParse(data['byteOffset']?.toString() ?? '') ??
        index * _fileChunkBytes;
    await handle.setPosition(byteOffset);
    await handle.writeFrom(bytes);
    _pendingFileChunkCounts[transferId] = count;
    final indexes = _pendingFileChunkIndexes.putIfAbsent(
      transferId,
      () => <int>{},
    );
    indexes.add(index);
    _emit('file_progress', <String, dynamic>{
      'transferId': transferId,
      'received': indexes.length,
      'total': count,
    });
    await _tryCompleteFile(transferId, sender, senderName, source);
  }

'''
new_complete = r'''  Future<void> _tryCompleteFile(
    String transferId,
    String sender,
    String senderName,
    String source,
  ) async {
    final manifest = _pendingFileManifests[transferId];
    final indexes = _pendingFileChunkIndexes[transferId];
    final count = _pendingFileChunkCounts[transferId] ?? 0;
    final partPath = _pendingFilePaths[transferId];
    final handle = _pendingFileHandles[transferId];
    if (manifest == null ||
        indexes == null ||
        count <= 0 ||
        indexes.length < count ||
        partPath == null ||
        handle == null) {
      return;
    }

    try {
      await handle.flush();
      await handle.close();
    } catch (_) {}
    _pendingFileHandles.remove(transferId);

    final rawAttachment = manifest['attachment'];
    if (rawAttachment is! Map) return;
    final attachment = Map<String, dynamic>.from(rawAttachment);
    final part = File(partPath);
    var finalPath = partPath;
    try {
      final root = part.parent;
      final name = _safeIncomingName(
        attachment['name']?.toString() ?? 'file',
      );
      final target = File(
        '${root.path}/${_safeIncomingName(transferId)}_$name',
      );
      if (await target.exists()) await target.delete();
      final renamed = await part.rename(target.path);
      finalPath = renamed.path;
    } catch (_) {}
    attachment
      ..remove('dataBase64')
      ..remove('path')
      ..['localPath'] = finalPath;
    manifest['attachment'] = attachment;
    final rawMeta = manifest['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};
    meta['fileReady'] = true;
    manifest['meta'] = meta;

    _pendingFileManifests.remove(transferId);
    _pendingFileChunkIndexes.remove(transferId);
    _pendingFileChunkCounts.remove(transferId);
    _pendingFilePaths.remove(transferId);
    _rememberMessage(_sanitizeMessage(manifest));
    _emitMessage(manifest, sender, senderName, source);
  }

'''
replace_block(
    'lib/internet_core.dart',
    '  void _tryCompleteFile(',
    '  Future<void> sendMessage(Map<String, dynamic> message) async {',
    file_receive_helpers + new_complete,
)

send_message = r'''  Future<void> sendMessage(Map<String, dynamic> message) async {
    _rememberLocalFile(message);
    _rememberMessage(_sanitizeMessage(message));

    final filePath = _filePathFor(message);
    if (filePath != null && filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) {
        await _sendFileFromDisk(message, file);
        return;
      }
    }

    final payload = _filePayloadFor(message);
    if (payload == null || payload.length <= _inlineFileChars) {
      await _sendEnvelope('message', <String, dynamic>{'message': message});
      return;
    }
    await _sendLargeFileMessage(message, payload);
  }

  Future<void> _sendFileFromDisk(
    Map<String, dynamic> message,
    File file,
  ) async {
    final messageId = message['id']?.toString() ?? CgIds.random(20);
    final size = await file.length();
    if (size == 0) {
      await _sendEnvelope('message', <String, dynamic>{'message': message});
      return;
    }
    final transferId = 'file_${messageId}_$size';
    final count = (size / _fileChunkBytes).ceil();
    final manifest = _sanitizeMessage(message);
    final rawMeta = manifest['meta'];
    manifest['meta'] = <String, dynamic>{
      if (rawMeta is Map) ...Map<String, dynamic>.from(rawMeta),
      'fileTransferId': transferId,
      'fileChunkCount': count,
      'fileReady': false,
      'fileSize': size,
      'fileChunkBytes': _fileChunkBytes,
    };
    await _sendEnvelope('message', <String, dynamic>{'message': manifest});

    final input = await file.open(mode: FileMode.read);
    try {
      for (var index = 0; index < count; index++) {
        final bytes = await input.read(_fileChunkBytes);
        await _sendEnvelope('file_chunk', <String, dynamic>{
          'transferId': transferId,
          'messageId': messageId,
          'index': index,
          'count': count,
          'byteOffset': index * _fileChunkBytes,
          'chunk': base64Encode(bytes),
        });
      }
    } finally {
      await input.close();
    }
  }

'''
replace_block(
    'lib/internet_core.dart',
    '  Future<void> sendMessage(Map<String, dynamic> message) async {',
    '  Future<void> _sendLargeFileMessage(',
    send_message,
)

file_path_helper = r'''  String? _filePathFor(Map<String, dynamic> message) {
    final rawAttachment = message['attachment'];
    if (rawAttachment is! Map) return null;
    final path = rawAttachment['localPath']?.toString() ??
        rawAttachment['path']?.toString();
    return path?.isNotEmpty == true ? path : null;
  }

'''
replace_once(
    'lib/internet_core.dart',
    '  String? _filePayloadFor(Map<String, dynamic> message) {\n',
    file_path_helper + '  String? _filePayloadFor(Map<String, dynamic> message) {\n',
)

replace_once(
    'lib/internet_core.dart',
    r'''      if (!_configured) {
        final relay = _publicRelay;
        if (relay == null || !relay.connected) {
          await _connectPublicRelay();
        }
        final sent = await _publicRelay?.publish(
              outer,
              retain: envelope.kind == 'history',
            ) ??
            false;
        if (sent) {
          _emit('status', const <String, dynamic>{
            'state': 'connected',
            'transport': 'public_mqtt',
          });
        } else {
          _scheduleReconnect();
        }
        return sent;
      }
''',
    r'''      if (!_configured) {
        final relay = _publicRelay;
        if (relay == null || !relay.connected) {
          unawaited(_connectPublicRelay());
          _emit('status', const <String, dynamic>{
            'state': 'queued',
            'transport': 'public_mqtt',
          });
          _scheduleReconnect();
          return false;
        }
        final sent = await relay.publish(
          outer,
          retain: envelope.kind == 'history',
        );
        if (sent) {
          _emit('status', const <String, dynamic>{
            'state': 'connected',
            'transport': 'public_mqtt',
          });
        } else {
          _scheduleReconnect();
        }
        return sent;
      }
''',
)

replace_once(
    'lib/internet_core.dart',
    '    await _publicRelay?.close();\n'
    '    try {\n'
    '      await _socket?.close();\n',
    '    await _publicRelay?.close();\n'
    '    for (final handle in _pendingFileHandles.values) {\n'
    '      try {\n'
    '        await handle.close();\n'
    '      } catch (_) {}\n'
    '    }\n'
    '    _pendingFileHandles.clear();\n'
    '    try {\n'
    '      await _socket?.close();\n',
)

print('Chernogram stability/update patch 0.83 applied')
