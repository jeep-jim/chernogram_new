from pathlib import Path

path = Path('lib/update_service.dart')
text = path.read_text(encoding='utf-8')
start = text.find('      final expand = await Process.run(\n')
if start < 0:
    raise SystemExit('Windows Expand-Archive start not found')
end = text.find('      if (expand.exitCode != 0) {\n', start)
if end < 0:
    raise SystemExit('Windows Expand-Archive end not found')
new = r'''      final expandScript = File('${tempRoot.path}/expand_update.ps1');
      await expandScript.writeAsString('''
param([string]\$ZipPath, [string]\$StagePath)
\$ErrorActionPreference = 'Stop'
Expand-Archive -LiteralPath \$ZipPath -DestinationPath \$StagePath -Force
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
'''
path.write_text(text[:start] + new + text[end:], encoding='utf-8')
print('Windows updater extraction fix applied')
