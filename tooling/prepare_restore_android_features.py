from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")
    marker = "class _LinkifiedMessageText extends StatefulWidget"
    bubble = "class _MessageBubble extends StatelessWidget"
    if marker in text:
        start = text.index(marker)
        end = text.index(bubble, start)
        text = text[:start] + text[end:]
        path.write_text(text, encoding="utf-8")
    print("Android feature restore prepared")


if __name__ == "__main__":
    main()
