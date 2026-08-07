from pathlib import Path

path = Path('lib/sound_service.dart')
text = path.read_text(encoding='utf-8')
if "import 'dart:async';" not in text:
    text = "import 'dart:async';\n\n" + text
path.write_text(text, encoding='utf-8')
print('Chernogram 0.85 compile fix applied')
