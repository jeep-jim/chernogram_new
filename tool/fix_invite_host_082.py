from pathlib import Path


def replace_all(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old!r}')
    file.write_text(text.replace(old, new), encoding='utf-8')


replace_all('pubspec.yaml', 'version: 0.81.0+81', 'version: 0.82.0+82')
replace_all(
    'lib/chat_screen.dart',
    'https://jeep-jim.github.io/chernogram_new/',
    'https://raw.githack.com/jeep-jim/chernogram_new/main/docs/index.html',
)
replace_all(
    'lib/light/light_chat_app.dart',
    'https://jeep-jim.github.io/chernogram_new/',
    'https://raw.githack.com/jeep-jim/chernogram_new/main/docs/index.html',
)
replace_all(
    'android/app/src/main/AndroidManifest.xml',
    'android:host="jeep-jim.github.io"\n                    android:pathPrefix="/chernogram_new"',
    'android:host="raw.githack.com"\n                    android:pathPrefix="/jeep-jim/chernogram_new/main/docs/index.html"',
)

print('Invite host and version 0.82 applied')
