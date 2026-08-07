from pathlib import Path

from PIL import Image, ImageDraw


# Same striped heart/shield mark that is already used by the Android vector
# drawable.  We generate the .ico during CI so the Windows executable and every
# desktop shortcut use the real Chernogram mark instead of the old placeholder.
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


def render(size: int) -> Image.Image:
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    scale = size / 1080.0
    width = max(1, round(28 * scale))
    for x, segments, color in LINES:
        px = round(x * scale)
        for top, bottom in segments:
            y1 = round(top * scale)
            y2 = round(bottom * scale)
            draw.line((px, y1, px, y2), fill=color, width=width)
            radius = width // 2
            draw.ellipse((px - radius, y1 - radius, px + radius, y1 + radius), fill=color)
            draw.ellipse((px - radius, y2 - radius, px + radius, y2 + radius), fill=color)
    return image


out = Path('windows/runner/resources/app_icon.ico')
out.parent.mkdir(parents=True, exist_ok=True)
base = render(256)
base.save(
    out,
    format='ICO',
    sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print(f'Generated {out}')
