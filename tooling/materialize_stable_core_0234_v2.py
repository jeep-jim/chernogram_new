from __future__ import annotations

import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tooling/materialize_stable_core_0234.py"
TEMP = ROOT / "tooling/.materialize_stable_core_0234_runtime.py"


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    old = '''        source = replace_once(
            source,
            "import 'internet_core.dart';\\n",
            "import 'install_share_sheet.dart';\\n"
            "import 'internet_core.dart';\\n"
            "import 'public_file_index.dart';\\n",
            "product imports",
        )
'''
    new = '''        source = replace_once(
            source,
            "import 'permission_center.dart';\\n",
            "import 'install_share_sheet.dart';\\n"
            "import 'public_file_index.dart';\\n"
            "import 'permission_center.dart';\\n",
            "product imports",
        )
'''
    if old not in source:
        raise RuntimeError("product import patch block not found")
    source = source.replace(old, new, 1)
    TEMP.write_text(source, encoding="utf-8")
    try:
        runpy.run_path(str(TEMP), run_name="__main__")
    finally:
        TEMP.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
