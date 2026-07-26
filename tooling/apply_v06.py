from pathlib import Path


def copy(source: str, target: str) -> None:
    source_path = Path(source)
    target_path = Path(target)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(source_path.read_text(encoding='utf-8'), encoding='utf-8')


def main() -> None:
    copy('tooling/v06_pubspec.yaml', 'pubspec.yaml')
    copy('tooling/v06_main.dart', 'lib/main.dart')
    copy('tooling/v06_manifest.xml', 'android/app/src/main/AndroidManifest.xml')
    copy('tooling/v06_icon_foreground.xml', 'android/app/src/main/res/drawable/ic_launcher_foreground.xml')
    copy('tooling/v06_launch_logo.xml', 'android/app/src/main/res/drawable/launch_logo.xml')
    copy('tooling/v06_launch_background.xml', 'android/app/src/main/res/drawable/launch_background.xml')
    copy('tooling/v06_launch_background.xml', 'android/app/src/main/res/drawable-v21/launch_background.xml')
    print('Applied Chernogram 0.6 source, manifest, icon and splash resources')


if __name__ == '__main__':
    main()
