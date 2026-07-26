from pathlib import Path


for relative in (
    'android/app/src/main/res/values-v31/styles.xml',
    'android/app/src/main/res/values-night-v31/styles.xml',
):
    path = Path(relative)
    if not path.exists():
        continue
    text = path.read_text(encoding='utf-8')
    text = '\n'.join(
        line for line in text.splitlines()
        if 'postSplashScreenTheme' not in line
    ) + '\n'
    path.write_text(text, encoding='utf-8')

print('Removed unsupported postSplashScreenTheme attribute')
