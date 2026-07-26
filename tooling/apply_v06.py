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

    for file_name in ('lib/v06.dart', 'tooling/v06.dart'):
        path = Path(file_name)
        if not path.exists():
            continue
        source = path.read_text(encoding='utf-8')
        source = source.replace('FilePicker.pickFiles(', 'FilePicker.platform.pickFiles(')
        path.write_text(source, encoding='utf-8')

    print('Applied Chernogram 0.6 source, manifest, icon, splash and FilePicker compatibility')


if __name__ == '__main__':
    main()
