from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "d1cad8649d00259ab615e65ea196213713b2385f"
VERSION = "0.24.0+56"


def old(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{BASE}:{path}"],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
    )


def replace(text: str, before: str, after: str, name: str) -> str:
    if before not in text:
        raise RuntimeError(f"Missing 0.7.3 anchor: {name}")
    return text.replace(before, after, 1)


def build_internet_core() -> str:
    text = old("lib/internet_core.dart")

    text = replace(
        text,
        "  final Map<String, DateTime> _peers = <String, DateTime>{};\n",
        "  final Map<String, DateTime> _peers = <String, DateTime>{};\n"
        "  final Map<String, String> _peerNames = <String, String>{};\n"
        "  final List<Map<String, dynamic>> _signalHistory =\n"
        "      <Map<String, dynamic>>[];\n",
        "peer state",
    )

    text = replace(
        text,
        "  int get onlinePeers => _peers.length + 1;\n",
        "  int get onlinePeers => _peers.length + 1;\n"
        "  List<Map<String, dynamic>> get members => <Map<String, dynamic>>[\n"
        "        <String, dynamic>{'id': profileId, 'name': nickname, 'self': true},\n"
        "        ..._peers.entries.map((entry) => <String, dynamic>{\n"
        "              'id': entry.key,\n"
        "              'name': _peerNames[entry.key] ?? 'user',\n"
        "              'self': false,\n"
        "              'seenAt': entry.value.toUtc().toIso8601String(),\n"
        "            }),\n"
        "      ];\n\n"
        "  Future<bool> waitUntilConnected([\n"
        "    Duration timeout = const Duration(seconds: 4),\n"
        "  ]) async {\n"
        "    if (_connected) return true;\n"
        "    unawaited(connect());\n"
        "    final deadline = DateTime.now().add(timeout);\n"
        "    while (!_closed && DateTime.now().isBefore(deadline)) {\n"
        "      if (_connected) return true;\n"
        "      await Future<void>.delayed(const Duration(milliseconds: 120));\n"
        "    }\n"
        "    return _connected;\n"
        "  }\n",
        "compatibility getters",
    )

    text = replace(
        text,
        "    final senderName = envelope['name']?.toString() ?? 'user';\n"
        "    _peers[sender] = DateTime.now();\n"
        "    _emitPresence();\n",
        "    final senderName = envelope['name']?.toString() ?? 'user';\n"
        "    _peers[sender] = DateTime.now();\n"
        "    _peerNames[sender] = senderName;\n"
        "    _emit('peer', <String, dynamic>{\n"
        "      'id': sender,\n"
        "      'name': senderName,\n"
        "      'seenAt': DateTime.now().toUtc().toIso8601String(),\n"
        "    });\n"
        "    _emitPresence();\n",
        "peer event",
    )

    text = replace(
        text,
        "      case 'signal':\n"
        "        _emit('signal', {\n"
        "          ...data,\n"
        "          'relaySender': sender,\n"
        "          'relaySenderName': senderName,\n"
        "        });\n"
        "        break;\n",
        "      case 'control':\n"
        "        _emit('control', <String, dynamic>{\n"
        "          ...data,\n"
        "          'relaySender': sender,\n"
        "          'relaySenderName': senderName,\n"
        "        });\n"
        "        break;\n"
        "      case 'signal':\n"
        "        final signal = <String, dynamic>{\n"
        "          ...data,\n"
        "          'relaySender': sender,\n"
        "          'relaySenderName': senderName,\n"
        "          'sentAt': envelope['sentAt'],\n"
        "          'receivedAt': DateTime.now().toUtc().toIso8601String(),\n"
        "        };\n"
        "        _signalHistory.add(signal);\n"
        "        if (_signalHistory.length > 200) {\n"
        "          _signalHistory.removeRange(0, _signalHistory.length - 200);\n"
        "        }\n"
        "        _emit('signal', signal);\n"
        "        break;\n",
        "control and signal events",
    )

    text = replace(
        text,
        "  Future<void> sendSignal(Map<String, dynamic> signal) async {\n"
        "    await _sendEnvelope('signal', signal);\n"
        "  }\n",
        "  Future<void> sendControl(Map<String, dynamic> control) async {\n"
        "    await _sendEnvelope('control', control);\n"
        "  }\n\n"
        "  Future<void> sendSignal(Map<String, dynamic> signal) async {\n"
        "    await _sendEnvelope('signal', signal);\n"
        "  }\n\n"
        "  List<Map<String, dynamic>> replaySignals(String callId) {\n"
        "    if (callId.isEmpty) return const <Map<String, dynamic>>[];\n"
        "    return _signalHistory\n"
        "        .where((item) => item['callId']?.toString() == callId)\n"
        "        .map((item) => Map<String, dynamic>.from(item))\n"
        "        .toList();\n"
        "  }\n\n"
        "  Future<void> sendHistory() async {\n"
        "    if (_history.isEmpty) return;\n"
        "    final start = _history.length > 120 ? _history.length - 120 : 0;\n"
        "    await _sendEnvelope('history', <String, dynamic>{\n"
        "      'messages': _history.skip(start).toList(),\n"
        "    });\n"
        "  }\n",
        "current public send API",
    )

    text = replace(
        text,
        "    await session.connect();\n    return session;\n",
        "    unawaited(session.connect());\n    return session;\n",
        "instant session return",
    )
    return text


