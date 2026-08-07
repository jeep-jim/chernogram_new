import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class RemoteUpdate {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String windowsUrl;
  final String sha256;
  final String windowsSha256;
  final String notesRu;
  final String notesEn;

  const RemoteUpdate({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.windowsUrl,
    required this.sha256,
    required this.windowsSha256,
    required this.notesRu,
    required this.notesEn,
  });

  factory RemoteUpdate.fromJson(Map<String, dynamic> json) => RemoteUpdate(
        versionName: json['versionName']?.toString() ?? '0.0.0',
        versionCode: int.tryParse(json['versionCode']?.toString() ?? '') ?? 0,
        apkUrl: json['apkUrl']?.toString() ?? '',
        windowsUrl: json['windowsUrl']?.toString() ?? '',
        sha256: json['sha256']?.toString() ?? '',
        windowsSha256: json['windowsSha256']?.toString() ?? '',
        notesRu: json['notesRu']?.toString() ?? '',
        notesEn: json['notesEn']?.toString() ?? '',
      );
}

class ChernogramUpdater {
  static const List<String> _manifestUrls = <String>[
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-room-alpha/update.json',
    'https://raw.githubusercontent.com/jeep-jim/chernogram_new/rebuild/minimal-room-chat-081/update-room-alpha.json',
  ];

  static bool _checking = false;
  static bool _installing = false;
  static DateTime? _lastAutomaticCheck;

