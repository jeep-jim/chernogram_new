from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    Path(path).write_text(source, encoding='utf-8')


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old in source:
        return source.replace(old, new, 1)
    if new in source:
        return source
    raise RuntimeError(f'Expected block was not found: {label}')


def patch_main() -> bool:
    path = Path('lib/main.dart')
    source = read(str(path))
    original = source

    if "import 'dart:io';" not in source:
        source = source.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n", 1)

    if "import 'notification_service.dart';" not in source:
        source = source.replace(
            "import 'brand.dart';\n",
            "import 'brand.dart';\nimport 'desktop_tray_service.dart';\nimport 'notification_service.dart';\n",
            1,
        )

    if 'await CgNotificationService.initialize();' not in source:
        source = source.replace(
            "  WidgetsFlutterBinding.ensureInitialized();\n",
            "  WidgetsFlutterBinding.ensureInitialized();\n"
            "  await CgNotificationService.initialize();\n"
            "  if (Platform.isWindows) await CgDesktopTray.initialize();\n",
            1,
        )

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_v12() -> bool:
    path = Path('lib/v12.dart')
    source = read(str(path))
    original = source

    if "import 'notification_service.dart';" not in source:
        source = source.replace(
            "import 'music_player.dart';\n",
            "import 'music_player.dart';\n"
            "import 'notification_service.dart';\n"
            "import 'permission_center.dart';\n",
            1,
        )

    if '_notificationClickSubscription' not in source:
        source = source.replace(
            "  StreamSubscription<Uri>? _linkSubscription;\n",
            "  StreamSubscription<Uri>? _linkSubscription;\n"
            "  StreamSubscription<String>? _notificationClickSubscription;\n",
            1,
        )

    bootstrap_old = """    await _listenLinks();
    unawaited(_prewarmAll());
  }
"""
    bootstrap_new = """    await _listenLinks();
    _notificationClickSubscription =
        CgNotificationService.tunnelClicks.listen(_openNotificationTunnel);
    final pendingTunnelId = CgNotificationService.consumePendingTunnelId();
    if (pendingTunnelId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openNotificationTunnel(pendingTunnelId));
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(CgPermissionCenter.maybePrompt(context, ru: widget.ru));
    });
    unawaited(_prewarmAll());
  }

  Future<void> _openNotificationTunnel(String tunnelId) async {
    final index = _tunnels.indexWhere((item) => item.id == tunnelId);
    if (index < 0 || !mounted) return;
    await _openTunnel(_tunnels[index]);
  }
"""
    if bootstrap_old in source:
        source = source.replace(bootstrap_old, bootstrap_new, 1)

    incoming_marker = """    final incoming = await CgMediaStore.cacheIncomingMessage(
      CgMessage.fromJson(raw),
    );
"""
    incoming_notify = incoming_marker + """    if (incoming.authorId != _profile?.id) {
      final tunnelIndexForNotification =
          _tunnels.indexWhere((item) => item.id == tunnelId);
      final notificationTitle = tunnelIndexForNotification < 0
          ? (widget.ru ? 'Новое сообщение' : 'New message')
          : _tunnels[tunnelIndexForNotification].displayName;
      final body = incoming.text.trim().isNotEmpty
          ? '${incoming.authorName}: ${incoming.text.trim()}'
          : '${incoming.authorName}: ${incoming.attachment?.name ?? (widget.ru ? 'Новое сообщение' : 'New message')}';
      unawaited(
        CgNotificationService.showMessage(
          messageId: incoming.id,
          tunnelId: tunnelId,
          title: notificationTitle,
          body: body,
        ),
      );
    }
"""
    if 'CgNotificationService.showMessage(' not in source:
        source = replace_once(
            source,
            incoming_marker,
            incoming_notify,
            'background message notification',
        )

    source = source.replace(
        """    _activeTunnelId = current.id;
    _markRead(current.id);
""",
        """    _activeTunnelId = current.id;
    CgNotificationService.setActiveTunnel(current.id);
    _markRead(current.id);
""",
        1,
    )
    source = source.replace(
        """    _activeTunnelId = null;
    _markRead(current.id);
""",
        """    _activeTunnelId = null;
    CgNotificationService.setActiveTunnel(null);
    _markRead(current.id);
""",
        1,
    )

    if '_notificationClickSubscription?.cancel()' not in source:
        source = source.replace(
            "    unawaited(_linkSubscription?.cancel());\n",
            "    unawaited(_linkSubscription?.cancel());\n"
            "    unawaited(_notificationClickSubscription?.cancel());\n",
            1,
        )

    source = source.replace("'Общайся без впн и рекламы.'", "'Связь без границ'", 1)
    source = source.replace("'Chat without VPN or ads.'", "'Connection without borders'", 1)
    if "widget.ru ? 'Общайся без впн и рекламы.' : 'Chat without VPN or ads.'" not in source:
        title_row_end = """                  ),
                ],
              ),
              AnimatedSize(
"""
        title_with_subtitle = """                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                widget.ru
                    ? 'Общайся без впн и рекламы.'
                    : 'Chat without VPN or ads.',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .58),
                ),
              ),
              AnimatedSize(
"""
        if title_row_end in source:
            source = source.replace(title_row_end, title_with_subtitle, 1)

    source = source.replace(
        "              Row(\n                children: <Widget>[\n",
        "              Row(\n                crossAxisAlignment: CrossAxisAlignment.center,\n"
        "                children: <Widget>[\n",
        1,
    )

    search_pattern = re.compile(
        r"""                          Expanded\(
                            flex: 4,
                            child: FilledButton\.tonalIcon\(
                              onPressed: _openSearch,
                              icon: const Icon\(Icons\.search_rounded\),
                              label: Text\(widget\.ru \? 'Поиск' : 'Search'\),
                            \),
                          \),
""",
        re.S,
    )
    search_replacement = """                          SizedBox(
                            width: 54,
                            height: 48,
                            child: Material(
                              color: Colors.white.withValues(alpha: .92),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: _openSearch,
                                borderRadius: BorderRadius.circular(16),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: scheme.primary,
                                  size: 25,
                                ),
                              ),
                            ),
                          ),
"""
    source, _ = search_pattern.subn(search_replacement, source, count=1)

    update_button = """      OutlinedButton.icon(
        onPressed: widget.onCheckUpdates,
        icon: const Icon(Icons.system_update_alt_rounded),
        label: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
      ),
      OutlinedButton.icon(
        onPressed: widget.onChangeLanguage,
"""
    update_replacement = """      OutlinedButton.icon(
        onPressed: widget.onCheckUpdates,
        icon: const Icon(Icons.system_update_alt_rounded),
        label: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => CgPermissionCenter.open(context, ru: widget.ru),
        icon: const Icon(Icons.admin_panel_settings_outlined),
        label: Text(widget.ru ? 'Доступы приложения' : 'App permissions'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.onChangeLanguage,
"""
    if update_button in source:
        source = source.replace(update_button, update_replacement, 1)

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_chat_scroll() -> bool:
    path = Path('lib/chat_screen.dart')
    source = read(str(path))
    original = source

    if 'bool get _isNearBottom' not in source:
        source = source.replace(
            """  String _attachmentKind(String name) {
""",
            """  bool get _isNearBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 120;
  }

  String _attachmentKind(String name) {
""",
            1,
        )

    source = source.replace(
        """  Future<void> _mergeMessages(List<Map<String, dynamic>> raw) async {
    final messages = <CgMessage>[..._tunnel.messages];
""",
        """  Future<void> _mergeMessages(List<Map<String, dynamic>> raw) async {
    final shouldFollowBottom = _isNearBottom;
    final messages = <CgMessage>[..._tunnel.messages];
""",
        1,
    )
    source = source.replace(
        """    _persist();
    _scrollToBottom();
  }

  Future<void> _handleControl""",
        """    _persist();
    if (shouldFollowBottom) _scrollToBottom();
  }

  Future<void> _handleControl""",
        1,
    )

    list_marker = """                : ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
"""
    list_new = """                : ListView.builder(
                    controller: _scroll,
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    dragStartBehavior: DragStartBehavior.down,
                    keyboardDismissBehavior:
"""
    if list_marker in source:
        source = source.replace(list_marker, list_new, 1)

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_call_hangup() -> bool:
    path = Path('lib/call_service.dart')
    source = read(str(path))
    original = source
    old = """  Future<void> _hangUp() async {
    if (_ended) return;
    await _sendSignal(<String, dynamic>{'action': 'call_end'});
    _finish(_connectedAt == null ? 'cancelled' : 'completed');
  }
"""
    new = """  Future<void> _hangUp() async {
    if (_ended) return;
    final status = _connectedAt == null ? 'cancelled' : 'completed';
    unawaited(
      _sendSignal(<String, dynamic>{'action': 'call_end'})
          .timeout(const Duration(milliseconds: 700))
          .catchError((_) {}),
    );
    _finish(status);
  }
"""
    if old in source:
        source = source.replace(old, new, 1)
    if source != original:
        write(str(path), source)
        return True
    return False


