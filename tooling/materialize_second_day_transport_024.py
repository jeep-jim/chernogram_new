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


def restore_transport() -> None:
    # Restore only the proven room transport and background receiver.
    # The current 0.23 interface, media screens, settings and call UI remain.
    internet = git_show("lib/internet_core.dart")
    compat = r'''

// Compatibility surface for the current UI. The second-day transport used
// signals for room-side control events; newer screens call sendControl.
extension CgSecondDayControlCompatibility on InternetTunnelSession {
  Future<void> sendControl(Map<String, dynamic> control) => sendSignal(
        <String, dynamic>{
          'action': 'room_control',
          'control': control,
        },
      );
}
'''
    if "CgSecondDayControlCompatibility" not in internet:
        internet += compat
    write("lib/internet_core.dart", internet)

    monitor = git_show("lib/app_monitor.dart")
    if "static Future<void> publishMessage" not in monitor:
        method = r'''  static Future<void> publishMessage({
    required CgProfile profile,
    required CgTunnel tunnel,
    required CgMessage message,
  }) async {
    _profile ??= profile;
    _tunnels[tunnel.id] = tunnel;
    await _ensureTunnel(tunnel);
    final session = _sessions[tunnel.id];
    if (session == null) {
      throw StateError('Room transport is unavailable');
    }
    session.replaceHistory(
      tunnel.messages.map((item) => item.toJson()).toList(),
    );
    await session.sendMessage(message.toJson());
  }

'''
        anchor = "  static Future<void> stop() async {\n"
        if anchor not in monitor:
            raise RuntimeError("second-day app monitor stop anchor not found")
        monitor = monitor.replace(anchor, method + anchor, 1)
    write("lib/app_monitor.dart", monitor)


def make_ui_non_blocking() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")

    # Voice and ordinary messages must remain usable while reconnecting.
    text = text.replace(
        "enabled: _networkState == 'connected',",
        "enabled: true,",
    )

    # Never present a permanent failure as if the chat itself were unusable.
    text = text.replace(
        "widget.ru ? 'Не подключено' : 'Not connected'",
        "widget.ru ? 'Сообщения отправятся автоматически' : 'Messages will send automatically'",
    )
    text = text.replace(
        "widget.ru ? 'Соединение…' : 'Connecting…'",
        "widget.ru ? 'Синхронизация' : 'Syncing'",
    )
    path.write_text(text, encoding="utf-8")


def bump_version() -> None:
    path = ROOT / "pubspec.yaml"
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if line.startswith("version:"):
            lines[index] = "version: 0.24.0+56"
            break
    else:
        raise RuntimeError("pubspec version field not found")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    restore_transport()
    make_ui_non_blocking()
    bump_version()
    print(f"Second-day transport {BASE} applied to Chernogram 0.24 UI")


if __name__ == "__main__":
    main()
