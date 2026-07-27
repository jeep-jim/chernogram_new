import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class WindowsRemoteUpdate {
  final String versionName;
  final String versionFull;
  final String portableUrl;
  final String portableSha256;

  const WindowsRemoteUpdate({
    required this.versionName,
    required this.versionFull,
    required this.portableUrl,
    required this.portableSha256,
  });

  factory WindowsRemoteUpdate.fromJson(Map<String, dynamic> json) {
    return WindowsRemoteUpdate(
      versionName: json['versionName']?.toString() ?? '0.0.0',
      versionFull: json['versionFull']?.toString() ?? '0.0.0+0',
      portableUrl: json['portableUrl']?.toString() ?? '',
      portableSha256: json['portableSha256']?.toString().toLowerCase() ?? '',
    );
  }
}

class ChernogramWindowsUpdater {
  static const List<String> _manifestUrls = <String>[
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-windows/windows-update.json',
  ];

  static bool _automaticCheckDone = false;
  static bool _checking = false;
  static bool _installing = false;

  static Future<WindowsRemoteUpdate?> checkForUpdate() async {
    if (!Platform.isWindows) return null;

    Object? lastError;
    WindowsRemoteUpdate? newest;

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
            .timeout(const Duration(seconds: 18));

        if (response.statusCode != 200) {
          throw HttpException(
            'Update server returned ${response.statusCode}',
          );
        }

        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) {
          throw const FormatException('Invalid Windows update manifest');
        }

        final remote = WindowsRemoteUpdate.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (remote.portableUrl.isEmpty || remote.versionName == '0.0.0') {
          throw const FormatException('Incomplete Windows update manifest');
        }

