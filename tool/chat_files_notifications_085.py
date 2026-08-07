from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:280]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_block(path: str, start: str, end: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    start_at = text.find(start)
    if start_at < 0:
        raise SystemExit(f'Start not found in {path}: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End not found in {path}: {end!r}')
    file.write_text(text[:start_at] + new + text[end_at:], encoding='utf-8')


# ---------------------------------------------------------------------------
# Public/system Downloads/Чернограм folder on Android.
# Modern Android uses MediaStore, so no broad storage permission is required.
# ---------------------------------------------------------------------------
main_activity = r'''package com.example.chernogram

import android.content.ContentValues
import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URLConnection

class MainActivity : FlutterActivity() {
    private val channelName = "chernogram/sound"
    private var incomingRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playMessage" -> {
                    playNotificationSound()
                    vibrate(longArrayOf(0, 35))
                    result.success(null)
                }
                "startIncomingCall" -> {
                    startIncomingCallSound()
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
                "stopIncomingCall" -> {
                    stopIncomingCallSound()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/device"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getBindingId") {
                val androidId = Settings.Secure.getString(
                    contentResolver,
                    Settings.Secure.ANDROID_ID
                ) ?: "unknown-android"
                result.success("android|$androidId")
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageStats" -> {
                    val stat = StatFs(Environment.getDataDirectory().path)
                    result.success(
                        mapOf(
                            "freeBytes" to stat.availableBytes,
                            "totalBytes" to stat.totalBytes
                        )
                    )
                }
                "saveToDownloads" -> {
                    val rawName = call.argument<String>("name") ?: "file"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("missing_bytes", "File bytes are missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(saveToDownloads(rawName, bytes))
                    } catch (error: Throwable) {
                        result.error("save_failed", error.message ?: "save failed", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun safeFileName(value: String): String {
        val cleaned = value
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .trim()
        return if (cleaned.isBlank()) "file" else cleaned
    }

    private fun saveToDownloads(rawName: String, bytes: ByteArray): String {
        val name = safeFileName(rawName)
        val mime = URLConnection.guessContentTypeFromName(name) ?: "application/octet-stream"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/Чернограм"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values
            ) ?: error("Не удалось создать файл в Загрузках")
            try {
                contentResolver.openOutputStream(uri, "w")?.use { stream ->
                    stream.write(bytes)
                    stream.flush()
                } ?: error("Не удалось открыть файл для записи")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (error: Throwable) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            return "Загрузки/Чернограм/$name"
        }

        val root = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val folder = File(root, "Чернограм")
        if (!folder.exists()) folder.mkdirs()
        var target = File(folder, name)
        if (target.exists()) {
            val dot = name.lastIndexOf('.')
            val stem = if (dot > 0) name.substring(0, dot) else name
            val ext = if (dot > 0) name.substring(dot) else ""
            var index = 1
            while (target.exists()) {
                target = File(folder, "$stem ($index)$ext")
                index += 1
            }
        }
        target.writeBytes(bytes)
        return target.absolutePath
    }

    private fun playNotificationSound() {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        RingtoneManager.getRingtone(applicationContext, uri)?.play()
    }

    private fun startIncomingCallSound() {
        stopIncomingCallSound()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        incomingRingtone = RingtoneManager.getRingtone(applicationContext, uri)?.also { ringtone ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) ringtone.isLooping = true
            ringtone.play()
        }
    }

    private fun stopIncomingCallSound() {
        incomingRingtone?.stop()
        incomingRingtone = null
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        vibrator.cancel()
    }

    @Suppress("DEPRECATION")
    private fun vibrate(pattern: LongArray) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            vibrator.vibrate(pattern, -1)
        }
    }

    override fun onStop() {
        super.onStop()
        if (isFinishing) stopIncomingCallSound()
    }

    override fun onDestroy() {
        stopIncomingCallSound()
        super.onDestroy()
    }
}
'''
Path('android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt').write_text(
    main_activity,
    encoding='utf-8',
)

manifest = Path('android/app/src/main/AndroidManifest.xml')
manifest_text = manifest.read_text(encoding='utf-8')
permission = '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />\n'
if 'android.permission.WRITE_EXTERNAL_STORAGE' not in manifest_text:
    manifest_text = manifest_text.replace(
        '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n',
        '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n' + permission,
        1,
    )
manifest.write_text(manifest_text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Media store: every chat attachment gets a system-folder copy, and every
# attachment has an explicit Download button. Auto archive is de-duplicated by
# message id across restarts.
# ---------------------------------------------------------------------------
replace_once(
    'lib/chat_media.dart',
    "import 'package:share_plus/share_plus.dart';\n",
    "import 'package:share_plus/share_plus.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
)

replace_once(
    'lib/chat_media.dart',
    '''  static Future<void> share(CgAttachment attachment) async {
    final file = await ensureFile(attachment);
    if (file != null) {
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
    }
  }
}
''',
    r'''  static Future<void> share(CgAttachment attachment) async {
    final file = await ensureFile(attachment);
    if (file != null) {
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
    }
  }

  static const String _systemArchiveKey = 'cg_system_archive_v1';
  static Set<String>? _systemArchivedIds;

  static String _publicSafeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  static Future<Set<String>> _loadSystemArchiveIds() async {
    final cached = _systemArchivedIds;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_systemArchiveKey) ?? const <String>[])
        .toSet();
    _systemArchivedIds = ids;
    return ids;
  }

  static Future<void> _rememberSystemArchiveId(String id) async {
    if (id.isEmpty) return;
    final ids = await _loadSystemArchiveIds();
    if (!ids.add(id)) return;
    while (ids.length > 3000) {
      ids.remove(ids.first);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_systemArchiveKey, ids.toList(growable: false));
  }

  static Future<File> _uniquePublicFile(Directory directory, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = File('${directory.path}${Platform.pathSeparator}$name');
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$stem ($index)$ext',
      );
      index += 1;
    }
    return candidate;
  }

  static Future<String?> downloadToSystem(CgAttachment attachment) async {
    final source = await ensureFile(attachment);
    if (source == null || !await source.exists()) return null;
    final name = _publicSafeName(attachment.name);

    if (Platform.isAndroid) {
      try {
        return await _storageChannel.invokeMethod<String>(
          'saveToDownloads',
          <String, dynamic>{
            'name': name,
            'bytes': await source.readAsBytes(),
          },
        );
      } catch (_) {
        return null;
      }
    }

    try {
      final downloads = await getDownloadsDirectory();
      final base = downloads ?? await getApplicationDocumentsDirectory();
      final directory = Directory(
        '${base.path}${Platform.pathSeparator}Чернограм',
      );
      if (!await directory.exists()) await directory.create(recursive: true);
      final target = await _uniquePublicFile(directory, name);
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> archiveMessage(CgMessage message) async {
    if (message.deleted || message.attachment == null || message.id.isEmpty) {
      return;
    }
    final ids = await _loadSystemArchiveIds();
    if (ids.contains(message.id)) return;
    final saved = await downloadToSystem(message.attachment!);
    if (saved != null) await _rememberSystemArchiveId(message.id);
  }

  static Future<void> archiveTunnels(List<CgTunnel> tunnels) async {
    for (final tunnel in tunnels) {
      for (final message in tunnel.messages) {
        await archiveMessage(message);
      }
    }
  }
}
''',
)

inline_attachment = r'''class CgInlineAttachment extends StatefulWidget {
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
  void dispose() {
    unawaited(_audio.dispose());
    super.dispose();
  }

  Uint8List? get _bytes {
    final raw = widget.attachment.dataBase64;
    if (raw == null) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<File?> _ensure() async {
    if (_file != null && await _file!.exists()) return _file;
    if (mounted) setState(() => _loading = true);
    _file = await CgMediaStore.ensureFile(widget.attachment);
    if (mounted) setState(() => _loading = false);
    return _file;
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
          saved == null
              ? 'Не удалось сохранить файл'
              : 'Сохранено: $saved',
        ),
      ),
    );
  }

  Widget _withDownload(Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      child,
      const SizedBox(height: 3),
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

  Future<void> _open() async {
    final file = await _ensure();
    if (file == null || !mounted) return;
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

  @override
  Widget build(BuildContext context) {
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
    final attachment = widget.attachment;
    final bytes = _bytes;
    if (attachment.kind == 'image' && bytes != null) {
      return _withDownload(
        GestureDetector(
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => CgImageViewer(bytes: bytes, title: attachment.name),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 270, maxHeight: 360),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      );
    }
    if (attachment.kind == 'circle') {
      return _withDownload(_CgInlineCircle(fileFuture: _ensure()));
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
            children: [
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
                  children: [
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
        onTap: _loading ? null : _open,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 270,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                CgMediaStore.isVideo(attachment)
                    ? Icons.movie_outlined
                    : attachment.kind == 'archive'
                    ? Icons.folder_zip_outlined
                    : Icons.description_outlined,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

'''
replace_block(
    'lib/chat_media.dart',
    'class CgInlineAttachment extends StatefulWidget {',
    'class _CgInlineCircle extends StatefulWidget {',
    inline_attachment,
)

# Archive outgoing attachments immediately and incoming attachments as soon as
# they enter the local history. This does not touch text/control packets.
replace_once(
    'lib/chat_screen.dart',
    '''    _persist();
    _scrollToBottom();
  }

  Future<void> _deleteMessage''',
    '''    _persist();
    if (message.attachment != null) {
      unawaited(CgMediaStore.archiveMessage(message));
    }
    _scrollToBottom();
  }

  Future<void> _deleteMessage''',
)
replace_once(
    'lib/chat_screen.dart',
    '''      if (index < 0) {
        messages.add(incoming);
        changed = true;
        continue;
      }
''',
    '''      if (index < 0) {
        messages.add(incoming);
        unawaited(CgMediaStore.archiveMessage(incoming));
        changed = true;
        continue;
      }
''',
)
replace_once(
    'lib/app_monitor.dart',
    '''    if (index < 0) {
      messages.add(message);
      changed = true;
''',
    '''    if (index < 0) {
      messages.add(message);
      unawaited(CgMediaStore.archiveMessage(message));
      changed = true;
''',
)

# ---------------------------------------------------------------------------
# Tapping a tray/system notification opens exactly that room. Handles both
# plain roomKey payloads and JSON payloads produced by the Android background
# runtime. A cold-start tap is buffered until the home screen has loaded chats.
# ---------------------------------------------------------------------------
replace_once(
    'lib/push_service.dart',
    "import 'dart:async';\n",
    "import 'dart:async';\nimport 'dart:convert';\n",
)
replace_once(
    'lib/push_service.dart',
    '''  static final StreamController<CgPushEvent> _events =
      StreamController<CgPushEvent>.broadcast(sync: true);

  static bool _initialized = false;
''',
    '''  static final StreamController<CgPushEvent> _events =
      StreamController<CgPushEvent>.broadcast(sync: true);
  static final StreamController<String> _notificationTaps =
      StreamController<String>.broadcast(sync: true);

  static bool _initialized = false;
  static String? _pendingNotificationRoom;
''',
)
replace_once(
    'lib/push_service.dart',
    '''  static bool get configured => _firebaseConfigured;
  static String? get token => _token;
  static Stream<CgPushEvent> get events => _events.stream;

''',
    r'''  static bool get configured => _firebaseConfigured;
  static String? get token => _token;
  static Stream<CgPushEvent> get events => _events.stream;
  static Stream<String> get notificationTaps => _notificationTaps.stream;

  static String? _roomFromPayload(String? payload) {
    final value = payload?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          final room = decoded['tunnelId']?.toString() ??
              decoded['roomKey']?.toString() ??
              '';
          if (room.isNotEmpty) return room;
        }
      } catch (_) {}
    }
    return value;
  }

  static void _emitNotificationTap(String? payload) {
    final room = _roomFromPayload(payload);
    if (room == null || room.isEmpty) return;
    if (_notificationTaps.hasListener) {
      _notificationTaps.add(room);
    } else {
      _pendingNotificationRoom = room;
    }
  }

  static String? takePendingNotificationRoom() {
    final room = _pendingNotificationRoom;
    _pendingNotificationRoom = null;
    return room;
  }

''',
)
replace_once(
    'lib/push_service.dart',
    '''      await _notifications.initialize(settings: initialization);
    } catch (_) {}

    if (Platform.isAndroid) {
''',
    '''      await _notifications.initialize(
        settings: initialization,
        onDidReceiveNotificationResponse: (response) {
          _emitNotificationTap(response.payload);
        },
      );
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _emitNotificationTap(launch?.notificationResponse?.payload);
      }
    } catch (_) {}

    if (Platform.isAndroid) {
''',
)
replace_once(
    'lib/push_service.dart',
    '''    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _events.add(CgPushEvent.fromMessage(message));
    });
    final initial = await messaging.getInitialMessage();
    if (initial != null) _events.add(CgPushEvent.fromMessage(initial));
''',
    '''    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final event = CgPushEvent.fromMessage(message);
      _events.add(event);
      _emitNotificationTap(event.roomKey);
    });
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      final event = CgPushEvent.fromMessage(initial);
      _events.add(event);
      _emitNotificationTap(event.roomKey);
    }
''',
)

# Home screen owns room navigation, so notification taps are resolved here.
for import_line in [
    "import '../chat_media.dart';\n",
    "import '../desktop_runtime.dart';\n",
    "import '../push_service.dart';\n",
]:
    app = Path('lib/light/light_chat_app.dart')
    text = app.read_text(encoding='utf-8')
    if import_line not in text:
        text = text.replace("import '../chat_screen.dart';\n", "import '../chat_screen.dart';\n" + import_line, 1)
        app.write_text(text, encoding='utf-8')

replace_once(
    'lib/light/light_chat_app.dart',
    '''  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

''',
    '''  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<String>? _notificationTapSubscription;
  String? _pendingNotificationRoom;

''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }
''',
    '''  void initState() {
    super.initState();
    _notificationTapSubscription = CgPushService.notificationTaps.listen(
      (room) => unawaited(_openNotificationRoom(room)),
    );
    _pendingNotificationRoom = CgPushService.takePendingNotificationRoom();
    unawaited(_bootstrap());
  }
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''    unawaited(_syncMonitor());
    unawaited(_listenLinks());
  }

  Future<void> _listenLinks() async {
''',
    '''    unawaited(CgMediaStore.archiveTunnels(_chats));
    unawaited(_syncMonitor());
    unawaited(_listenLinks());
    final pendingRoom = _pendingNotificationRoom;
    if (pendingRoom != null) {
      _pendingNotificationRoom = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openNotificationRoom(pendingRoom));
      });
    }
  }

  Future<void> _openNotificationRoom(String roomId) async {
    final value = roomId.trim();
    if (value.isEmpty) return;
    if (_loading || _profile == null) {
      _pendingNotificationRoom = value;
      return;
    }
    final chat = _chats.where((item) => item.id == value).firstOrNull;
    if (chat == null || !mounted) return;
    await CgDesktopRuntime.instance.showWindow();
    if (!mounted) return;
    setState(() => _tab = 0);
    await _openChat(chat);
  }

  Future<void> _listenLinks() async {
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(ChernogramAppMonitor.stop());
''',
    '''  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(_notificationTapSubscription?.cancel());
    unawaited(ChernogramAppMonitor.stop());
''',
)

print('System chat files, download button, uncropped images and notification navigation applied')
