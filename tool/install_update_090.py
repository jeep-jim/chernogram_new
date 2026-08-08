from pathlib import Path
import re


# 0.90 is a distribution/update release. Transport routing is untouched.
pubspec = Path('pubspec.yaml')
text = pubspec.read_text(encoding='utf-8')
if 'version: 0.89.0+89' not in text:
    raise SystemExit('Expected 0.89 version before 0.90 patch')
pubspec.write_text(text.replace('version: 0.89.0+89', 'version: 0.90.0+90', 1), encoding='utf-8')

# The install QR/share sheet must always point to the exact APK published by
# this release. This deliberately uses a versioned filename, not the obsolete
# chernogram-room.apk alias, so another device can see exactly what it installs.
settings = Path('lib/client_settings.dart')
text = settings.read_text(encoding='utf-8')
pattern = re.compile(
    r"const String cGAndroidInstallUrl =\s*\n\s*'[^']+';",
    re.MULTILINE,
)
replacement = (
    "const String cGAndroidInstallUrl =\n"
    "    'https://github.com/jeep-jim/chernogram_new/releases/download/"
    "latest-room-alpha/chernogram-android-0.90.apk';"
)
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit('cGAndroidInstallUrl definition not found')
settings.write_text(text, encoding='utf-8')

print('Chernogram 0.90 versioned install QR/share URL applied')
