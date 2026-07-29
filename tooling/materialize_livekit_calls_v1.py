from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(source: str, old: str, new: str, *, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return source.replace(old, new, 1)


def patch_pubspec() -> None:
    path = ROOT / "pubspec.yaml"
    source = path.read_text(encoding="utf-8")
    source = re.sub(
        r"(?m)^version:\s*0\.20\.0\+50\s*$",
        "version: 0.21.0+51",
        source,
        count=1,
    )
    if "  livekit_client:" not in source:
        source = replace_once(
            source,
            "  http: ^1.5.0\n",
            "  http: ^1.5.0\n  livekit_client: 2.8.1\n",
            label="pubspec dependency",
        )
    path.write_text(source, encoding="utf-8")


def patch_navigation() -> None:
    path = ROOT / "lib" / "v12.dart"
    source = path.read_text(encoding="utf-8")

    if "import 'livekit_test_screen.dart';" not in source:
        source = replace_once(
            source,
            "import 'group_call_service.dart';\n",
            "import 'group_call_service.dart';\nimport 'livekit_test_screen.dart';\n",
            label="LiveKit import",
        )

    if "Future<void> _openLiveKitTest()" not in source:
        method = """  Future<void> _openLiveKitTest() async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgLiveKitTestScreen(
          ru: widget.ru,
          initialIdentity: profile.id,
          initialDisplayName: profile.nickname,
        ),
      ),
    );
  }

"""
        source = replace_once(
            source,
            "  Future<void> _togglePrivacy() async {\n",
            method + "  Future<void> _togglePrivacy() async {\n",
            label="LiveKit navigation method",
        )

    if "if (value == 'livekit_test')" not in source:
        source = replace_once(
            source,
            "              if (value == 'language') widget.onChangeLanguage();\n"
            "              if (value == 'update') widget.onCheckUpdates();\n",
            "              if (value == 'language') widget.onChangeLanguage();\n"
            "              if (value == 'livekit_test') {\n"
            "                unawaited(_openLiveKitTest());\n"
            "              }\n"
            "              if (value == 'update') widget.onCheckUpdates();\n",
            label="LiveKit menu handler",
        )

    if "value: 'livekit_test'" not in source:
        item = """              PopupMenuItem(
                value: 'livekit_test',
                child: ListTile(
                  leading: const Icon(Icons.video_call_rounded),
                  title: Text(
                    widget.ru ? 'Тест LiveKit' : 'LiveKit test',
                  ),
                  subtitle: const Text('Android ↔ Windows'),
                ),
              ),
"""
        source = replace_once(
            source,
            "              PopupMenuItem(\n"
            "                value: 'update',\n",
            item
            + "              PopupMenuItem(\n"
            + "                value: 'update',\n",
            label="LiveKit menu item",
        )

    path.write_text(source, encoding="utf-8")


def patch_gitignore() -> None:
    path = ROOT / ".gitignore"
    source = path.read_text(encoding="utf-8") if path.exists() else ""
    entries = [".env.livekit", "services/livekit_broker/__pycache__/"]
    lines = set(source.splitlines())
    additions = [entry for entry in entries if entry not in lines]
    if not additions:
        return
    if source and not source.endswith("\n"):
        source += "\n"
    source += "\n# Local LiveKit environment\n" + "\n".join(additions) + "\n"
    path.write_text(source, encoding="utf-8")


def main() -> None:
    patch_pubspec()
    patch_navigation()
    patch_gitignore()
    print("LiveKit Calls v1 source materialized")


if __name__ == "__main__":
    main()