def patch_media_screen() -> bool:
    path = Path('lib/chat_media.dart')
    source = read(str(path))
    original = source

    source = source.replace(
        "${widget.ru ? 'Медиа Чернограма' : 'Chernogram media'}:",
        "${widget.ru ? 'Медиа' : 'Media'}:",
    )
    chip_old = """                    child: FilterChip(
                      selected: _filter == entry.$1,
                      avatar: Icon(entry.$3, size: 18),
                      label: Text(entry.$2),
"""
    chip_new = """                    child: FilterChip(
                      selected: _filter == entry.$1,
                      showCheckmark: false,
                      avatar: Icon(entry.$3, size: 18),
                      label: Text(entry.$2),
"""
    if chip_old in source:
        source = source.replace(chip_old, chip_new, 1)

    card_old = """                           return Card(
                             child: ListTile(
"""
    card_new = """                           return Padding(
                             padding: const EdgeInsets.only(bottom: 2),
                             child: Card(
                               child: ListTile(
"""
    if card_old in source:
        source = source.replace(card_old, card_new, 1)
        card_at = source.find(card_new)
        close_old = """                             ),
                           );
"""
        close_new = """                               ),
                             ),
                           );
"""
        close_at = source.find(close_old, card_at)
        if close_at >= 0:
            source = source[:close_at] + close_new + source[close_at + len(close_old):]

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_manifest() -> bool:
    path = Path('android/app/src/main/AndroidManifest.xml')
    if not path.exists():
        return False
    source = read(str(path))
    original = source
    permissions = [
        '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
        '    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />',
    ]
    insertion = '\n'.join(p for p in permissions if p not in source)
    if insertion:
        source = source.replace(
            '    <uses-permission android:name="android.permission.INTERNET" />',
            '    <uses-permission android:name="android.permission.INTERNET" />\n' + insertion,
            1,
        )
    source = source.replace(
        'android:windowSoftInputMode="adjustResize">',
        'android:windowSoftInputMode="adjustResize"\n'
        '            android:showWhenLocked="true"\n'
        '            android:turnScreenOn="true">',
    )
    if source != original:
        write(str(path), source)
        return True
    return False


def main() -> None:
    changed = False
    changed |= patch_main()
    changed |= patch_v12()
    changed |= patch_chat_scroll()
    changed |= patch_call_hangup()
    changed |= patch_media_screen()
    changed |= patch_manifest()
    print('Applied Chernogram 0.16.2 runtime and interface polish' if changed else 'Chernogram 0.16.2 runtime polish already applied')


if __name__ == '__main__':
    main()
