from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    stale_files = (
        'lib/chat_state.dart',
        'lib/contacts_screen.dart',
        'lib/call_service_v08.dart',
        'lib/internet_core_v08.dart',
    )
    for name in stale_files:
        file = Path(name)
        if file.exists():
            file.unlink()

    replace(
        'lib/internet_core.dart',
        """      await Future.wait(
        relayHosts.map((host) => _connectHost(host)),
        eagerError: false,
      );
""",
        """      for (final host in relayHosts) {
        unawaited(_connectHost(host));
      }
      for (var attempt = 0; attempt < 20 && !connected; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
""",
    )

    chat_file = Path('lib/chat_screen.dart')
    chat_source = chat_file.read_text(encoding='utf-8')
    if "import 'app_monitor.dart';" not in chat_source:
        replace(
            'lib/chat_screen.dart',
            "import 'brand.dart';\n",
            "import 'app_monitor.dart';\nimport 'brand.dart';\n",
        )
    if "import 'sound_service.dart';" not in chat_source:
        replace(
            'lib/chat_screen.dart',
            "import 'internet_core.dart';\n",
            "import 'internet_core.dart';\nimport 'sound_service.dart';\n",
        )

    replace(
        'lib/chat_screen.dart',
        "  String get _inviteUrl =>\n      '$_landingBase?invite=${Uri.encodeQueryComponent(_tunnel.inviteToken)}';",
        "  String get _inviteUrl =>\n      '$_landingBase?v=15&invite=${Uri.encodeQueryComponent(_tunnel.inviteToken)}';\n\n  String get _deepInvite =>\n      'chernogram://join/${Uri.encodeComponent(_tunnel.inviteToken)}';",
    )
    replace(
        'lib/chat_screen.dart',
        'child: QrImageView(data: _inviteUrl, size: 220),',
        'child: QrImageView(data: _deepInvite, size: 220),',
    )
    replace(
        'lib/chat_screen.dart',
        "? 'Присоединяйся к моему туннелю Чернограма: $_inviteUrl'\n                        : 'Join my Chernogram tunnel: $_inviteUrl',",
        "? 'Открой чат в Чернограме: $_deepInvite\\n\\nЕсли приложение не открылось: $_inviteUrl'\n                        : 'Open the Chernogram chat: $_deepInvite\\n\\nIf the app did not open: $_inviteUrl',",
    )

    replace(
        'lib/chat_screen.dart',
        "          _mergeMessages([raw]);\n          _rememberContact(",
        "          _playIncomingMessageSound(raw);\n          _mergeMessages([raw]);\n          _rememberContact(",
    )

    contact_method = """  void _rememberContact(String id, String name) {
    if (id.isEmpty || id == widget.profile.id) return;
    widget.onContactSeen?.call(
      CgContact(
        id: id,
        nickname: name.trim().isEmpty ? 'user' : name,
        lastSeenAt: DateTime.now(),
        tunnelIds: [_tunnel.id],
      ),
    );
  }
"""
    if 'void _playIncomingMessageSound' not in Path('lib/chat_screen.dart').read_text(encoding='utf-8'):
        replace(
            'lib/chat_screen.dart',
            contact_method,
            contact_method
            + """
  void _playIncomingMessageSound(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    if (!CgMessageSoundRegistry.claim(id)) return;
    final sentAt = DateTime.tryParse(raw['sentAt']?.toString() ?? '');
    if (sentAt != null &&
        DateTime.now().difference(sentAt.toLocal()).inSeconds.abs() > 30) {
      return;
    }
    unawaited(ChernogramSound.playMessage());
  }
""",
        )

    old_merge = """  void _mergeMessages(List<Map<String, dynamic>> raw) {
    final byId = <String, CgMessage>{
      for (final message in _tunnel.messages) message.id: message,
    };
    var changed = false;
    for (final item in raw) {
      final incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final existing = byId[incoming.id];
      if (existing == null ||
          jsonEncode(existing.toJson()) != jsonEncode(incoming.toJson())) {
        byId[incoming.id] = incoming;
        changed = true;
      }
    }
    if (!changed) return;
    final messages = byId.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    _scrollToBottom();
  }
"""
    new_merge = """  void _mergeMessages(List<Map<String, dynamic>> raw) {
    final messages = <CgMessage>[..._tunnel.messages];
    var changed = false;
    for (final item in raw) {
      final incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final index = messages.indexWhere((message) => message.id == incoming.id);
      if (index < 0) {
        messages.add(incoming);
        changed = true;
        continue;
      }
      if (jsonEncode(messages[index].toJson()) !=
          jsonEncode(incoming.toJson())) {
        messages[index] = incoming;
        changed = true;
      }
    }
    if (!changed) return;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    _scrollToBottom();
  }
"""
    replace('lib/chat_screen.dart', old_merge, new_merge)

    replace(
        'lib/chat_screen.dart',
        '_handledCalls.add(callId)',
        'CgSignalRegistry.claim(callId)',
    )

    replace(
        'lib/chat_screen.dart',
        "  ) async {\n    final accepted = await showDialog<bool>(\n      context: context,\n      barrierDismissible: false,",
        "  ) async {\n    await ChernogramSound.startIncomingCall(video: video);\n    final accepted = await showDialog<bool>(\n      context: context,\n      barrierDismissible: false,",
    )
    replace(
        'lib/chat_screen.dart',
        "      ),\n    );\n    if (accepted != true) {\n      await _session?.sendSignal({",
        "      ),\n    );\n    await ChernogramSound.stopIncomingCall();\n    if (accepted != true) {\n      await _session?.sendSignal({",
    )

    replace(
        'lib/chat_screen.dart',
        "  ) async {\n    final accepted = await showDialog<bool>(\n      context: context,\n      builder: (context) => AlertDialog(\n        icon: Icon(\n          video ? Icons.groups_2_rounded : Icons.group_rounded,",
        "  ) async {\n    await ChernogramSound.startIncomingCall(video: video);\n    final accepted = await showDialog<bool>(\n      context: context,\n      builder: (context) => AlertDialog(\n        icon: Icon(\n          video ? Icons.groups_2_rounded : Icons.group_rounded,",
    )
    replace(
        'lib/chat_screen.dart',
        "      ),\n    );\n    if (accepted != true || !mounted) return;\n    await Navigator.push<CgCallOutcome>(",
        "      ),\n    );\n    await ChernogramSound.stopIncomingCall();\n    if (accepted != true || !mounted) return;\n    await Navigator.push<CgCallOutcome>(",
    )

    replace(
        'lib/chat_screen.dart',
        "    } else if (status == 'cancelled') {\n      subtitle = ru ? 'Звонок отменён' : 'Call cancelled';",
        "    } else if (status == 'cancelled') {\n      subtitle = mine\n          ? (ru ? 'Звонок отменён' : 'Call cancelled')\n          : (ru ? 'Пропущенный звонок' : 'Missed call');",
    )

    replace(
        'lib/chat_screen.dart',
        "  void dispose() {\n    unawaited(_subscription?.cancel());",
        "  void dispose() {\n    unawaited(ChernogramSound.stopIncomingCall());\n    unawaited(_subscription?.cancel());",
    )

    v07_file = Path('lib/v07.dart')
    v07_source = v07_file.read_text(encoding='utf-8')
    if "import 'app_monitor.dart';" not in v07_source:
        replace(
            'lib/v07.dart',
            "import 'agent_screen.dart';\n",
            "import 'agent_screen.dart';\nimport 'app_monitor.dart';\n",
        )

    replace(
        'lib/v07.dart',
        "    await _listenLinks();\n  }",
        "    _syncMonitor();\n    await _listenLinks();\n  }",
    )
    replace(
        'lib/v07.dart',
        "    await CgStore.saveTunnels(_tunnels);\n    await _openTunnel(tunnel);",
        "    await CgStore.saveTunnels(_tunnels);\n    _syncMonitor();\n    await _openTunnel(tunnel);",
    )
    replace(
        'lib/v07.dart',
        "    await CgStore.saveTunnels(_tunnels);\n    await _openTunnel(tunnel, autoInvite: true);",
        "    await CgStore.saveTunnels(_tunnels);\n    _syncMonitor();\n    await _openTunnel(tunnel, autoInvite: true);",
    )
    replace(
        'lib/v07.dart',
        "    if (mounted) setState(() {});\n    unawaited(CgStore.saveTunnels(_tunnels));\n  }\n\n  void _rememberContact",
        "    if (mounted) setState(() {});\n    unawaited(CgStore.saveTunnels(_tunnels));\n    _syncMonitor();\n  }\n\n  void _rememberContact",
    )

    monitor_method = """
  void _syncMonitor() {
    final profile = _profile;
    if (profile == null) return;
    unawaited(
      ChernogramAppMonitor.sync(
        profile: profile,
        tunnels: _tunnels,
        ru: widget.ru,
        onTunnelChanged: _updateTunnel,
        onContactSeen: _rememberContact,
      ),
    );
  }

"""
    if 'void _syncMonitor()' not in Path('lib/v07.dart').read_text(encoding='utf-8'):
        replace(
            'lib/v07.dart',
            "  Future<void> _saveProfile(CgProfile profile) async {",
            monitor_method + "  Future<void> _saveProfile(CgProfile profile) async {",
        )

    replace(
        'lib/v07.dart',
        "    await CgStore.saveProfile(profile);\n    if (mounted) setState(() => _profile = profile);",
        "    await CgStore.saveProfile(profile);\n    if (mounted) setState(() => _profile = profile);\n    _syncMonitor();",
    )
    replace(
        'lib/v07.dart',
        "  void dispose() {\n    unawaited(_linkSubscription?.cancel());",
        "  void dispose() {\n    unawaited(ChernogramAppMonitor.stop());\n    unawaited(_linkSubscription?.cancel());",
    )

    print('Applied Chernogram 0.8 app-wide calls, sounds and message ordering fixes')


if __name__ == '__main__':
    main()
