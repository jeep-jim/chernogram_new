from base64 import b64decode
from pathlib import Path


PARTS = [Path(f'assets/audio/incoming_call.part{index}') for index in range(1, 7)]
FLUTTER_TARGET = Path('assets/audio/chernogram_incoming.mp3')
ANDROID_TARGET = Path('android/app/src/main/res/raw/chernogram_incoming.mp3')
KEEP_TARGET = Path('android/app/src/main/res/values/chernogram_keep.xml')


def ringtone_bytes() -> bytes:
    missing = [str(path) for path in PARTS if not path.exists()]
    if missing:
        raise RuntimeError(f'Missing ringtone chunks: {missing}')
    encoded = ''.join(''.join(path.read_text(encoding='utf-8').split()) for path in PARTS)
    data = b64decode(encoded, validate=True)
    if len(data) < 100_000:
        raise RuntimeError(f'Ringtone is unexpectedly small: {len(data)} bytes')
    if not (data.startswith(b'ID3') or data[:2] in (b'\xff\xfb', b'\xff\xf3', b'\xff\xf2')):
        raise RuntimeError('Ringtone does not look like an MP3 file')
    return data


def write_if_changed(path: Path, data: bytes) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        return False
    path.write_bytes(data)
    return True


def main() -> None:
    data = ringtone_bytes()
    changed = write_if_changed(FLUTTER_TARGET, data)
    changed |= write_if_changed(ANDROID_TARGET, data)

    keep_xml = '''<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@raw/chernogram_incoming,@drawable/chernogram_launcher_icon" />
'''
    KEEP_TARGET.parent.mkdir(parents=True, exist_ok=True)
    if not KEEP_TARGET.exists() or KEEP_TARGET.read_text(encoding='utf-8') != keep_xml:
        KEEP_TARGET.write_text(keep_xml, encoding='utf-8')
        changed = True

    print(
        f'Materialized Chernogram ringtone: {len(data)} bytes'
        if changed
        else f'Chernogram ringtone already materialized: {len(data)} bytes'
    )


if __name__ == '__main__':
    main()