  static bool get _supported => Platform.isAndroid || Platform.isWindows;

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  static Future<RemoteUpdate?> checkForUpdate() async {
    if (!_supported) return null;
    Object? lastError;
    RemoteUpdate? newest;

    for (final baseUrl in _manifestUrls) {
      try {
        final separator = baseUrl.contains('?') ? '&' : '?';
        final response = await http
            .get(
              Uri.parse(
                '$baseUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}',
              ),
              headers: const <String, String>{
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw HttpException('Update server returned ${response.statusCode}');
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) {
          throw const FormatException('Invalid update manifest');
        }
        final remote = RemoteUpdate.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        final platformUrl = Platform.isAndroid
            ? remote.apkUrl
            : remote.windowsUrl;
        if (remote.versionCode <= 0 || platformUrl.isEmpty) {
          throw const FormatException('Incomplete update manifest');
        }
        if (newest == null || remote.versionCode > newest.versionCode) {
          newest = remote;
        }
      } catch (error) {
        lastError = error;
      }
    }

    if (newest == null) {
      throw lastError ?? const HttpException('No update source available');
    }
    final current = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(current.buildNumber) ?? 0;
    return newest.versionCode > currentCode ? newest : null;
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    required bool ru,
    bool manual = false,
  }) async {
    if (!_supported || _checking || _installing) return;
    if (!manual) {
      final last = _lastAutomaticCheck;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 8)) {
        return;
      }
      _lastAutomaticCheck = DateTime.now();
    }
    _checking = true;

    try {
      final update = await checkForUpdate();
      if (!context.mounted) return;
      if (update == null) {
        if (manual) {
          final current = await currentVersion();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ru
                    ? 'Установлена последняя версия: $current.'
                    : 'The latest version is installed: $current.',
              ),
            ),
          );
        }
        return;
      }

      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.system_update_alt_rounded, size: 38),
          title: Text(
            ru
                ? 'Доступна версия ${update.versionName}'
                : 'Version ${update.versionName} is available',
          ),
          content: Text(
            (ru ? update.notesRu : update.notesEn).trim().isEmpty
                ? (ru
                    ? 'Новая версия Чернограма готова.'
                    : 'A new Chernogram version is ready.')
                : (ru ? update.notesRu : update.notesEn),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(ru ? 'Позже' : 'Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.download_rounded),
              label: Text(ru ? 'Обновить' : 'Update'),
            ),
          ],
        ),
      );
      if (install != true || !context.mounted) return;
      if (Platform.isWindows) {
        await _downloadAndInstallWindows(context, update, ru: ru);
        return;
      }
      await _downloadAndInstallAndroid(context, update, ru: ru);
    } on TimeoutException {
      if (manual && context.mounted) {
        _showError(
          context,
          ru,
          ru
              ? 'Сервер обновлений не ответил.'
              : 'The update server did not respond.',
        );
      }
    } catch (error) {
      if (manual && context.mounted) {
        _showError(
          context,
          ru,
          ru
              ? 'Не удалось проверить обновления: $error'
              : 'Could not check for updates: $error',
        );
      }
    } finally {
      _checking = false;
    }
  }

  static Future<void> _downloadAndInstallAndroid(
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
      ru ? 'Подготовка обновления…' : 'Preparing the update…',
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
        SnackBar(duration: const Duration(seconds: 10), content: Text(text)),
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
                  const SizedBox(height: 14),
                  ValueListenableBuilder<String>(
                    valueListenable: status,
                    builder: (_, text, __) => Text(text),
                  ),
                  if (value > 0) ...<Widget>[
                    const SizedBox(height: 6),
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
              destinationFilename: 'chernogram-room-${update.versionCode}.apk',
            )
          : OtaUpdate().execute(
              update.apkUrl,
              destinationFilename: 'chernogram-room-${update.versionCode}.apk',
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
                  ? 'Не удалось установить обновление ($name).'
                  : 'The update could not be installed ($name).',
            );
            if (!completed.isCompleted) completed.complete();
          }
        },
        onError: (Object error) {
          closeDialog();
          message(
            ru
                ? 'Ошибка скачивания обновления: $error'
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

  static Future<void> _downloadAndInstallWindows(
    BuildContext context,
    RemoteUpdate update, {
    required bool ru,
  }) async {
    if (_installing) return;
    _installing = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (navigator.canPop()) navigator.pop();
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
                  Text(
                    ru
                        ? 'Скачиваем и установим автоматически. Чернограм сам перезапустится.'
                        : 'Downloading and installing automatically. Chernogram will restart itself.',
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
      final tempRoot = await Directory.systemTemp.createTemp('chernogram_update_');
      final zip = File('${tempRoot.path}/chernogram-room-windows.zip');
      final request = http.Request('GET', Uri.parse(update.windowsUrl));
      request.headers['Cache-Control'] = 'no-cache';
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(
          const Duration(seconds: 20),
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
              progress.value = (received * 100 / length).clamp(0, 100).toDouble();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }

      if (update.windowsSha256.isNotEmpty) {
        final digest = await crypto.sha256.bind(zip.openRead()).first;
        if (digest.toString().toLowerCase() !=
            update.windowsSha256.toLowerCase()) {
          throw const FormatException('Windows update checksum mismatch');
        }
      }

      final executable = File(Platform.resolvedExecutable);
      final installDir = executable.parent.path;
      final exeName = executable.uri.pathSegments.isEmpty
          ? 'chernogram.exe'
          : executable.uri.pathSegments.last;
      final stage = '${tempRoot.path}/stage';
      final script = File('${tempRoot.path}/apply_update.ps1');
      String quote(String value) => "'${value.replaceAll("'", "''")}'";
      await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
\$pidToWait = $pid
while (Get-Process -Id \$pidToWait -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 300
}
\$zip = ${quote(zip.path)}
\$stage = ${quote(stage)}
\$dest = ${quote(installDir)}
\$exe = ${quote(exeName)}
if (Test-Path -LiteralPath \$stage) {
  Remove-Item -LiteralPath \$stage -Recurse -Force
}
New-Item -ItemType Directory -Path \$stage -Force | Out-Null
Expand-Archive -LiteralPath \$zip -DestinationPath \$stage -Force
Get-ChildItem -LiteralPath \$stage -Force | ForEach-Object {
  Copy-Item -LiteralPath \$_.FullName -Destination \$dest -Recurse -Force
}
Start-Process -FilePath (Join-Path \$dest \$exe)
Start-Sleep -Seconds 1
Remove-Item -LiteralPath ${quote(tempRoot.path)} -Recurse -Force -ErrorAction SilentlyContinue
''');

      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
        ],
        mode: ProcessStartMode.detached,
      );
      closeDialog();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      exit(0);
    } catch (error) {
      closeDialog();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(
            ru
                ? 'Не удалось установить обновление: $error'
                : 'Could not install the update: $error',
          ),
        ),
      );
    } finally {
      progress.dispose();
      _installing = false;
    }
  }

  static void _showError(BuildContext context, bool ru, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: ru ? 'Повторить' : 'Retry',
          onPressed: () => checkAndPrompt(context, ru: ru, manual: true),
        ),
      ),
    );
  }
}
