from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:180]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


# The first patch intentionally uses simple string transforms. Move public
# relay cleanup from the socket reconnect function into the real session close.
replace_once(
    'lib/internet_core.dart',
    '    await _socketSubscription?.cancel();\n'
    '    await _publicPacketSubscription?.cancel();\n'
    '    await _publicStatusSubscription?.cancel();\n'
    '    await _publicRelay?.close();\n'
    '    final old = _socket;\n',
    '    await _socketSubscription?.cancel();\n'
    '    final old = _socket;\n',
)
replace_once(
    'lib/internet_core.dart',
    '    _outboxTimer?.cancel();\n'
    '    await _socketSubscription?.cancel();\n'
    '    try {\n'
    '      await _socket?.close();\n',
    '    _outboxTimer?.cancel();\n'
    '    await _socketSubscription?.cancel();\n'
    '    await _publicPacketSubscription?.cancel();\n'
    '    await _publicStatusSubscription?.cancel();\n'
    '    await _publicRelay?.close();\n'
    '    try {\n'
    '      await _socket?.close();\n',
)
replace_once(
    'lib/internet_core.dart',
    "    } catch (_) {\n"
    "      _httpReady = false;\n"
    "      _emit('status', const <String, dynamic>{\n"
    "        'state': 'queued',\n"
    "        'transport': 'impulse_worker',\n"
    "      });\n"
    "      _scheduleReconnect();\n"
    "    } finally {\n",
    "    } catch (_) {\n"
    "      if (_configured) _httpReady = false;\n"
    "      _emit('status', <String, dynamic>{\n"
    "        'state': 'queued',\n"
    "        'transport': _configured ? 'impulse_worker' : 'public_mqtt',\n"
    "      });\n"
    "      _scheduleReconnect();\n"
    "    } finally {\n",
)

# Relocate the installation QR into Profile even if a generic UI marker in an
# earlier page was matched by the first patch.
path = Path('lib/light/light_chat_app.dart')
text = path.read_text(encoding='utf-8')
qr_title = "                  const Text(\n                    'QR для установки',"
qr_pos = text.find(qr_title)
if qr_pos < 0:
    raise SystemExit('Installation QR block not found')
qr_start = text.rfind('          Padding(\n', 0, qr_pos)
next_marker = (
    '          Padding(\n'
    '            padding: const EdgeInsets.symmetric(horizontal: 14),\n'
    '            child: LightGlass(\n'
)
qr_end = text.find(next_marker, qr_pos)
if qr_start < 0 or qr_end < 0:
    raise SystemExit('Unable to isolate installation QR block')
qr_block = text[qr_start:qr_end]
text = text[:qr_start] + text[qr_end:]
profile_pos = text.find('class _ProfilePage extends StatelessWidget {')
if profile_pos < 0:
    raise SystemExit('Profile page not found')
profile_marker = text.find(next_marker, profile_pos)
if profile_marker < 0:
    raise SystemExit('Profile settings marker not found')
text = text[:profile_marker] + qr_block + text[profile_marker:]
path.write_text(text, encoding='utf-8')

print('Minimal room chat 0.81 follow-up fixes applied')
