#!/usr/bin/env python3
from pathlib import Path

path = Path('lib/svet_core.dart')
text = path.read_text(encoding='utf-8')
text = text.replace(
    'await _native.setMethodCallHandler(null);',
    '_native.setMethodCallHandler(null);',
)
text = text.replace(
    'FilePicker.platform.pickFiles(',
    'FilePicker.pickFiles(',
)
path.write_text(text, encoding='utf-8')
print('Patched lib/svet_core.dart')
