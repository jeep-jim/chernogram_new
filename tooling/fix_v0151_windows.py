from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old in source:
        return source.replace(old, new, 1)
    if new in source:
        return source
    raise RuntimeError(f'Expected block was not found: {label}')


def patch_windows_updater() -> bool:
    path = Path('lib/windows_update_service.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    source = replace_once(
        source,
        """      final executable = File(Platform.resolvedExecutable);
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
 """,
        """      final executable = File(Platform.resolvedExecutable);
       final installDirectory = executable.parent.path;
       final executableName = executable.uri.pathSegments.last;
       final script = File(
         '${temp.path}${Platform.pathSeparator}chernogram-install-$safeVersion.cmd',
       );
       final readyFile = File(
         '${temp.path}${Platform.pathSeparator}chernogram-install-$safeVersion.ready',
       );
       final launcher = File(
         '${temp.path}${Platform.pathSeparator}chernogram-update-launcher-$safeVersion.vbs',
       );
       if (await readyFile.exists()) await readyFile.delete();
       await script.writeAsString(_windowsInstallScript, flush: true);

       final command = <String>[
         'cmd.exe',
         '/d',
         '/s',
         '/c',
         'call',
         _quoteWindowsArgument(script.path),
         pid.toString(),
         _quoteWindowsArgument(zipFile.path),
         _quoteWindowsArgument(installDirectory),
         _quoteWindowsArgument(executableName),
         _quoteWindowsArgument(readyFile.path),
       ].join(' ');
       final escapedCommand = command.replaceAll('"', '""');
       await launcher.writeAsString(
         'Set shell = CreateObject("WScript.Shell")\\r\\n'
         'shell.Run "$escapedCommand", 0, False\\r\\n'
         'CreateObject("Scripting.FileSystemObject").DeleteFile '
         'WScript.ScriptFullName, True\\r\\n',
         flush: true,
       );

       await Process.start(
         'wscript.exe',
         <String>['//B', '//Nologo', launcher.path],
         mode: ProcessStartMode.detached,
         runInShell: false,
       );

       var helperReady = false;
       for (var attempt = 0; attempt < 50; attempt++) {
         if (await readyFile.exists()) {
           helperReady = true;
           break;
         }
         await Future<void>.delayed(const Duration(milliseconds: 100));
       }
       if (!helperReady) {
         throw StateError('Windows updater helper did not start');
       }

       await Future<void>.delayed(const Duration(milliseconds: 250));
       closeDialog();
       exit(0);
 """,
        'Windows helper launch',
    )

    marker = "  static const String _windowsInstallScript = r'''"
    marker_index = source.find(marker)
    if marker_index < 0:
        raise RuntimeError('Windows updater script marker was not found')

    if 'static String _quoteWindowsArgument' not in source:
        helper = """  static String _quoteWindowsArgument(String value) {
    return '\"${value.replaceAll('\"', r'\\\"')}\"';
  }

"""
        source = source[:marker_index] + helper + source[marker_index:]
        marker_index = source.find(marker)

    new_script = r"""  static const String _windowsInstallScript = r'''@echo off
setlocal EnableExtensions

set "APP_PID=%~1"
set "ZIP_PATH=%~2"
set "INSTALL_DIR=%~3"
set "EXE_NAME=%~4"
set "READY_PATH=%~5"
set "ORIGINAL_INSTALL=%INSTALL_DIR%"
set "LOG_PATH=%TEMP%\chernogram-update.log"
set "STAGE=%TEMP%\chernogram-stage-%RANDOM%-%RANDOM%"

> "%READY_PATH%" echo ready
> "%LOG_PATH%" echo [%DATE% %TIME%] Windows updater started for PID %APP_PID%

:wait_for_app
tasklist /FI "PID eq %APP_PID%" /NH 2>NUL | findstr /R /C:"[ ]%APP_PID%[ ]" >NUL
if not errorlevel 1 (
  ping 127.0.0.1 -n 2 >NUL
  goto wait_for_app
)
ping 127.0.0.1 -n 2 >NUL

if exist "%STAGE%" rmdir /S /Q "%STAGE%" >NUL 2>&1
mkdir "%STAGE%" >>"%LOG_PATH%" 2>&1
if errorlevel 1 goto fail

where tar.exe >NUL 2>&1
if errorlevel 1 goto fail

tar.exe -xf "%ZIP_PATH%" -C "%STAGE%" >>"%LOG_PATH%" 2>&1
if errorlevel 1 goto fail

set "SOURCE=%STAGE%\app"
if exist "%SOURCE%\%EXE_NAME%" goto source_ready
set "SOURCE=%STAGE%"
if exist "%SOURCE%\%EXE_NAME%" goto source_ready
for /R "%STAGE%" %%F in (%EXE_NAME%) do set "SOURCE=%%~dpF"

:source_ready
if not exist "%SOURCE%\%EXE_NAME%" goto fail

for /L %%A in (1,1,30) do (
  robocopy "%SOURCE%" "%INSTALL_DIR%" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >>"%LOG_PATH%" 2>&1
  if errorlevel 8 (
    ping 127.0.0.1 -n 2 >NUL
  ) else (
    goto copied
  )
)
goto fail

:copied
if not exist "%INSTALL_DIR%\%EXE_NAME%" goto fail
del /Q "%ZIP_PATH%" >NUL 2>&1
rmdir /S /Q "%STAGE%" >NUL 2>&1
del /Q "%READY_PATH%" >NUL 2>&1
>>"%LOG_PATH%" echo [%DATE% %TIME%] Update completed
start "" /D "%INSTALL_DIR%" "%INSTALL_DIR%\%EXE_NAME%"
exit /B 0

:fail
>>"%LOG_PATH%" echo [%DATE% %TIME%] Update failed, restarting previous version
if exist "%ORIGINAL_INSTALL%\%EXE_NAME%" start "" /D "%ORIGINAL_INSTALL%" "%ORIGINAL_INSTALL%\%EXE_NAME%"
exit /B 1
''';
}
"""
    source = source[:marker_index] + new_script

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def apply_windows_fix() -> bool:
    return patch_windows_updater()
