#!/usr/bin/env python3
"""Small idempotent fixes applied after the main Jami 0.79 patch."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch(path: str, old: str, new: str, marker: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f"{path}: missing patch anchor {old!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


patch(
    "lib/jami_core.dart",
    """  static void install() {
    InternetRelay.preferredFactory = open;
  }""",
    """  static void install() {
    if (!Platform.isAndroid) return;
    InternetRelay.preferredFactory = open;
  }""",
    "if (!Platform.isAndroid) return;",
)

patch(
    "lib/core_models.dart",
    """      'owner': ownerId,
      'secret': secret,""",
    """      'owner': ownerId,
      'jamiOwner': jamiOwner,
      'secret': secret,""",
    "      'jamiOwner': jamiOwner,",
)

print("Jami 0.79 final integration fixes applied")
