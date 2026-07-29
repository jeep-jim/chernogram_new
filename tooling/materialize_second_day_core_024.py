from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "d1cad8649d00259ab615e65ea196213713b2385f"
VERSION = "0.24.0+56"


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


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"Patch anchor not found: {label}")
    return text.replace(old, new, 1)


def materialize_internet_core() -> None:
    text = git_show("lib/internet_core.dart")

    text = replace_once(
        text,
        "  final Map<String, DateTime> _peers = <String, DateTime>{};\n",
        "  final Map<String, DateTime> _peers = <String, DateTime>{};\n"
        "  final Map<String, String> _peerNames = <String, String>{};\n"
        "  final List<Map<String, dynamic>> _signalHistory =\n"
        "      <Map<String, dynamic>>[];\n",
        "peer compatibility state",
    )

    text = replace_once(
        text,
        "  Stream<InternetEvent> get events => _events.stream;\n"
        "  bool get connected => _connected;\n"
        "  int get onlinePeers => _peers.length + 1;\n",
        "  Stream<InternetEvent> get events => _events.stream;\n"
        "  bool get connected => _connected;\n"
        "  int get onlinePeers => _peers.length + 1;\n"
        "  List<Map<String, dynamic>> get members => <Map<String, dynamic>>[\n"
        "        <String, dynamic>{\n"
        "          'id': profileId,\n"
        "          'name': nickname,\n"
        "          'self': true,\n"
        "          'seenAt': DateTime.now().toUtc().toIso8601String(),\n"
        "        },\n"
        "        ..._peers.entries.map(\n"
        "          (entry) => <String, dynamic>{\n"
        "            'id': entry.key,\n"
        "            'name': _peerNames[entry.key] ?? 'user',\n"
        "            'self': false,\n"
        "            'seenAt': entry.value.toUtc().toIso8601String(),\n"
        "          },\n"
        "        ),\n"
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
        "public compatibility API",
    )

    text = replace_once(
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

    text = replace_once(
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
        "control and signal replay",
    )

    text = replace_once(
        text,
        "  Future<void> sendMessage(Map<String, dynamic> message) async {\n"
        "    _rememberMessage(message);\n"
        "    await _sendEnvelope('message', {'message': message});\n"
        "  }\n\n"
        "  Future<void> sendSignal(Map<String, dynamic> signal) async {\n"
        "    await _sendEnvelope('signal', signal);\n"
        "  }\n",
        "  Future<void> sendMessage(Map<String, dynamic> message) async {\n"
        "    _rememberMessage(message);\n"
        "    await _sendEnvelope('message', {'message': message});\n"
        "  }\n\n"
        "  Future<void> sendControl(Map<String, dynamic> control) async {\n"
        "    await _sendEnvelope('control', control);\n"
        "  }\n\n"
        "  Future<void> sendSignal(Map<String, dynamic> signal) async {\n"
        "    await _sendEnvelope('signal', signal);\n"
        "  }\n\n"
        "  List<Map<String, dynamic>> replaySignals(String callId) {\n"
        "    if (callId.isEmpty) return const <Map<String, dynamic>>[];\n"
        "    final cutoff =\n"
        "        DateTime.now().toUtc().subtract(const Duration(minutes: 3));\n"
        "    return _signalHistory\n"
        "        .where((signal) {\n"
        "          if (signal['callId']?.toString() != callId) return false;\n"
        "          final receivedAt = DateTime.tryParse(\n"
        "            signal['receivedAt']?.toString() ?? '',\n"
        "          );\n"
        "          return receivedAt == null || !receivedAt.toUtc().isBefore(cutoff);\n"
        "        })\n"
        "        .map((signal) => Map<String, dynamic>.from(signal))\n"
        "        .toList();\n"
        "  }\n\n"
        "  Future<void> sendHistory() async {\n"
        "    if (_history.isEmpty) return;\n"
        "    final start = _history.length > 120 ? _history.length - 120 : 0;\n"
        "    await _sendEnvelope('history', <String, dynamic>{\n"
        "      'messages': _history.skip(start).toList(),\n"
        "    });\n"
        "  }\n",
        "send API",
    )

    text = replace_once(
        text,
        "    await session.connect();\n    return session;\n",
        "    unawaited(session.connect());\n    return session;\n",
        "non-blocking session open",
    )

    write("lib/internet_core.dart", text)


def materialize_call_service() -> None:
    text = git_show("lib/call_service.dart")

    text = replace_once(
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
        "call outcome compatibility",
    )

    text = replace_once(
        text,
        "  final bool isCaller;\n  final String? peerName;\n",
        "  final bool isCaller;\n  final String? peerId;\n  final String? peerName;\n",
        "peer field",
    )
    text = replace_once(
        text,
        "    this.isCaller = true,\n    this.peerName,\n",
        "    this.isCaller = true,\n    this.peerId,\n    this.peerName,\n",
        "peer constructor",
    )

    text = replace_once(
        text,
        "  bool _remoteVideoReady = false;\n  String _status = '';\n  String? _error;\n\n"
        "  String get _callId => widget.callId ?? CgIds.random(20);\n",
        "  bool _remoteVideoReady = false;\n"
        "  String _status = '';\n"
        "  String? _error;\n"
        "  DateTime? _connectedAt;\n"
        "  late final String _resolvedCallId;\n"
        "  String? _peerId;\n\n"
        "  String get _callId => _resolvedCallId;\n",
        "stable call state",
    )

    text = replace_once(
        text,
        "    super.initState();\n    _status = widget.ru ? 'Подключаем защищённый звонок…' : 'Connecting secure call…';\n",
        "    super.initState();\n"
        "    _resolvedCallId = widget.callId ?? CgIds.random(20);\n"
        "    _peerId = widget.peerId;\n"
        "    _status = widget.ru\n"
        "        ? 'Подключаем защищённый звонок…'\n"
        "        : 'Connecting secure call…';\n",
        "call initialization",
    )

    text = replace_once(
        text,
        "              _remoteVideoReady = true;\n              _status = widget.ru ? 'Соединено' : 'Connected';\n",
        "              _remoteVideoReady = true;\n"
        "              _connectedAt ??= DateTime.now();\n"
        "              _status = widget.ru ? 'Соединено' : 'Connected';\n",
        "remote track connected state",
    )
    text = replace_once(
        text,
        "            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:\n"
        "              _status = widget.ru ? 'Соединено' : 'Connected';\n",
        "            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:\n"
        "              _connectedAt ??= DateTime.now();\n"
        "              _status = widget.ru ? 'Соединено' : 'Connected';\n",
        "peer connected state",
    )

    text = replace_once(
        text,
        "    final target = data['target']?.toString();\n"
        "    if (target != null && target.isNotEmpty && target != _profileId) return;\n"
        "    final action = data['action']?.toString() ?? '';\n",
        "    final target = data['target']?.toString();\n"
        "    if (target != null && target.isNotEmpty && target != _profileId) return;\n"
        "    final relaySender = data['relaySender']?.toString() ?? '';\n"
        "    if (relaySender.isNotEmpty && relaySender != _profileId) {\n"
        "      _peerId ??= relaySender;\n"
        "    }\n"
        "    final action = data['action']?.toString() ?? '';\n",
        "learn peer id from relay",
    )

    text = replace_once(
        text,
        "           Future<void>.delayed(const Duration(milliseconds: 850), () {\n"
        "             if (mounted) Navigator.pop(context);\n"
        "           });\n",
        "           Future<void>.delayed(const Duration(milliseconds: 850), () {\n"
        "             if (mounted) Navigator.pop(context, _outcome('declined'));\n"
        "           });\n",
        "declined outcome",
    )
    text = replace_once(
        text,
        "           Future<void>.delayed(const Duration(milliseconds: 500), () {\n"
        "             if (mounted) Navigator.pop(context);\n"
        "           });\n",
        "           Future<void>.delayed(const Duration(milliseconds: 500), () {\n"
        "             if (mounted) Navigator.pop(context, _outcome('completed'));\n"
        "           });\n",
        "ended outcome",
    )

    text = replace_once(
        text,
        "    await session.sendSignal({\n"
        "      ...data,\n"
        "      'callId': _callId,\n"
        "      'from': _profileId,\n"
        "      'video': widget.video,\n"
        "    });\n",
        "    await session.sendSignal({\n"
        "      ...data,\n"
        "      'callId': _callId,\n"
        "      'from': _profileId,\n"
        "      if (_peerId != null && _peerId!.isNotEmpty) 'target': _peerId,\n"
        "      'video': widget.video,\n"
        "    });\n",
        "targeted call signals",
    )

    text = replace_once(
        text,
        "  Future<void> _hangUp() async {\n"
        "    if (_ended) return;\n"
        "    _ended = true;\n"
        "    await _sendSignal({'action': 'call_end'});\n"
        "    if (mounted) Navigator.pop(context);\n"
        "  }\n",
        "  CgCallOutcome _outcome(String status) {\n"
        "    final connectedAt = _connectedAt;\n"
        "    final duration = connectedAt == null\n"
        "        ? 0\n"
        "        : DateTime.now().difference(connectedAt).inSeconds;\n"
        "    return CgCallOutcome(\n"
        "      status: status,\n"
        "      durationSeconds: duration < 0 ? 0 : duration,\n"
        "      connected: connectedAt != null,\n"
        "      video: widget.video,\n"
        "    );\n"
        "  }\n\n"
        "  Future<void> _hangUp() async {\n"
        "    if (_ended) return;\n"
        "    _ended = true;\n"
        "    await _sendSignal({'action': 'call_end'});\n"
        "    if (mounted) {\n"
        "      Navigator.pop(\n"
        "        context,\n"
        "        _outcome(_connectedAt == null ? 'cancelled' : 'completed'),\n"
        "      );\n"
        "    }\n"
        "  }\n",
        "hangup outcome",
    )

    write("lib/call_service.dart", text)


def patch_app_monitor() -> None:
    path = ROOT / "lib/app_monitor.dart"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "      unawaited(InternetRelay.close(tunnelId));\n",
        "      // Do not close the shared room session here. The visible chat or an\n"
        "      // active call may still use the same 0.7.3 transport instance.\n",
    )
    write("lib/app_monitor.dart", text)


def bump_version() -> None:
    path = ROOT / "pubspec.yaml"
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("version:"):
            lines[index] = f"version: {VERSION}"
            break
    else:
        raise RuntimeError("pubspec version field not found")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    materialize_internet_core()
    materialize_call_service()
    patch_app_monitor()
    bump_version()
    print(f"Chernogram {VERSION}: exact 0.7.3 chat/video-call transport restored from {BASE}")


if __name__ == "__main__":
    main()
