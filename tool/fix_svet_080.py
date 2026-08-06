#!/usr/bin/env python3
from pathlib import Path

core_path = Path('lib/svet_core.dart')
core = core_path.read_text(encoding='utf-8')
core = core.replace(
    'await _native.setMethodCallHandler(null);',
    '_native.setMethodCallHandler(null);',
)
core = core.replace(
    'FilePicker.platform.pickFiles(',
    'FilePicker.pickFiles(',
)
core = core.replace(
    "'${base.path}${separator}SVET${separator}${_safeFileName(senderName)}_$stamp'",
    "'${base.path}${separator}SVET$separator${_safeFileName(senderName)}_$stamp'",
)
core_path.write_text(core, encoding='utf-8')

main_path = Path('lib/main.dart')
main = main_path.read_text(encoding='utf-8')
main = main.replace('separatorBuilder: (_, __) =>', 'separatorBuilder: (_, _) =>')
main = main.replace('errorBuilder: (_, __, ___) =>', 'errorBuilder: (_, _, _) =>')
main_path.write_text(main, encoding='utf-8')

print('Patched SVET source')
