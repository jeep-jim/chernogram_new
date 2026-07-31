from __future__ import annotations

import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tooling/materialize_stable_core_0234.py"
TEMP = ROOT / "tooling/.materialize_stable_core_0234_runtime.py"


def _patch_materializer_source(source: str) -> str:
    old_imports = '''        source = replace_once(
            source,
            "import 'internet_core.dart';\\n",
            "import 'install_share_sheet.dart';\\n"
            "import 'internet_core.dart';\\n"
            "import 'public_file_index.dart';\\n",
            "product imports",
        )
'''
    new_imports = '''        source = replace_once(
            source,
            "import 'permission_center.dart';\\n",
            "import 'install_share_sheet.dart';\\n"
            "import 'public_file_index.dart';\\n"
            "import 'permission_center.dart';\\n",
            "product imports",
        )
'''
    if old_imports not in source:
        raise RuntimeError("product import patch block not found")
    source = source.replace(old_imports, new_imports, 1)

    async_marker = '''    source = source.replace(
        "  static void _handleMessage(\\n",
        "  static Future<void> _handleMessage(\\n",
        1,
    )
'''
    async_fix = async_marker + '''    source = source.replace(
        "    required bool playSound,\\n  }) {",
        "    required bool playSound,\\n  }) async {",
        1,
    )
'''
    if async_marker not in source:
        raise RuntimeError("incoming message async marker not found")
    return source.replace(async_marker, async_fix, 1)


def _patch_generated_source() -> None:
    pubspec_path = ROOT / "pubspec.yaml"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    if "\n  test:" not in pubspec:
        anchor = "  flutter_lints: ^3.0.0\n"
        if anchor not in pubspec:
            raise RuntimeError("root dev dependency anchor not found")
        pubspec = pubspec.replace(
            anchor,
            anchor + "  test: ^1.25.15\n",
            1,
        )
        pubspec_path.write_text(pubspec, encoding="utf-8")

    client_path = ROOT / "lib/realtime_gateway_client.dart"
    client = client_path.read_text(encoding="utf-8")
    old_ack = '''    _sendFrame(<String, dynamic>{
      'type': 'ack',
      'protocol': 1,
      'roomId': event.roomId,
      'roomSeq': event.roomSeq,
    });
'''
    new_ack = '''    _sendFrame(<String, dynamic>{
      'type': 'event_ack',
      'protocol': 1,
      'packetId': event.packetId,
      'roomId': event.roomId,
      'roomSeq': event.roomSeq,
    });
'''
    if old_ack in client:
        client = client.replace(old_ack, new_ack, 1)
        client_path.write_text(client, encoding="utf-8")
    elif new_ack not in client:
        raise RuntimeError("recipient delivery ACK block not found")


def main() -> None:
    source = _patch_materializer_source(SOURCE.read_text(encoding="utf-8"))
    TEMP.write_text(source, encoding="utf-8")
    try:
        runpy.run_path(str(TEMP), run_name="__main__")
        _patch_generated_source()
    finally:
        TEMP.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