        if (newest == null ||
            _compareVersions(remote.versionFull, newest.versionFull) > 0) {
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
    final currentFull = '${current.version}+${current.buildNumber}';
    if (_compareVersions(newest.versionFull, currentFull) <= 0) return null;
    return newest;
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    required bool ru,
    bool manual = false,
  }) async {
    if (!Platform.isWindows || _checking || _installing) return;
    if (!manual && _automaticCheckDone) return;

    if (!manual) _automaticCheckDone = true;
    _checking = true;

    try {
      final update = await checkForUpdate();
      if (!context.mounted) return;

      if (update == null) {
        if (manual) {
          final current = await PackageInfo.fromPlatform();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ru
                    ? 'Установлена последняя версия: ${current.version}+${current.buildNumber}.'
                    : 'The latest version is installed: ${current.version}+${current.buildNumber}.',
              ),
            ),
          );
        }
        return;
      }

      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.system_update_alt_rounded, size: 38),
          title: Text(
            ru
                ? 'Доступно обновление ${update.versionName}'
                : 'Update ${update.versionName} is available',
          ),
          content: Text(
            ru
                ? 'Чернограм сам скачает обновление. Затем приложение закроется, заменит файлы и автоматически запустится снова.'
                : 'Chernogram will download the update, close, replace its files and start again automatically.',
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

      if (shouldInstall == true && context.mounted) {
        await _downloadAndRestart(context, update, ru: ru);
      }
    } on TimeoutException {
      if (manual && context.mounted) {
        _showError(
          context,
          ru ? 'Сервер обновлений не ответил.' : 'The update server did not respond.',
        );
      }
    } catch (error) {
      if (manual && context.mounted) {
        _showError(
          context,
          ru
              ? 'Не удалось проверить обновления: $error'
              : 'Could not check for updates: $error',
        );
      }
    } finally {
      _checking = false;
    }
  }

  static Future<void> _downloadAndRestart(
    BuildContext context,
    WindowsRemoteUpdate update, {
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
            title: Text(
              ru ? 'Обновление Чернограма' : 'Updating Chernogram',
            ),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, __) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: value <= 0 ? null : value / 100,
                  ),
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

    http.Client? client;
    IOSink? sink;
    File? zipFile;

    try {
      final temp = await getTemporaryDirectory();
      final safeVersion = update.versionFull.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      zipFile = File('${temp.path}${Platform.pathSeparator}chernogram-$safeVersion.zip');
      if (await zipFile.exists()) await zipFile.delete();

      status.value = ru ? 'Скачиваем новую версию…' : 'Downloading the new version…';
      client = http.Client();
      final request = http.Request('GET', Uri.parse(update.portableUrl));
      request.headers.addAll(const <String, String>{
        'Cache-Control': 'no-cache',
        'Accept': 'application/zip, application/octet-stream',
      });
      final response = await client.send(request).timeout(
            const Duration(seconds: 25),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Download server returned ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      sink = zipFile.openWrite();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress.value = (received * 100 / total).clamp(0, 100).toDouble();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (update.portableSha256.isNotEmpty) {
        status.value = ru ? 'Проверяем файл…' : 'Verifying the package…';
        final digest = await Sha256().hash(await zipFile.readAsBytes());
        final actual = digest.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        if (actual.toLowerCase() != update.portableSha256.toLowerCase()) {
          throw const FormatException('Update checksum does not match');
        }
      }

      progress.value = 100;
      status.value = ru
          ? 'Перезапускаем и устанавливаем…'
          : 'Restarting and installing…';

      final executable = File(Platform.resolvedExecutable);
      final installDirectory = executable.parent.path;
      final executableName = executable.uri.pathSegments.last;
      final script = File(
        '${temp.path}${Platform.pathSeparator}chernogram-install-$safeVersion.ps1',
      );
      await script.writeAsString(_windowsInstallScript, flush: true);

      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-AppProcessId',
          pid.toString(),
          '-ZipPath',
          zipFile.path,
          '-InstallDir',
          installDirectory,
          '-ExeName',
          executableName,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 700));
      closeDialog();
      exit(0);
    } catch (error) {
      closeDialog();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            ru
                ? 'Не удалось установить обновление: $error'
                : 'Could not install the update: $error',
          ),
        ),
      );
    } finally {
      await sink?.close();
      client?.close();
      progress.dispose();
      status.dispose();
      _installing = false;
    }
  }

  static int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final a = index < leftParts.length ? leftParts[index] : 0;
      final b = index < rightParts.length ? rightParts[index] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  static List<int> _versionParts(String value) {
    final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+(\d+))?')
        .firstMatch(value.trim());
    if (match == null) return const <int>[0, 0, 0, 0];
    return <int>[
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      int.tryParse(match.group(4) ?? '') ?? 0,
    ];
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(message),
      ),
    );
  }

  static const String _windowsInstallScript = r'''
param(
  [Parameter(Mandatory=$true)][int]$AppProcessId,
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][string]$ExeName
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path ([System.IO.Path]::GetTempPath()) 'chernogram-update.log'
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('chernogram-stage-' + [Guid]::NewGuid().ToString('N'))

try {
  "[$([DateTime]::UtcNow.ToString('o'))] Waiting for process $AppProcessId" | Set-Content -LiteralPath $logPath -Encoding UTF8
  Wait-Process -Id $AppProcessId -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 700

  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $stage -Force

  $copied = $false
  for ($attempt = 1; $attempt -le 20; $attempt++) {
    try {
      Get-ChildItem -LiteralPath $stage -Force | Copy-Item -Destination $InstallDir -Recurse -Force
      $copied = $true
      break
    }
    catch {
      Start-Sleep -Milliseconds 600
    }
  }

  if (-not $copied) {
    throw 'Could not replace application files.'
  }

  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue

  $newExe = Join-Path $InstallDir $ExeName
  if (-not (Test-Path -LiteralPath $newExe)) {
    throw "Updated executable was not found: $newExe"
  }

  "[$([DateTime]::UtcNow.ToString('o'))] Update completed" | Add-Content -LiteralPath $logPath -Encoding UTF8
  Start-Process -FilePath $newExe -WorkingDirectory $InstallDir
}
catch {
  $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
  $oldExe = Join-Path $InstallDir $ExeName
  if (Test-Path -LiteralPath $oldExe) {
    Start-Process -FilePath $oldExe -WorkingDirectory $InstallDir
  }
}
''';
}
