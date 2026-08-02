from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


worker = Path('worker/impulse/src/index.ts')
text = worker.read_text(encoding='utf-8')
if not text.startswith('import { DurableObject }'):
    text = 'import { DurableObject } from "cloudflare:workers";\n\n' + text
worker.write_text(text, encoding='utf-8')

core = Path('lib/internet_core.dart')
text = core.read_text(encoding='utf-8')
old = '    if (_closed || _connecting || connected) return;\n'
if old in text:
    text = replace_once(
        text,
        old,
        '    if (_closed || _connecting || (_httpReady && _socket != null)) return;\n',
        'websocket reconnect condition',
    )
core.write_text(text, encoding='utf-8')

monitor = Path('lib/app_monitor.dart')
text = monitor.read_text(encoding='utf-8')
old = '    final monitored = recent.take(8).toList(growable: false);\n'
if old in text:
    text = replace_once(
        text,
        old,
        """    // Every saved direct contact must register with Impulse/FCM,
    // otherwise a quiet old dialog could not wake the phone.
    final monitored = recent.toList(growable: false);
""",
        'monitor every saved contact',
    )
monitor.write_text(text, encoding='utf-8')

print('Impulse build 74 follow-up applied.')
