from pathlib import Path


MANIFEST = Path('android/app/src/main/AndroidManifest.xml')


def main() -> None:
    source = MANIFEST.read_text(encoding='utf-8')
    original = source
    source = source.replace(
        '''        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:exported="false"
            android:stopWithTask="false"
            android:foregroundServiceType="dataSync" />''',
        '''        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:exported="true"
            android:stopWithTask="false"
            android:foregroundServiceType="dataSync" />''',
    )
    if source != original:
        MANIFEST.write_text(source, encoding='utf-8')
        print('Aligned Android background service manifest attributes')
    else:
        print('Android background service manifest already aligned')


if __name__ == '__main__':
    main()
