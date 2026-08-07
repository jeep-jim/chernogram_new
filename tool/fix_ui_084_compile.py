from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:180]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


# Named record type for Windows disk stats.
replace_once(
    'lib/chat_media.dart',
    '  static Future<(int free, int total)?> _windowsDriveStats() async {',
    '  static Future<({int free, int total})?> _windowsDriveStats() async {',
)

# ui_full_084 inserts the storage card immediately before the existing settings
# panel. Collapse the duplicated opening marker left by that insertion.
marker = (
    '          Padding(\n'
    '            padding: const EdgeInsets.symmetric(horizontal: 14),\n'
    '            child: LightGlass(\n'
)
light = Path('lib/light/light_chat_app.dart')
text = light.read_text(encoding='utf-8')
if marker + marker in text:
    text = text.replace(marker + marker, marker, 1)
else:
    raise SystemExit('Duplicate profile settings marker not found')
light.write_text(text, encoding='utf-8')

# The block replacement for the final push method retains the original class
# terminator. Remove only the redundant method terminator, not the class brace.
push = Path('lib/push_service.dart')
text = push.read_text(encoding='utf-8')
extra = '  }\n\n  }\n}'
if extra in text:
    text = text.replace(extra, '  }\n}', 1)
else:
    raise SystemExit('Redundant push-service closing brace not found')
push.write_text(text, encoding='utf-8')

print('Chernogram UI 0.84 compile fixes applied')
