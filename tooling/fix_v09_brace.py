from pathlib import Path


path = Path('lib/call_service.dart')
source = path.read_text(encoding='utf-8').rstrip()
if source.endswith(');'):
    path.write_text(source + '\n}\n', encoding='utf-8')
print('Verified call_service.dart closing brace')
