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
            "  http: ^1.5.0\n  livekit_client: 2.9.0\n",
            label="pubspec dependency",
        )
    else:
        source = re.sub(
            r"(?m)^  livekit_client:\s*\S+\s*$",
            "  livekit_client: 2.9.0",
            source,
            count=1,
        )
    path.write_text(source, encoding="utf-8")


def patch_livekit_screen() -> None:
    path = ROOT / "lib" / "livekit_test_screen.dart"
    source = path.read_text(encoding="utf-8")

    # Participant is intentionally accepted as the common base type. Its
    # publication can still contain an audio Track, so narrow it explicitly
    # before passing it to VideoTrackRenderer on Android and Windows.
    source = source.replace(
        """      final track = publication.track;
      if (track != null && !publication.muted) return track;
""",
        """      final track = publication.track;
      if (track is lk.VideoTrack && !publication.muted) return track;
""",
    )

    # Dispose asynchronously without passing a Future<bool> tear-off through
    # Future.whenComplete. This keeps the code accepted by strict Dart
    # analysis on both hosted runners.
    source = source.replace(
        "    unawaited(_room.disconnect().whenComplete(_room.dispose));\n",
        """    unawaited(() async {
      await _room.disconnect();
      await _room.dispose();
    }());
""",
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


def patch_android_manifest() -> None:
    path = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    source = path.read_text(encoding="utf-8")

    required_permissions = [
        '    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />',
        '    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />',
    ]
    anchor = '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />'
    for permission in required_permissions:
        if permission not in source:
            source = replace_once(
                source,
                anchor + "\n",
                anchor + "\n" + permission + "\n",
                label=f"Android permission {permission}",
            )
            anchor = permission

    camera_feature = (
        '    <uses-feature android:name="android.hardware.camera" '
        'android:required="false" />'
    )
    microphone_feature = (
        '    <uses-feature android:name="android.hardware.microphone" '
        'android:required="false" />'
    )
    if camera_feature not in source:
        source = replace_once(
            source,
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            + camera_feature
            + "\n"
            + microphone_feature
            + "\n",
            label="Android LiveKit features",
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
    patch_livekit_screen()
    patch_navigation()
    patch_android_manifest()
    patch_gitignore()
    print("LiveKit Calls v1 source materialized")


if __name__ == "__main__":
    main()
