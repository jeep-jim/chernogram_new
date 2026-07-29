from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")
    if "CgMessage? _replyingTo;" not in text:
        anchor = "  bool _sendingFile = false;\n  bool _hasText = false;\n"
        if anchor not in text:
            raise RuntimeError("chat reply state anchor not found")
        text = text.replace(
            anchor,
            anchor + "  CgMessage? _replyingTo;\n",
            1,
        )
        path.write_text(text, encoding="utf-8")
    print("Reply state prepared")


if __name__ == "__main__":
    main()
