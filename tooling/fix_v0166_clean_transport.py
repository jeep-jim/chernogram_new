from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write_if_changed(path: str, source: str, original: str) -> bool:
    if source == original:
        return False
    Path(path).write_text(source, encoding='utf-8')
    print(f'Patched {path}')
    return True


def patch_internet_core() -> bool:
    path = 'lib/internet_core.dart'
    source = read(path)
    original = source

    # Do not replay a half hour of cached relay traffic after every reconnect.
    # Thirty seconds is enough to bridge a brief radio/network handover without
    # filling the event loop with stale messages, presence and call packets.
    source = source.replace("'since': '30m'", "'since': '30s'")

    # ntfy's documented maximum priority is max/5. Keep one canonical value on
    # every relay instead of relying on server-specific aliases.
    source = source.replace("priority: 'urgent'", "priority: 'max'")
    source = source.replace(
        "priority: kind == 'signal' ? 'urgent' : 'default'",
        "priority: kind == 'signal' ? 'max' : 'high'",
    )

    # Signals, presence, control packets and normal text messages are tiny and
    # latency-sensitive. Publish them in parallel to the already configured
    # relay set. Packet IDs already deduplicate copies on the receiver.
    source = source.replace(
        "    if (kind == 'signal') {\n"
        "      successfulHost = await _publishSignalFast(orderedHosts, encrypted);\n"
        "    } else {",
        "    final fastPacket = kind == 'signal' ||\n"
        "        kind == 'presence' ||\n"
        "        kind == 'control' ||\n"
        "        (kind == 'message' && encrypted.length <= 3500);\n"
        "    if (fastPacket) {\n"
        "      successfulHost = await _publishSignalFast(orderedHosts, encrypted);\n"
        "    } else {",
        1,
    )

    # A dead public endpoint must not hold the UI or call negotiation for many
    # seconds. Other relays are attempted in parallel for fast packets.
    source = source.replace(
        "Duration timeout = const Duration(seconds: 8)",
        "Duration timeout = const Duration(seconds: 4)",
        1,
    )

    # Keep heartbeat reasonably quick, but avoid the 0.16.5 three-way packet
    # storm while the phone radio is changing networks.
    source = source.replace(
        'Timer.periodic(const Duration(seconds: 8), (_) {\n      unawaited(_publishPresence());',
        'Timer.periodic(const Duration(seconds: 12), (_) {\n      unawaited(_publishPresence());',
        1,
    )
    source = source.replace(
        'Timer.periodic(const Duration(seconds: 8), (_) {\n      final cutoff',
        'Timer.periodic(const Duration(seconds: 10), (_) {\n      final cutoff',
        1,
    )
    source = source.replace(
        'DateTime.now().subtract(const Duration(seconds: 28))',
        'DateTime.now().subtract(const Duration(seconds: 32))',
        1,
    )

    return write_if_changed(path, source, original)


def patch_chat_screen() -> bool:
    path = 'lib/chat_screen.dart'
    source = read(path)
    original = source

    # Never address a new call to an arbitrary old author from chat history.
    # When no live peer is known, broadcast inside the encrypted tunnel; the
    # first answering peer is then locked by callId/target negotiation.
    pattern = re.compile(
        r"  String\? get _preferredPeerId \{.*?\n  \}\n\n  String\? get _preferredPeerName",
        re.S,
    )
    match = pattern.search(source)
    if match:
        replacement = r'''  String? get _preferredPeerId {
    final session = _session;
    if (session == null) return null;
    for (final member in session.members) {
      if (member['self'] == true) continue;
      final id = member['id']?.toString() ?? '';
      if (id.isNotEmpty && id != widget.profile.id) return id;
    }
    return null;
  }

  String? get _preferredPeerName'''
        source = source[:match.start()] + replacement + source[match.end():]

    return write_if_changed(path, source, original)


