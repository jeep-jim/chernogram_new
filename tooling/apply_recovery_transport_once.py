from pathlib import Path
import re


def patch(path: str, transform) -> bool:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    updated = transform(source)
    if updated == source:
        return False
    file.write_text(updated, encoding='utf-8')
    print(f'Patched {path}')
    return True


def internet_core(source: str) -> str:
    source = source.replace(
        """  static const List<String> relayHosts = <String>[
    'ntfy.sh',
    'ntfy.jae.fi',
    'ntfy.adminforge.de',
    'ntfy.envs.net',
  ];""",
        """  // Temporary recovery transport. Keep one primary and one hot standby;
  // broadcasting every packet to four public services caused radio load,
  // duplicate cache replays and long UI stalls on Android.
  static const List<String> relayHosts = <String>[
    'ntfy.sh',
    'ntfy.jae.fi',
  ];""",
    )
    source = source.replace("'since': '30s'", "'since': '2m'")
    source = source.replace(
        "final selected = hosts.take(4).toList(growable: false);",
        "final selected = hosts.take(2).toList(growable: false);",
    )
    source = source.replace(
        "if (backup != null && kind != 'presence') {",
        "if (backup != null && kind != 'presence' && !fastPacket) {",
    )
    source = source.replace(
        ").timeout(const Duration(seconds: 6));",
        ").timeout(timeout);",
    )
    return source


def background_service(source: str) -> str:
    source = source.replace('      autoStart: true,', '      autoStart: false,')
    source = source.replace('      autoStartOnBoot: true,', '      autoStartOnBoot: false,')
    source = source.replace(
        '  await service.startService();\n',
        "  // Recovery build: do not start a second Flutter isolate automatically.\n"
        "  // Foreground chat/calls use the main process only while the new push/Telecom\n"
        "  // background path is being built.\n",
    )
    return source


def main_diagnostics(source: str) -> str:
    marker = "      await ChernogramCrashReporter.breadcrumb('runApp');\n"
    if marker in source and 'recovery foreground-only transport' not in source:
        source = source.replace(
            marker,
            "      await ChernogramCrashReporter.breadcrumb(\n"
            "        'recovery foreground-only transport; background isolate disabled',\n"
            "      );\n" + marker,
            1,
        )
    return source


def metadata(source: str) -> str:
    return re.sub(
        r'^version:\s*0\.16\.9\+40\s*$',
        'version: 0.16.10+41',
        source,
        count=1,
        flags=re.M,
    )


changed = False
changed |= patch('lib/internet_core.dart', internet_core)
changed |= patch('lib/background_realtime_service.dart', background_service)
changed |= patch('lib/main.dart', main_diagnostics)
changed |= patch('pubspec.yaml', metadata)
print('Recovery transport applied' if changed else 'Recovery transport already applied')
