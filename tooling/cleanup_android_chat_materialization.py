from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def dedupe_state(text: str) -> str:
    start = text.index("class _CgChatScreenState extends State<CgChatScreen>")
    end = text.index("  bool get _isOwner", start)
    section = text[start:end]
    lines = section.splitlines(keepends=True)
    seen_has_text = False
    cleaned: list[str] = []
    for line in lines:
        if line.strip() == "bool _hasText = false;":
            if seen_has_text:
                continue
            seen_has_text = True
        cleaned.append(line)
    return text[:start] + "".join(cleaned) + text[end:]


def dedupe_call_arguments(text: str) -> str:
    lines = text.splitlines(keepends=True)
    result: list[str] = []
    inside = False
    depth = 0
    seen: set[str] = set()
    for line in lines:
        if not inside and "ChernogramCallScreen(" in line:
            inside = True
            depth = line.count("(") - line.count(")")
            seen = set()
            result.append(line)
            continue
        if inside:
            stripped = line.strip()
            key = None
            if stripped.startswith("peerId:"):
                key = "peerId"
            elif stripped.startswith("peerName:"):
                key = "peerName"
            elif stripped.startswith("peerAvatarBase64:"):
                key = "peerAvatarBase64"
            if key is not None:
                if key in seen:
                    depth += line.count("(") - line.count(")")
                    if depth <= 0:
                        inside = False
                    continue
                seen.add(key)
            result.append(line)
            depth += line.count("(") - line.count(")")
            if depth <= 0:
                inside = False
            continue
        result.append(line)
    return "".join(result)


def main() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")
    text = dedupe_state(text)
    text = dedupe_call_arguments(text)
    path.write_text(text, encoding="utf-8")
    print("Android chat materialization duplicates removed")


if __name__ == "__main__":
    main()
