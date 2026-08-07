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


# Version and direct ZIP extraction dependency. No transport code is changed.
replace_once('pubspec.yaml', 'version: 0.85.0+85', 'version: 0.86.0+86')
if '  archive: ^4.0.7\n' not in Path('pubspec.yaml').read_text(encoding='utf-8'):
    replace_once(
        'pubspec.yaml',
        '  crypto: ^3.0.6\n',
        '  crypto: ^3.0.6\n  archive: ^4.0.7\n',
    )

replace_once(
    'lib/update_service.dart',
    "import 'package:crypto/crypto.dart' as crypto;\n",
    "import 'package:archive/archive.dart';\n"
    "import 'package:crypto/crypto.dart' as crypto;\n"
    "import 'package:flutter/services.dart';\n"
    "import 'package:path_provider/path_provider.dart';\n",
)

android_updater = r'''  static Future<void> _downloadAndInstallAndroid(
    BuildContext context,
    RemoteUpdate update, {
    required bool ru,
  }) async {
    if (_installing) return;
    _installing = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>(
      ru ? 'Скачиваем обновление…' : 'Downloading update…',
    );
    var dialogOpen = true;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (navigator.canPop()) navigator.pop();
    }

    try {
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

      final temp = await getTemporaryDirectory();
      final apk = File(
        '${temp.path}${Platform.pathSeparator}chernogram-${update.versionCode}.apk',
      );
      if (await apk.exists()) await apk.delete();

      final request = http.Request('GET', Uri.parse(update.apkUrl));
      request.headers['Cache-Control'] = 'no-cache, no-store';
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(
          const Duration(seconds: 25),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('Android update HTTP ${response.statusCode}');
        }
        final length = response.contentLength ?? -1;
        var received = 0;
        final sink = apk.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (length > 0) {
              progress.value = (received * 90 / length).clamp(0, 90).toDouble();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }

      status.value = ru ? 'Проверяем подпись файла…' : 'Verifying package…';
      if (update.sha256.isNotEmpty) {
        final digest = await crypto.sha256.bind(apk.openRead()).first;
        if (digest.toString().toLowerCase() != update.sha256.toLowerCase()) {
          throw const FormatException('Android update checksum mismatch');
        }
      }
      progress.value = 96;
      status.value = ru
          ? 'Открываем системную установку…'
          : 'Opening Android installer…';

      const channel = MethodChannel('chernogram/update');
      final opened = await channel.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': apk.path},
      );
      if (opened != true) {
        throw const PlatformException(
          code: 'installer_not_opened',
          message: 'Android package installer was not opened',
        );
      }
      progress.value = 100;
      closeDialog();
    } on PlatformException catch (error) {
      closeDialog();
      final permission = error.code == 'install_permission_required';
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 14),
          content: Text(
            permission
                ? (ru
                    ? 'Разреши Чернограму установку приложений. После возврата установка продолжится автоматически.'
                    : 'Allow Chernogram to install apps. Installation will continue when you return.')
                : (ru
                    ? 'Не удалось открыть установку обновления: ${error.message ?? error.code}'
                    : 'Could not open update installer: ${error.message ?? error.code}'),
          ),
        ),
      );
    } catch (error) {
      closeDialog();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 14),
          content: Text(
            ru
                ? 'Не удалось подготовить обновление: $error'
                : 'Could not prepare update: $error',
          ),
        ),
      );
    } finally {
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

windows_updater = r'''  static Future<void> _downloadAndInstallWindows(
    BuildContext context,
    RemoteUpdate update, {
    required bool ru,
  }) async {
    if (_installing) return;
    _installing = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>(
      ru ? 'Скачиваем обновление…' : 'Downloading update…',
    );
    var dialogOpen = true;
    Directory? tempRoot;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (navigator.canPop()) navigator.pop();
    }

    try {
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

      tempRoot = await Directory.systemTemp.createTemp('chernogram_update_');
      final zip = File('${tempRoot.path}${Platform.pathSeparator}update.zip');
      final stage = Directory('${tempRoot.path}${Platform.pathSeparator}stage');
      await stage.create(recursive: true);

      final request = http.Request('GET', Uri.parse(update.windowsUrl));
      request.headers['Cache-Control'] = 'no-cache, no-store';
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(
          const Duration(seconds: 25),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('Windows update HTTP ${response.statusCode}');
        }
        final length = response.contentLength ?? -1;
        var received = 0;
        final sink = zip.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (length > 0) {
              progress.value = (received * 70 / length).clamp(0, 70).toDouble();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }

      status.value = ru ? 'Проверяем пакет…' : 'Verifying package…';
      if (update.windowsSha256.isNotEmpty) {
        final digest = await crypto.sha256.bind(zip.openRead()).first;
        if (digest.toString().toLowerCase() !=
            update.windowsSha256.toLowerCase()) {
          throw const FormatException('Windows update checksum mismatch');
        }
      }
      progress.value = 74;

      status.value = ru ? 'Распаковываем новую версию…' : 'Preparing new version…';
      final bytes = await zip.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      var extracted = 0;
      for (final entry in archive) {
        var name = entry.name.replaceAll('\\', '/');
        while (name.startsWith('./')) name = name.substring(2);
        if (name.isEmpty || name.startsWith('/') || name.contains('../')) {
          throw const FormatException('Unsafe path in Windows package');
        }
        final parts = name.split('/').where((part) => part.isNotEmpty).toList();
        final outPath = <String>[stage.path, ...parts].join(Platform.pathSeparator);
        if (entry.isFile) {
          final output = File(outPath);
          await output.parent.create(recursive: true);
          final content = entry.content;
          if (content is List<int>) {
            await output.writeAsBytes(content, flush: true);
          } else {
            throw const FormatException('Invalid file data in Windows package');
          }
        } else {
          await Directory(outPath).create(recursive: true);
        }
        extracted++;
        if (archive.isNotEmpty) {
          progress.value = 74 + (extracted * 20 / archive.length).clamp(0, 20);
        }
      }

      final executable = File(Platform.resolvedExecutable);
      final installDir = executable.parent;
      final exeName = executable.uri.pathSegments.isEmpty
          ? 'chernogram.exe'
          : executable.uri.pathSegments.last;
      final stagedExe = File('${stage.path}${Platform.pathSeparator}$exeName');
      if (!await stagedExe.exists() || await stagedExe.length() < 100 * 1024) {
        throw const FormatException('Prepared package has no Chernogram executable');
      }

      final bundledHelper = File(
        '${installDir.path}${Platform.pathSeparator}chernogram_updater.exe',
      );
      if (!await bundledHelper.exists()) {
        throw const FileSystemException('chernogram_updater.exe is missing');
      }
      final helper = File(
        '${tempRoot.path}${Platform.pathSeparator}chernogram_updater.exe',
      );
      await bundledHelper.copy(helper.path);

      progress.value = 98;
      status.value = ru ? 'Перезапускаем Чернограм…' : 'Restarting Chernogram…';
      await Process.start(
        helper.path,
        <String>[
          '$pid',
          stage.path,
          installDir.path,
          exeName,
        ],
        mode: ProcessStartMode.detached,
      );
      progress.value = 100;
      closeDialog();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      exit(0);
    } catch (error) {
      closeDialog();
      if (tempRoot != null) {
        try {
          if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
        } catch (_) {}
      }
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 15),
          content: Text(
            ru
                ? 'Не удалось установить обновление: $error'
                : 'Could not install update: $error',
          ),
        ),
      );
    } finally {
      progress.dispose();
      status.dispose();
      _installing = false;
    }
  }

