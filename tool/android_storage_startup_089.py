from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:260]!r}')
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


# 0.89 fixes an Android-only startup regression introduced by the automatic
# system-downloads backfill. Transport routing (MQTT/WebRTC) is untouched.
replace_once('pubspec.yaml', 'version: 0.88.0+88', 'version: 0.89.0+89')

# Never walk and re-export the entire historic chat library during app startup.
# A large attachment used to be materialized and then read into one ByteArray,
# which can make Android kill the process for OOM immediately after opening.
replace_once(
    'lib/light/light_chat_app.dart',
    '    unawaited(CgMediaStore.archiveTunnels(_chats));\n',
    '',
)

# Android system-download saving is now path based. The native side streams the
# file to MediaStore, so there is no Dart ByteArray proportional to file size.
replace_once(
    'lib/chat_media.dart',
    '''        return await _storageChannel.invokeMethod<String>(
          'saveToDownloads',
          <String, dynamic>{
            'name': name,
            'bytes': await source.readAsBytes(),
          },
        );
''',
    '''        return await _storageChannel.invokeMethod<String>(
          'saveToDownloads',
          <String, dynamic>{
            'name': name,
            'sourcePath': source.path,
          },
        );
''',
)

# Serialize automatic archiving of newly arriving/sent attachments. There is no
# artificial size cap; each file is copied as a stream and only one archive copy
# runs at a time.
replace_block(
    'lib/chat_media.dart',
    '  static Future<void> archiveMessage(CgMessage message) async {',
    '  static Future<void> archiveTunnels(List<CgTunnel> tunnels) async {',
    '''  static Future<void> _archiveTail = Future<void>.value();

  static Future<void> archiveMessage(CgMessage message) {
    final task = _archiveTail.then((_) => _archiveMessageNow(message));
    _archiveTail = task.catchError((_) {});
    return task;
  }

  static Future<void> _archiveMessageNow(CgMessage message) async {
    if (message.deleted || message.attachment == null || message.id.isEmpty) {
      return;
    }
    final ids = await _loadSystemArchiveIds();
    if (ids.contains(message.id)) return;
    final saved = await downloadToSystem(message.attachment!);
    if (saved != null) await _rememberSystemArchiveId(message.id);
  }

''',
)

# Keep the public method for compatibility but intentionally do not backfill old
# history at launch. Existing files stay available through the explicit Download
# button; new files are archived automatically as they arrive.
replace_block(
    'lib/chat_media.dart',
    '  static Future<void> archiveTunnels(List<CgTunnel> tunnels) async {',
    "}\n\nclass CgInlineAttachment",
    '''  static Future<void> archiveTunnels(List<CgTunnel> tunnels) async {
    // Deliberately no startup backfill. See 0.89 Android startup fix.
  }
}\n\nclass CgInlineAttachment''',
)

# Restore a complete but inert-at-startup MainActivity. saveToDownloads accepts
# a local source path and copies it with streams instead of a giant MethodChannel
# ByteArray. No service is started from this activity.
Path('android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt').write_text(r'''package com.example.chernogram

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
    private val soundChannel = "chernogram/sound"
    private var incomingRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundChannel)
            .setMethodCallHandler { call, result ->
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
                    "startIncomingCallVibration" -> {
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chernogram/device")
            .setMethodCallHandler { call, result ->
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chernogram/storage")
            .setMethodCallHandler { call, result ->
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
                        val sourcePath = call.argument<String>("sourcePath")
                        if (sourcePath.isNullOrBlank()) {
                            result.error("missing_source", "Source file path is missing", null)
                            return@setMethodCallHandler
                        }
                        val source = File(sourcePath)
                        if (!source.isFile) {
                            result.error("missing_source", "Source file does not exist", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(rawName, source))
                        } catch (error: Throwable) {
                            result.error("save_failed", error.message ?: "save failed", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun safeFileName(value: String): String {
        val cleaned = value.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
        return if (cleaned.isBlank()) "file" else cleaned
    }

    private fun saveToDownloads(rawName: String, source: File): String {
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
                source.inputStream().buffered().use { input ->
                    contentResolver.openOutputStream(uri, "w")?.buffered()?.use { output ->
                        input.copyTo(output, 1024 * 1024)
                        output.flush()
                    } ?: error("Не удалось открыть файл для записи")
                }
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
        source.inputStream().buffered().use { input ->
            target.outputStream().buffered().use { output ->
                input.copyTo(output, 1024 * 1024)
                output.flush()
            }
        }
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
''', encoding='utf-8')

print('Android 0.89 startup/file streaming fix applied')
