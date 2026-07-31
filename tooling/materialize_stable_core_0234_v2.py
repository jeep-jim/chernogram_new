from __future__ import annotations

import runpy
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tooling/materialize_stable_core_0234.py"
TEMP = ROOT / "tooling/.materialize_stable_core_0234_runtime.py"
WORKING_SERVERLESS_REF = "6847a3d4e6ade48ca139c6560c036540865b8bf8"


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


def _git_show(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{WORKING_SERVERLESS_REF}:{path}"],
        cwd=ROOT,
        text=True,
    )


def _restore_serverless_realtime_core() -> None:
    # Restore the exact chat and WebRTC core that was already verified in the
    # serverless 0.7.3-derived build. No private gateway, hosted backend or
    # production TURN deployment is required by the application.
    for path in (
        "lib/internet_core.dart",
        "lib/call_service.dart",
        "lib/app_monitor.dart",
    ):
        target = ROOT / path
        target.write_text(_git_show(path), encoding="utf-8")

    # The stable materializer adds a private gateway background service. Keep
    # the current UI/lifecycle code, but do not start that service at launch.
    main_path = ROOT / "lib/main.dart"
    main = main_path.read_text(encoding="utf-8")
    main = main.replace(
        "Future<void> main() async {\n"
        "  WidgetsFlutterBinding.ensureInitialized();\n"
        "  await initializeChernogramRealtimeService();\n"
        "  runApp(const ChernogramApp());\n"
        "}",
        "void main() {\n"
        "  WidgetsFlutterBinding.ensureInitialized();\n"
        "  runApp(const ChernogramApp());\n"
        "}",
        1,
    )
    main_path.write_text(main, encoding="utf-8")


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


def main() -> None:
    source = _patch_materializer_source(SOURCE.read_text(encoding="utf-8"))
    TEMP.write_text(source, encoding="utf-8")
    try:
        runpy.run_path(str(TEMP), run_name="__main__")
        _restore_serverless_realtime_core()
        _patch_generated_source()
    finally:
        TEMP.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
