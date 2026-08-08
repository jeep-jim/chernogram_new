from __future__ import annotations

import base64
from pathlib import Path

from PIL import Image, ImageDraw

LINES = [
    (300, [(430, 630)], '#B9A8FF'),
    (335, [(350, 704)], '#AE98FF'),
    (370, [(300, 410), (495, 760)], '#A087FF'),
    (405, [(260, 410), (495, 805)], '#9277FF'),
    (440, [(230, 410), (495, 838)], '#8668FF'),
    (475, [(210, 410), (495, 858)], '#7B5CFF'),
    (510, [(198, 868)], '#715FFB'),
    (545, [(192, 875)], '#666AF8'),
    (580, [(198, 868)], '#5B78F4'),
    (615, [(210, 410), (495, 858)], '#5088F1'),
    (650, [(230, 410), (495, 838)], '#4599EE'),
    (685, [(260, 410), (495, 805)], '#3BA9EC'),
    (720, [(300, 410), (495, 760)], '#31B7EC'),
    (755, [(350, 704)], '#27C1F3'),
    (790, [(430, 630)], '#20C7FF'),
]


def render_mask(size: int, *, scale_factor: float = 1.0) -> Image.Image:
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    base_scale = size / 1080.0 * scale_factor
    offset = (size - 1080.0 * base_scale) / 2.0
    width = max(1, round(28 * base_scale))
    for x, segments, color in LINES:
        px = round(offset + x * base_scale)
        for top, bottom in segments:
            y1 = round(offset + top * base_scale)
            y2 = round(offset + bottom * base_scale)
            draw.line((px, y1, px, y2), fill=color, width=width)
            radius = width // 2
            draw.ellipse((px - radius, y1 - radius, px + radius, y1 + radius), fill=color)
            draw.ellipse((px - radius, y2 - radius, px + radius, y2 + radius), fill=color)
    return image


def android_legacy(size: int) -> Image.Image:
    return render_mask(size, scale_factor=1.0)


# User-supplied ringtone, compactly stored as base64 so GitHub's text-only
# content API can carry the binary faithfully into CI.
encoded = Path('tool/chernogram_call_ring.b64').read_text(encoding='ascii').strip()
audio = base64.b64decode(encoded)
for path in (
    Path('assets/audio/incoming_call.mp3'),
    Path('android/app/src/main/res/raw/chernogram_call_ring.mp3'),
):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(audio)

# Windows EXE icon and tray icon: transparent mask only.
tray = render_mask(256, scale_factor=1.0)
windows_icon = Path('windows/runner/resources/app_icon.ico')
windows_icon.parent.mkdir(parents=True, exist_ok=True)
tray.save(
    windows_icon,
    format='ICO',
    sizes=[
        (16, 16), (20, 20), (24, 24), (32, 32),
        (40, 40), (48, 48), (64, 64), (128, 128), (256, 256),
    ],
)
tray_asset = Path('assets/icons/chernogram_tray.ico')
tray_asset.parent.mkdir(parents=True, exist_ok=True)
tray.save(
    tray_asset,
    format='ICO',
    sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

# Legacy Android launchers are regenerated at every density from the same mask.
for folder, size in {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}.items():
    out = Path('android/app/src/main/res') / folder / 'ic_launcher.png'
    out.parent.mkdir(parents=True, exist_ok=True)
    android_legacy(size).save(out, format='PNG')

print('Materialized user ringtone and exact Chernogram mask icons')
