from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:220]!r}')
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


# 0.87: startup safety + Android updater rollback to the proven ota_update
# plugin. MQTT/WebRTC transport is intentionally untouched.
replace_once('pubspec.yaml', 'version: 0.86.0+86', 'version: 0.87.0+87')

# Never block the first Flutter frame on optional background/tray integrations.
# A plugin failure must not be able to close the app during startup.
replace_once(
    'lib/main.dart',
    '''Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(chernogramFirebaseBackgroundHandler);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (Platform.isWindows) await CgDesktopRuntime.initialize();
  if (Platform.isAndroid) await CgBackgroundRuntime.initialize();
  runApp(const ChernogramApp());
  CgBackgroundRuntime.setAppVisible(true);
  unawaited(CgPushService.initialize());
}
''',
    '''Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(chernogramFirebaseBackgroundHandler);
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (_) {}
  if (Platform.isWindows) {
    try {
      await CgDesktopRuntime.initialize();
    } catch (_) {}
  }
  runApp(const ChernogramApp());

  // Non-critical integrations start only after the UI is alive. Android OEMs
  // differ a lot in foreground-service and notification behavior; none of
  // those differences may prevent Chernogram from opening.
  unawaited(() async {
    if (Platform.isAndroid) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await CgBackgroundRuntime.initialize();
        CgBackgroundRuntime.setAppVisible(true);
      } catch (_) {}
    }
    try {
      await CgPushService.initialize();
    } catch (_) {}
  }());
}
''',
)

# Go back to the updater implementation that already opened Android's package
# installer successfully. The previous failure was the rotating APK signature,
# not ota_update itself. 0.85+ now has a pinned release certificate.
update_service = Path('lib/update_service.dart')
text = update_service.read_text(encoding='utf-8')
if "import 'package:ota_update/ota_update.dart';\n" not in text:
    marker = "import 'package:http/http.dart' as http;\n"
    if marker not in text:
        raise SystemExit('http import anchor missing in update_service.dart')
    text = text.replace(marker, marker + "import 'package:ota_update/ota_update.dart';\n", 1)
    update_service.write_text(text, encoding='utf-8')

android_updater = '''  static Future<void> _downloadAndInstallAndroid(
    BuildContext context,
    RemoteUpdate update, {
    required bool ru,
  }) async {
    if (_installing) return;
    _installing = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>(
      ru ? 'Скачиваем обновление…' : 'Downloading update…',
    );
    var dialogOpen = true;
    StreamSubscription<OtaEvent>? subscription;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (navigator.canPop()) navigator.pop();
    }

    void message(String text) {
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 14), content: Text(text)),
      );
    }

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(ru ? 'Обновление Чернограма' : 'Updating Chernogram'),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, __) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(value: value <= 0 ? null : value / 100),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: status,
                    builder: (_, text, __) => Text(text),
                  ),
                  if (value > 0) ...<Widget>[
                    const SizedBox(height: 8),
                    Text('${value.toStringAsFixed(0)}%'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final stream = update.sha256.isEmpty
          ? OtaUpdate().execute(
              update.apkUrl,
              destinationFilename: 'chernogram-android-${update.versionName}.apk',
            )
          : OtaUpdate().execute(
              update.apkUrl,
              destinationFilename: 'chernogram-android-${update.versionName}.apk',
              sha256checksum: update.sha256,
            );
      final completed = Completer<void>();
      subscription = stream.listen(
        (event) {
          final name = event.status.toString().split('.').last;
          if (name == 'DOWNLOADING') {
            progress.value =
                (double.tryParse(event.value ?? '') ?? 0).clamp(0, 100).toDouble();
            status.value = ru
                ? 'Скачиваем новую версию…'
                : 'Downloading the new version…';
            return;
          }
          if (name == 'INSTALLING' || name == 'INSTALLATION_DONE') {
            closeDialog();
            if (!completed.isCompleted) completed.complete();
            return;
          }
          if (name.contains('ERROR')) {
            closeDialog();
            message(
              ru
                  ? 'Android не смог открыть установку обновления ($name).'
                  : 'Android could not open the update installer ($name).',
            );
            if (!completed.isCompleted) completed.complete();
          }
        },
        onError: (Object error) {
          closeDialog();
          message(
            ru
                ? 'Ошибка загрузки обновления: $error'
                : 'Update download failed: $error',
          );
          if (!completed.isCompleted) completed.complete();
        },
        onDone: () {
          if (!completed.isCompleted) completed.complete();
        },
      );
      await completed.future.timeout(const Duration(minutes: 8));
    } catch (error) {
      closeDialog();
      message(
        ru
            ? 'Не удалось запустить обновление: $error'
            : 'Could not start the update: $error',
      );
    } finally {
      await subscription?.cancel();
      progress.dispose();
      status.dispose();
      _installing = false;
    }
  }

'''
replace_block(
    'lib/update_service.dart',
    '  static Future<void> _downloadAndInstallAndroid(',
    '  static Future<void> _downloadAndInstallWindows(',
    android_updater,
)

# Remove the custom 0.86 Android installer hook entirely. Keeping Android's
# activity minimal eliminates another possible OEM-specific startup failure.
main_activity = Path('android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt')
main_activity.write_text('''package com.example.chernogram

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
            if (call.method == "getStorageStats") {
                val stat = StatFs(Environment.getDataDirectory().path)
                result.success(
                    mapOf(
                        "freeBytes" to stat.availableBytes,
                        "totalBytes" to stat.totalBytes
                    )
                )
            } else {
                result.notImplemented()
            }
        }
    }

    private fun playNotificationSound() {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        RingtoneManager.getRingtone(applicationContext, uri)?.play()
    }

    private fun startIncomingCallSound() {
        stopIncomingCallSound()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        incomingRingtone = RingtoneManager.getRingtone(applicationContext, uri)?.also { ringtone ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone.isLooping = true
            }
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

manifest = Path('android/app/src/main/AndroidManifest.xml')
manifest_text = manifest.read_text(encoding='utf-8')
custom_provider = '''        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/update_filepaths" />
        </provider>

'''
if custom_provider in manifest_text:
    manifest_text = manifest_text.replace(custom_provider, '', 1)
manifest.write_text(manifest_text, encoding='utf-8')

print('Android startup/OTA stability patch 0.87 applied')
