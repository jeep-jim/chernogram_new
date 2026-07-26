from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        source = source.replace(old, new)
        file.write_text(source, encoding='utf-8')


def main() -> None:
    replace(
        'lib/internet_core.dart',
        "DateTime.now().toUtc().difference(sentAt.toUtc()).abs() >\n            const Duration(minutes: 2)",
        "DateTime.now().toUtc().difference(sentAt.toUtc()).inSeconds.abs() > 120",
    )

    replace(
        'lib/chat_screen.dart',
        "  Future<void> _startCall(bool video) async {\n    final callId = CgIds.random(22);",
        "  Future<void> _startCall(bool video) async {\n"
        "    if (_session == null || !_session!.connected) {\n"
        "      unawaited(_connect());\n"
        "      if (mounted) {\n"
        "        ScaffoldMessenger.of(context).showSnackBar(\n"
        "          SnackBar(\n"
        "            content: Text(\n"
        "              widget.ru\n"
        "                  ? 'Защищённый канал ещё подключается. Подождите пару секунд и повторите звонок.'\n"
        "                  : 'The secure channel is still connecting. Wait a few seconds and try the call again.',\n"
        "            ),\n"
        "          ),\n"
        "        );\n"
        "      }\n"
        "      return;\n"
        "    }\n"
        "    final callId = CgIds.random(22);",
    )

    status_block = """  String get _statusText {
    if (_networkState == 'connected') {
      return widget.ru
          ? 'Интернет • онлайн $_onlinePeers'
          : 'Internet • $_onlinePeers online';
    }
    if (_networkState == 'queued') {
      return widget.ru ? 'Сообщение в очереди' : 'Message queued';
    }
    if (_networkState == 'error' || _networkState == 'disconnected') {
      return widget.ru ? 'Переподключение…' : 'Reconnecting…';
    }
    return widget.ru ? 'Подключение…' : 'Connecting…';
  }
"""
    if '_connectionBannerText' not in Path('lib/chat_screen.dart').read_text(encoding='utf-8'):
        replace(
            'lib/chat_screen.dart',
            status_block,
            status_block
            + """
  String get _connectionBannerText {
    if (_networkState == 'queued') {
      return widget.ru
          ? 'Сообщение сохранено. Отправим автоматически после восстановления связи.'
          : 'Message saved. It will be sent automatically when the connection returns.';
    }
    if (_networkState == 'error' || _networkState == 'disconnected') {
      return widget.ru
          ? 'Защищённый канал временно недоступен. Переподключаемся через обычный HTTPS-порт 443…'
          : 'The secure channel is temporarily unavailable. Reconnecting over standard HTTPS port 443…';
    }
    return widget.ru
        ? 'Подключаем защищённый интернет-канал…'
        : 'Connecting the secure internet channel…';
  }
""",
        )

    replace(
        'lib/chat_screen.dart',
        '_networkError ?? _statusText',
        '_connectionBannerText',
    )

    replace(
        'lib/v07.dart',
        "import 'package:mobile_scanner/mobile_scanner.dart';",
        "import 'package:mobile_scanner/mobile_scanner.dart';\n"
        "import 'package:package_info_plus/package_info_plus.dart';",
    )
    replace(
        'lib/v07.dart',
        "  String? _avatarBase64;\n\n  @override\n  void initState() {\n    super.initState();\n    _avatarBase64 = widget.profile.avatarBase64;\n  }",
        "  String? _avatarBase64;\n"
        "  String _version = '…';\n\n"
        "  @override\n"
        "  void initState() {\n"
        "    super.initState();\n"
        "    _avatarBase64 = widget.profile.avatarBase64;\n"
        "    unawaited(_loadVersion());\n"
        "  }\n\n"
        "  Future<void> _loadVersion() async {\n"
        "    final info = await PackageInfo.fromPlatform();\n"
        "    if (!mounted) return;\n"
        "    setState(() => _version = '${info.version} (${info.buildNumber})');\n"
        "  }",
    )

    update_button = """          OutlinedButton.icon(
            onPressed: widget.onCheckUpdates,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
          ),
"""
    if "Версия $_version" not in Path('lib/v07.dart').read_text(encoding='utf-8'):
        replace(
            'lib/v07.dart',
            update_button,
            update_button
            + """          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                widget.ru ? 'Версия $_version' : 'Version $_version',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .48),
                ),
              ),
            ),
          ),
""",
        )

    print('Applied Chernogram 0.7.2 transport and UX compatibility fixes')


if __name__ == '__main__':
    main()
