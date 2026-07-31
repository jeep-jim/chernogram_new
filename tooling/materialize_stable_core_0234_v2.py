from __future__ import annotations

import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tooling/materialize_stable_core_0234.py"
TEMP = ROOT / "tooling/.materialize_stable_core_0234_runtime.py"


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")

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
    source = source.replace(async_marker, async_fix, 1)

    TEMP.write_text(source, encoding="utf-8")
    try:
        runpy.run_path(str(TEMP), run_name="__main__")
    finally:
        TEMP.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
