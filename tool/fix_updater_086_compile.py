from pathlib import Path

path = Path('lib/update_service.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import 'package:ota_update/ota_update.dart';\n", '')
text = text.replace(
    "        throw const PlatformException(\n",
    "        throw PlatformException(\n",
    1,
)
old = '''          final content = entry.content;
          if (content is List<int>) {
            await output.writeAsBytes(content, flush: true);
          } else {
            throw const FormatException('Invalid file data in Windows package');
          }
'''
new = '''          await output.writeAsBytes(entry.content, flush: true);
'''
if old not in text:
    raise SystemExit('Archive content block not found')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

# Several older feature patches already import java.io.File in MainActivity.
# Keep exactly one import after composing the full 0.86 patch chain.
main = Path('android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt')
main_text = main.read_text(encoding='utf-8')
lines = main_text.splitlines()
seen_file_import = False
cleaned = []
for line in lines:
    if line.strip() == 'import java.io.File':
        if seen_file_import:
            continue
        seen_file_import = True
    cleaned.append(line)
main.write_text('\n'.join(cleaned) + '\n', encoding='utf-8')

print('Updater 0.86 compile fixes applied')