'''
replace_block(
    'lib/update_service.dart',
    '  static Future<void> _downloadAndInstallWindows(',
    '  static void _showError(',
    windows_updater,
)

# Native Android installer: system confirmation stays mandatory, but the APK is
# downloaded and verified inside Chernogram and the permission screen resumes it.
main_activity = Path(
    'android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt'
)
text = main_activity.read_text(encoding='utf-8')
for old, new in [
    ('import android.content.Context\n', 'import android.content.Context\nimport android.content.Intent\n'),
    ('import android.media.Ringtone\n', 'import android.media.Ringtone\nimport android.net.Uri\n'),
    ('import android.provider.Settings\n', 'import android.provider.Settings\nimport androidx.core.content.FileProvider\nimport java.io.File\n'),
    ('    private var incomingRingtone: Ringtone? = null\n', '    private var incomingRingtone: Ringtone? = null\n    private var pendingUpdateApk: String? = null\n'),
]:
    if old not in text:
        raise SystemExit(f'MainActivity pattern missing: {old!r}')
    text = text.replace(old, new, 1)

anchor = '''        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/storage"
        ).setMethodCallHandler { call, result ->
'''
if anchor not in text:
    raise SystemExit('MainActivity storage channel anchor missing')
update_channel = '''        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/update"
        ).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank() || !File(path).exists()) {
                    result.error("apk_missing", "Downloaded APK is missing", null)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()) {
                    pendingUpdateApk = path
                    val settingsIntent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(settingsIntent)
                    result.error(
                        "install_permission_required",
                        "Install unknown apps permission is required",
                        null
                    )
                } else {
                    openPackageInstaller(path)
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }

'''
text = text.replace(anchor, update_channel + anchor, 1)

insert_before = '''    private fun playNotificationSound() {
'''
if insert_before not in text:
    raise SystemExit('MainActivity method anchor missing')
methods = '''    private fun openPackageInstaller(path: String) {
        val apk = File(path)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.update_provider",
            apk
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    override fun onResume() {
        super.onResume()
        val path = pendingUpdateApk ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()) {
            pendingUpdateApk = null
            if (File(path).exists()) openPackageInstaller(path)
        }
    }

'''
text = text.replace(insert_before, methods + insert_before, 1)
main_activity.write_text(text, encoding='utf-8')

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')
provider_anchor = '''        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
'''
if provider_anchor not in text:
    raise SystemExit('OTA provider anchor missing')
provider = '''        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/update_filepaths" />
        </provider>

'''
text = text.replace(provider_anchor, provider + provider_anchor, 1)
manifest.write_text(text, encoding='utf-8')

Path('android/app/src/main/res/xml/update_filepaths.xml').write_text(
    '''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="chernogram_update_cache" path="." />
</paths>
''',
    encoding='utf-8',
)

# Cover real Android phones that still run a 32-bit userspace as well as arm64.
gradle = Path('android/app/build.gradle.kts')
text = gradle.read_text(encoding='utf-8')
text = text.replace(
    'abiFilters += "arm64-v8a"',
    'abiFilters += listOf("arm64-v8a", "armeabi-v7a")',
)
gradle.write_text(text, encoding='utf-8')

print('Chernogram updater 0.86 applied: native Android install + native Windows helper')
