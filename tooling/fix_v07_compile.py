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
        'final seconds = _reconnectAttempt.clamp(1, 8);',
        'final seconds = _reconnectAttempt.clamp(1, 8).toInt();',
    )
    replace(
        'lib/internet_core.dart',
        ".startClean()\n          .withWillQos(MqttQos.atLeastOnce);",
        '.startClean();',
    )
    print('Applied Chernogram 0.7 compile compatibility fixes')


if __name__ == '__main__':
    main()
