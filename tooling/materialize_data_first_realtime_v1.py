from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_monitor() -> None:
    path = ROOT / "lib" / "app_monitor.dart"
    text = path.read_text(encoding="utf-8")
    if "static Future<void> publishMessage" in text:
        return
    method = """  static Future<void> publishMessage({
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

"""
    text = replace_once(
        text,
        "  static Future<void> stop() async {\n",
        method + "  static Future<void> stop() async {\n",
        "monitor publisher",
    )
    path.write_text(text, encoding="utf-8")


def patch_shell() -> None:
    path = ROOT / "lib" / "android_data_first.dart"
    text = path.read_text(encoding="utf-8")

    if "import 'app_monitor.dart';" not in text:
        text = replace_once(
            text,
            "import 'account_access.dart';\n",
            "import 'account_access.dart';\nimport 'app_monitor.dart';\n",
            "app monitor import",
        )

    if "Future<void> _syncMonitor()" not in text:
        method = """  Future<void> _syncMonitor() async {
    final profile = _profile;
    if (profile == null) return;
    await ChernogramAppMonitor.sync(
      profile: profile,
      tunnels: _tunnels,
      ru: widget.ru,
      onTunnelChanged: _updateTunnel,
      onContactSeen: _rememberContact,
    );
  }

"""
        text = replace_once(
            text,
            "  Future<void> _listenLinks() async {\n",
            method + "  Future<void> _listenLinks() async {\n",
            "monitor sync method",
        )

    bootstrap_old = """    });
    await _listenLinks();
  }

  Future<void> _syncMonitor() async {
"""
    bootstrap_new = """    });
    await _syncMonitor();
    await _listenLinks();
  }

  Future<void> _syncMonitor() async {
"""
    if bootstrap_old in text:
        text = replace_once(
            text,
            bootstrap_old,
            bootstrap_new,
            "bootstrap monitor sync",
        )

    save_join_old = """    await CgStore.saveTunnels(_tunnels);
    await _openTunnel(tunnel);
"""
    save_join_new = """    await CgStore.saveTunnels(_tunnels);
    await _syncMonitor();
    await _openTunnel(tunnel);
"""
    if save_join_old in text:
        text = replace_once(text, save_join_old, save_join_new, "join sync")

    save_create_old = """    setState(() => _tunnels = [tunnel, ..._tunnels]);
    await CgStore.saveTunnels(_tunnels);
    return tunnel;
"""
    save_create_new = """    setState(() => _tunnels = [tunnel, ..._tunnels]);
    await CgStore.saveTunnels(_tunnels);
    await _syncMonitor();
    return tunnel;
"""
    if save_create_old in text:
        text = replace_once(text, save_create_old, save_create_new, "create sync")

    update_old = """    if (mounted) setState(() => _tunnels = copy);
    unawaited(CgStore.saveTunnels(copy));
  }
"""
    update_new = """    if (mounted) setState(() => _tunnels = copy);
    unawaited(CgStore.saveTunnels(copy));
    unawaited(_syncMonitor());
  }
"""
    if update_old in text:
        text = replace_once(text, update_old, update_new, "tunnel update sync")

    restore_old = """    setState(() {
      _profile = bundle.profile;
      _tunnels = bundle.tunnels;
      _contacts = bundle.contacts;
    });
  }
"""
    restore_new = """    setState(() {
      _profile = bundle.profile;
      _tunnels = bundle.tunnels;
      _contacts = bundle.contacts;
    });
    await _syncMonitor();
  }
"""
    if restore_old in text:
        text = replace_once(text, restore_old, restore_new, "restore sync")

    profile_old = """        onProfileChanged: (profile) async {
          await CgStore.saveProfile(profile);
          if (mounted) setState(() => _profile = profile);
        },
"""
    profile_new = """        onProfileChanged: (profile) async {
          await CgStore.saveProfile(profile);
          if (mounted) setState(() => _profile = profile);
          await _syncMonitor();
        },
"""
    if profile_old in text:
        text = replace_once(text, profile_old, profile_new, "profile sync")

    dispose_old = """  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }
"""
    dispose_new = """  void dispose() {
    unawaited(_linkSubscription?.cancel());
    unawaited(ChernogramAppMonitor.stop());
    super.dispose();
  }
"""
    if dispose_old in text:
        text = replace_once(text, dispose_old, dispose_new, "monitor dispose")

    local_publish_old = """      final updated = room.copyWith(messages: [...room.messages, message]);
      widget.onTunnelChanged(updated);
      if (mounted) {
"""
    local_publish_new = """      final updated = room.copyWith(messages: [...room.messages, message]);
      widget.onTunnelChanged(updated);
      await ChernogramAppMonitor.publishMessage(
        profile: widget.profile,
        tunnel: updated,
        message: message,
      );
      if (mounted) {
"""
    if local_publish_old in text:
        text = replace_once(
            text,
            local_publish_old,
            local_publish_new,
            "public file publish",
        )

    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_monitor()
    patch_shell()
    print("Android data-first background realtime materialized")


if __name__ == "__main__":
    main()
