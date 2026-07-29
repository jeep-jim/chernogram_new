from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    chat = ROOT / "lib" / "chat_screen.dart"
    source = chat.read_text(encoding="utf-8")
    old = """                    if (attachment != null)
                      _AttachmentPreview(
                        attachment: attachment,
                        hidden: privacyLens,
                      ),
"""
    new = """                    if (attachment != null)
                      CgInlineAttachment(
                        attachment: attachment,
                        hidden: privacyLens,
                      ),
"""
    if old in source:
        source = source.replace(old, new, 1)
    chat.write_text(source, encoding="utf-8")

    brand = ROOT / "lib" / "brand.dart"
    source = brand.read_text(encoding="utf-8")
    if "static const purple" not in source:
        source = source.replace(
            "  static const orange = violet;\n",
            "  static const purple = violet;\n  static const orange = violet;\n",
            1,
        )
    brand.write_text(source, encoding="utf-8")

    print("Android data-first compatibility finalized")


if __name__ == "__main__":
    main()
