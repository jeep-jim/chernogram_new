from pathlib import Path


def replace_block(path: str, start: str, end: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    start_at = text.find(start)
    if start_at < 0:
        raise SystemExit(f'Start not found: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End not found: {end!r}')
    file.write_text(text[:start_at] + new + text[end_at:], encoding='utf-8')


windows_updater = r"""  static Future<void> _downloadAndInstallWindows(
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

    Directory? tempRoot;
    try {
      tempRoot = await Directory.systemTemp.createTemp('chernogram_update_');
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
              progress.value = (received * 75 / length).clamp(0, 75).toDouble();
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
        status.value = ru ? 'Проверяем файл…' : 'Verifying file…';
        final digest = await crypto.sha256.bind(zip.openRead()).first;
        if (digest.toString().toLowerCase() !=
            update.windowsSha256.toLowerCase()) {
          throw const FormatException('Windows update checksum mismatch');
        }
      }
      progress.value = 80;

      final executable = File(Platform.resolvedExecutable);
      final installDir = executable.parent.path;
      final exeName = executable.uri.pathSegments.isEmpty
          ? 'chernogram.exe'
          : executable.uri.pathSegments.last;
      final stage = Directory('${tempRoot.path}/stage');
      if (await stage.exists()) await stage.delete(recursive: true);
      await stage.create(recursive: true);

      // Prepare everything before closing the running app. The detached helper
      // only copies verified files and restarts Chernogram after this PID exits.
      status.value = ru ? 'Подготавливаем новую версию…' : 'Preparing new version…';
      final expandScript = File('${tempRoot.path}/expand_update.ps1');
      await expandScript.writeAsString('''
param([string]$ZipPath, [string]$StagePath)
$ErrorActionPreference = 'Stop'
Expand-Archive -LiteralPath $ZipPath -DestinationPath $StagePath -Force
''');
      final expand = await Process.run(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          expandScript.path,
          zip.path,
          stage.path,
        ],
      ).timeout(const Duration(minutes: 2));
      if (expand.exitCode != 0) {
        throw ProcessException(
          'powershell.exe',
          const <String>[],
          'Expand-Archive failed: ${expand.stderr}',
          expand.exitCode,
        );
      }

      final stagedExe = File('${stage.path}${Platform.pathSeparator}$exeName');
      if (!await stagedExe.exists() || await stagedExe.length() < 100 * 1024) {
        throw const FormatException('Prepared Windows package has no executable');
      }
      progress.value = 95;
      status.value = ru ? 'Готово. Перезапускаем…' : 'Ready. Restarting…';

      final helper = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'chernogram_apply_${pid}_${DateTime.now().millisecondsSinceEpoch}.ps1',
      );
      final log =
          '${Directory.systemTemp.path}${Platform.pathSeparator}chernogram-update.log';
      String quote(String value) => "'${value.replaceAll("'", "''")}'";
      await helper.writeAsString('''
$ErrorActionPreference = 'Stop'
$pidToWait = $pid
$source = ${quote(stage.path)}
$dest = ${quote(installDir)}
$exe = ${quote(exeName)}
$log = ${quote(log)}
function Log([string]$text) {
  Add-Content -LiteralPath $log -Value ("[" + (Get-Date -Format s) + "] " + $text)
}
try {
  Log "Waiting for PID $pidToWait"
  for ($i = 0; $i -lt 120; $i++) {
    if (-not (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
  }
  if (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue) {
    throw "Old Chernogram process did not exit"
  }
  Log "Copying prepared update"
  Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
  }
  $target = Join-Path $dest $exe
  if (-not (Test-Path -LiteralPath $target)) {
    throw "Updated executable was not copied"
  }
  Log "Starting updated Chernogram"
  Start-Process -FilePath $target -WorkingDirectory $dest
  Log "Update completed"
} catch {
  Log ("ERROR: " + $_.Exception.Message)
  try {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
      "Не удалось завершить обновление Чернограма.`n`n" + $_.Exception.Message + "`n`nЖурнал: " + $log,
      "Чернограм — обновление"
    ) | Out-Null
  } catch {}
}
Start-Sleep -Milliseconds 800
Remove-Item -LiteralPath ${quote(tempRoot.path)} -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
''');

      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          helper.path,
        ],
        mode: ProcessStartMode.detached,
      );
      progress.value = 100;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      closeDialog();
      await Future<void>.delayed(const Duration(milliseconds: 250));
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
          duration: const Duration(seconds: 14),
          content: Text(
            ru
                ? 'Не удалось подготовить обновление: $error'
                : 'Could not prepare the update: $error',
          ),
        ),
      );
    } finally {
      progress.dispose();
      status.dispose();
      _installing = false;
    }
  }

"""

replace_block(
    'lib/update_service.dart',
    '  static Future<void> _downloadAndInstallWindows(',
    '  static void _showError(',
    windows_updater,
)

print('Reliable Windows updater 0.85 applied')
