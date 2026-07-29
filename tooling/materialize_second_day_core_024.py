from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "d696e470cb96e61a0e5cc29c9e335b5da5a8f69b"


def git_show(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{BASE}:{path}"],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
    )


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def restore_second_day_core() -> None:
    # These files formed the working message/call path on the second day.
    for path in (
        "lib/internet_core.dart",
        "lib/call_service.dart",
        "lib/app_monitor.dart",
    ):
        write(path, git_show(path))


def bump_version() -> None:
    path = ROOT / "pubspec.yaml"
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("version:"):
            lines[index] = "version: 0.24.0+56"
            break
    else:
        raise RuntimeError("pubspec version field not found")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    restore_second_day_core()
    bump_version()
    print(f"Second-day core {BASE} restored for Chernogram 0.24")


if __name__ == "__main__":
    main()
