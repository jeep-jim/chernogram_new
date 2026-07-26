from pathlib import Path


def main() -> None:
    """Keep CI deterministic after the 0.8 source migration.

    Older releases patched Dart sources during every build. The 0.8 source is
    now committed in its final form, so repeated string replacements would
    duplicate imports and re-introduce obsolete UI text.
    """
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
    print('Chernogram 0.8 sources are ready; no legacy patches applied')


if __name__ == '__main__':
    main()
