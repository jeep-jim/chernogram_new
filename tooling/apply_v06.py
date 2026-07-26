from pathlib import Path


def main() -> None:
    Path('pubspec.yaml').write_text(Path('tooling/v06_pubspec.yaml').read_text(encoding='utf-8'), encoding='utf-8')
    print('Applied Chernogram 0.6 pubspec')


if __name__ == '__main__':
    main()
