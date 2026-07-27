from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    Path(path).write_text(source, encoding='utf-8')


def replace(path: str, old: str, new: str) -> None:
    source = read(path)
    if old in source:
        write(path, source.replace(old, new))


def patch_pubspec() -> None:
    path = Path('pubspec.yaml')
    source = path.read_text(encoding='utf-8')
    if 'just_audio_windows:' not in source:
        source = source.replace(
            '  just_audio: ^0.10.6\n',
            '  just_audio: ^0.10.6\n  just_audio_windows: ^0.2.3\n',
        )
    if 'audio_service_win:' not in source:
        source = source.replace(
            '  audio_service: ^0.18.18\n',
            '  audio_service: ^0.18.18\n  audio_service_win: ^0.0.3\n',
        )
    path.write_text(source, encoding='utf-8')


def patch_main() -> None:
    path = Path('lib/main.dart')
    source = path.read_text(encoding='utf-8')
    if "import 'dart:io';" not in source:
        source = source.replace(
            "import 'dart:async';\n",
            "import 'dart:async';\nimport 'dart:io';\n",
            1,
        )
    source = source.replace(
        """  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.chernogram.audio',
    androidNotificationChannelName: 'Музыка Чернограма',
    androidNotificationOngoing: true,
  );
""",
        """  if (Platform.isAndroid || Platform.isIOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.chernogram.audio',
      androidNotificationChannelName: 'Музыка Чернограма',
      androidNotificationOngoing: true,
    );
  }
""",
    )
    path.write_text(source, encoding='utf-8')


def patch_desktop_guards() -> None:
    path = Path('lib/v07.dart')
    source = path.read_text(encoding='utf-8')
    if "import 'dart:io';" not in source:
        source = source.replace(
            "import 'dart:convert';\n",
            "import 'dart:convert';\nimport 'dart:io';\n",
            1,
        )
    source = source.replace(
        """  Future<void> _inviteFromPhoneBook() async {
    final allowed = await FlutterContacts.requestPermission();
""",
        """  Future<void> _inviteFromPhoneBook() async {
    if (Platform.isWindows) {
      await _inviteViaMessengers();
      return;
    }
    final allowed = await FlutterContacts.requestPermission();
""",
    )
    path.write_text(source, encoding='utf-8')


def patch_runner() -> None:
    main_cpp = Path('windows/runner/main.cpp')
    if main_cpp.exists():
        source = main_cpp.read_text(encoding='utf-8')
        source = source.replace(
            'Win32Window::Size size(1280, 720);',
            'Win32Window::Size size(520, 900);',
        )
        source = re.sub(
            r'window\.Create\(L"[^"]*", origin, size\)',
            'window.Create(L"\\u0427\\u0435\\u0440\\u043d\\u043e\\u0433\\u0440\\u0430\\u043c", origin, size)',
            source,
        )
        main_cpp.write_text(source, encoding='utf-8')

    rc = Path('windows/runner/Runner.rc')
    if rc.exists():
        source = rc.read_text(encoding='utf-8')
        source = source.replace('VALUE "FileDescription", "chernogram"',
                                'VALUE "FileDescription", "Chernogram"')
        source = source.replace('VALUE "ProductName", "chernogram"',
                                'VALUE "ProductName", "Chernogram"')
        rc.write_text(source, encoding='utf-8')


def create_icon() -> None:
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return

    destination = Path('windows/runner/resources/app_icon.ico')
    destination.parent.mkdir(parents=True, exist_ok=True)
    size = 256
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        (10, 10, size - 10, size - 10),
        radius=58,
        fill=(9, 13, 24, 255),
        outline=(124, 92, 255, 255),
        width=5,
    )
    arc_box = (50, 46, 206, 202)
    draw.arc(arc_box, start=35, end=318, fill=(156, 134, 255, 255), width=25)
    draw.arc((60, 56, 196, 192), start=42, end=312, fill=(25, 200, 255, 255), width=8)
    draw.line((132, 128, 204, 128), fill=(9, 13, 24, 255), width=27)
    draw.ellipse((170, 116, 194, 140), fill=(141, 222, 255, 255))
    image.save(
        destination,
        format='ICO',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main() -> None:
    patch_pubspec()
    patch_main()
    patch_desktop_guards()
    patch_runner()
    create_icon()
    print('Applied Chernogram Windows desktop compatibility')


if __name__ == '__main__':
    main()
