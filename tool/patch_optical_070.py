from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


app = Path('lib/optical/optical_app.dart')
text = app.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    trailing: Flexible(
      child: Text(
""",
    """    trailing: SizedBox(
      width: 170,
      child: Text(
""",
    'LabRow trailing width',
)
app.write_text(text, encoding='utf-8')

transfer = Path('lib/optical/optical_transfer_screens.dart')
text = transfer.read_text(encoding='utf-8')
text = text.replace(
    'min(MediaQuery.sizeOf(context).width - 76, 330)',
    'min(MediaQuery.sizeOf(context).width - 76, 330.0)',
)
text = text.replace(
    'min(MediaQuery.sizeOf(context).width - 42, 390)',
    'min(MediaQuery.sizeOf(context).width - 42, 390.0)',
)
transfer.write_text(text, encoding='utf-8')

codec = Path('lib/optical/optical_codec.dart')
text = codec.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    final count = (packed.length / frameChunkBytes).ceil().clamp(1, 1 << 30);
""",
    """    final count = (packed.length / frameChunkBytes)
        .ceil()
        .clamp(1, 1 << 30)
        .toInt();
""",
    'frame count integer',
)
codec.write_text(text, encoding='utf-8')

print('Optical build 70 UI patch applied.')
