from pathlib import Path

path = Path('lib/chat_media.dart')
text = path.read_text(encoding='utf-8')
broken = '}\n\nclass CgInlineAttachment}\n\nclass CgInlineAttachment extends StatefulWidget {'
fixed = '}\n\nclass CgInlineAttachment extends StatefulWidget {'
if broken not in text:
    raise SystemExit('0.89 duplicate CgInlineAttachment marker not found')
path.write_text(text.replace(broken, fixed, 1), encoding='utf-8')
print('Android 0.89 chat_media compile structure fixed')
