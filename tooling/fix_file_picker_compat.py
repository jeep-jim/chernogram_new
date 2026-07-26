from pathlib import Path


def main() -> None:
    paths = [Path('lib/v06.dart'), Path('tooling/v06.dart')]
    for path in paths:
        if not path.exists():
            continue
        source = path.read_text(encoding='utf-8')
        updated = source.replace('FilePicker.pickFiles(', 'FilePicker.platform.pickFiles(')
        path.write_text(updated, encoding='utf-8')
        print(f'Patched {path}')


if __name__ == '__main__':
    main()
