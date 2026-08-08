from pathlib import Path

path = Path('lib/client_settings.dart')
text = path.read_text(encoding='utf-8')
old = 'latest-room-alpha/chernogram-android-0.90.apk'
new = 'latest-room-alpha/chernogram-android-0.91.apk'
if old not in text:
    raise SystemExit('Android 0.90 install URL not found before 0.91 release')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Chernogram 0.91 install QR/share URL applied')
