from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    replace(
        'lib/internet_core.dart',
        "    final signature = '${signal['action']}|${signal['from']}|${signal['sdp']?.hashCode}|${signal['candidate']?.hashCode}';",
        '    final signature = "${signal[\'action\']}|${signal[\'from\']}|${signal[\'sdp\']?.hashCode}|${signal[\'candidate\']?.hashCode}";',
    )

    replace(
        'lib/call_service.dart',
        """    if (sender.isEmpty || sender == _profileId) return;
    _adoptPeer(sender);
""",
        """    if (sender.isEmpty || sender == _profileId) return;
    if (_peerId != null && _peerId!.isNotEmpty && _peerId != sender) return;
    _adoptPeer(sender);
""",
    )

    call_file = Path('lib/call_service.dart')
    call_source = call_file.read_text(encoding='utf-8').rstrip()
    if call_source.endswith(');'):
        call_file.write_text(call_source + '\n}\n', encoding='utf-8')

    replace(
        'lib/chat_media.dart',
        'ChernogramColors.purple',
        'Theme.of(context).colorScheme.primary',
    )
    replace(
        'lib/chat_media.dart',
        """                            dimension: math.min(
                              MediaQuery.sizeOf(context).width - 34,
                              420,
                            ),
""",
        """                            dimension: math.min(
                              MediaQuery.sizeOf(context).width - 34,
                              420.0,
                            ).toDouble(),
""",
    )
    replace(
        'lib/chat_media.dart',
        """                            dimension: math.min(
                              MediaQuery.sizeOf(context).width - 36,
                              420,
                            ),
""",
        """                            dimension: math.min(
                              MediaQuery.sizeOf(context).width - 36,
                              420.0,
                            ).toDouble(),
""",
    )
    replace(
        'lib/chat_media.dart',
        """        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
""",
        """        enableAudio: true,
""",
    )

    print('Applied Chernogram 0.9 compile safeguards')


if __name__ == '__main__':
    main()