def build_call_service() -> str:
    text = old("lib/call_service.dart")
    text = replace(
        text,
        "import 'brand.dart';\n",
        "import 'brand.dart';\nimport 'call_avatar.dart';\n",
        "current avatar import",
    )
    text = replace(
        text,
        "class ChernogramCallScreen extends StatefulWidget {\n",
        "class CgCallOutcome {\n"
        "  final String status;\n"
        "  final int durationSeconds;\n"
        "  final bool connected;\n"
        "  final bool video;\n\n"
        "  const CgCallOutcome({\n"
        "    required this.status,\n"
        "    required this.durationSeconds,\n"
        "    required this.connected,\n"
        "    required this.video,\n"
        "  });\n"
        "}\n\n"
        "class ChernogramCallScreen extends StatefulWidget {\n",
        "call result contract",
    )
    text = replace(
        text,
        "  final bool isCaller;\n  final String? peerName;\n",
        "  final bool isCaller;\n"
        "  final String? peerId;\n"
        "  final String? peerName;\n"
        "  final String? peerAvatarBase64;\n"
        "  final String? myAvatarBase64;\n",
        "current call fields",
    )
    text = replace(
        text,
        "    this.isCaller = true,\n    this.peerName,\n",
        "    this.isCaller = true,\n"
        "    this.peerId,\n"
        "    this.peerName,\n"
        "    this.peerAvatarBase64,\n"
        "    this.myAvatarBase64,\n",
        "current call parameters",
    )
    text = replace(
        text,
        "                      const ChernogramLogo(size: 112, withPlate: true),\n",
        "                      CgCallAvatar(\n"
        "                        avatarBase64: widget.peerAvatarBase64,\n"
        "                        name: remoteLabel,\n"
        "                        size: 112,\n"
        "                        fallbackIcon: widget.video\n"
        "                            ? Icons.videocam_rounded\n"
        "                            : Icons.call_rounded,\n"
        "                      ),\n",
        "current peer avatar presentation",
    )
    return text


def patch_monitor() -> None:
    path = ROOT / "lib/app_monitor.dart"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "      unawaited(InternetRelay.close(tunnelId));\n",
        "      // Shared 0.7.3 session may still be used by the visible chat/call.\n",
    )
    path.write_text(text, encoding="utf-8")


def bump_version() -> None:
    path = ROOT / "pubspec.yaml"
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if line.startswith("version:"):
            lines[index] = f"version: {VERSION}"
            break
    else:
        raise RuntimeError("pubspec version not found")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    (ROOT / "lib/internet_core.dart").write_text(
        build_internet_core(), encoding="utf-8"
    )
    (ROOT / "lib/call_service.dart").write_text(
        build_call_service(), encoding="utf-8"
    )
    patch_monitor()
    bump_version()
    print(f"Restored exact working 0.7.3+14 chat and WebRTC video calls from {BASE}")


if __name__ == "__main__":
    main()