def patch_call_service() -> bool:
    path = 'lib/call_service.dart'
    source = read(path)
    original = source

    # 0.16.5 sent overlapping invite/ready/offer bursts every 700-850 ms to
    # four public relays. A short, non-overloading cadence is faster in practice
    # on mobile radios and prevents Android ANRs during camera setup.
    source = source.replace(
        'Timer.periodic(const Duration(milliseconds: 700)',
        'Timer.periodic(const Duration(milliseconds: 1200)',
    )
    source = source.replace(
        'Timer.periodic(const Duration(milliseconds: 850)',
        'Timer.periodic(const Duration(milliseconds: 1500)',
    )

    # Do not let a slow relay await block call preparation indefinitely.
    old = """  Future<void> _sendSignal(Map<String, dynamic> data) async {
    final session = _session;
    if (session == null || _ended) return;
    await session.sendSignal(<String, dynamic>{
      ...data,
      'callId': _callId,
      'from': _profileId,
      'video': widget.video,
      if (_peerId != null && _peerId!.isNotEmpty) 'target': _peerId,
    });
  }
"""
    new = """  Future<void> _sendSignal(Map<String, dynamic> data) async {
    final session = _session;
    if (session == null || _ended) return;
    try {
      await session
          .sendSignal(<String, dynamic>{
            ...data,
            'callId': _callId,
            'from': _profileId,
            'video': widget.video,
            if (_peerId != null && _peerId!.isNotEmpty) 'target': _peerId,
          })
          .timeout(const Duration(milliseconds: 3200));
    } catch (_) {}
  }
"""
    if old in source:
        source = source.replace(old, new, 1)

    return write_if_changed(path, source, original)


def patch_main() -> bool:
    path = 'lib/main.dart'
    source = read(path)
    original = source

    # A vendor Android ROM may reject/restart a foreground service. That must
    # never terminate the visible application or delay its first frame.
    source = source.replace(
        '  await initializeChernogramRealtimeService();\n',
        "  try {\n"
        "    await initializeChernogramRealtimeService()\n"
        "        .timeout(const Duration(seconds: 4));\n"
        "  } catch (_) {}\n",
        1,
    )

    return write_if_changed(path, source, original)


def patch_background_service() -> bool:
    path = 'lib/background_realtime_service.dart'
    source = read(path)
    original = source

    # Do not overlap a full session rescan every 20 seconds when a previous
    # SharedPreferences/network pass is still running on a slow Android device.
    if 'bool syncingSessions = false;' not in source:
        source = source.replace(
            '  List<CgTunnel> tunnels = const <CgTunnel>[];\n',
            '  List<CgTunnel> tunnels = const <CgTunnel>[];\n'
            '  bool syncingSessions = false;\n',
            1,
        )

    source = source.replace(
        '  Future<void> syncSessions() async {\n    profile = await CgStore.loadOrCreateProfile();',
        '  Future<void> syncSessions() async {\n'
        '    if (syncingSessions) return;\n'
        '    syncingSessions = true;\n'
        '    try {\n'
        '      profile = await CgStore.loadOrCreateProfile();',
        1,
    )

    marker = """    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      service.setForegroundNotificationInfo(
        title: 'Чернограм на связи',
        content: '${tunnels.length} чатов слушают сообщения и звонки',
      );
    }
  }
"""
    replacement = """      if (service is AndroidServiceInstance &&
          await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'Чернограм на связи',
          content: '${tunnels.length} чатов слушают сообщения и звонки',
        );
      }
    } catch (_) {
      // The foreground isolate must survive temporary storage/network errors.
    } finally {
      syncingSessions = false;
    }
  }
"""
    if marker in source:
        source = source.replace(marker, replacement, 1)

    return write_if_changed(path, source, original)


def patch_metadata() -> bool:
    changed = False

    path = 'pubspec.yaml'
    source = read(path)
    original = source
    source = re.sub(
        r'^version:\s*0\.16\.[0-9]+\+[0-9]+\s*$',
        'version: 0.16.6+37',
        source,
        count=1,
        flags=re.M,
    )
    changed |= write_if_changed(path, source, original)

    path = 'docs/index.html'
    source = read(path)
    original = source
    source = re.sub(r'chernogram\.apk\?v=\d+', 'chernogram.apk?v=37', source)
    changed |= write_if_changed(path, source, original)

    path = 'roadmap.md'
    source = read(path)
    original = source
    if '`0.16.6+37`' not in source:
        source = source.rstrip() + (
            '\n- `0.16.6+37` — очищен realtime-транспорт: короткий relay replay, '
            'параллельная доставка звонков, presence и текстовых сообщений, исправлена адресация '
            'вызова и защищён Android foreground isolate от наложения синхронизаций.\n'
        )
    changed |= write_if_changed(path, source, original)

    return changed


def main() -> None:
    changed = False
    changed |= patch_internet_core()
    changed |= patch_chat_screen()
    changed |= patch_call_service()
    changed |= patch_main()
    changed |= patch_background_service()
    changed |= patch_metadata()
    print(
        'Chernogram 0.16.6 clean realtime transport fixes applied'
        if changed
        else 'Chernogram 0.16.6 clean transport already applied'
    )


if __name__ == '__main__':
    main()
