from pathlib import Path
import re


def patch_text(path: str, transform) -> bool:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    updated = transform(source)
    if updated == source:
        return False
    file.write_text(updated, encoding='utf-8')
    print(f'Patched {path}')
    return True


def patch_brand() -> bool:
    def transform(source: str) -> str:
        # Keep the existing striped head and eye gaps. Remove the mouth gap.
        source = source.replace(
            "      if (normalizedX.abs() < .44) {\n"
            "        gaps.add((size.height * .625, size.height * .67));\n"
            "      }\n",
            "",
        )

        # Remove the expensive blurred duplicate stroke. It caused startup
        # instability on some Windows GPU/driver combinations.
        source = re.sub(
            r"\n      final glow = Paint\(\)\n"
            r"        \.\.style = PaintingStyle\.stroke\n"
            r"        \.\.strokeWidth = lineWidth \* 2\.25\n"
            r"        \.\.strokeCap = StrokeCap\.round\n"
            r"        \.\.color = const Color\(0xFF6E65FF\)\.withAlpha\(\(alpha \* \.22\)\.round\(\)\)\n"
            r"        \.\.maskFilter = MaskFilter\.blur\(BlurStyle\.normal, size\.width \* \.035\);",
            "",
            source,
            count=1,
        )
        source = source.replace(
            "          canvas.drawLine(Offset(x, cursor), Offset(x, gapStart), glow);\n",
            "",
        )
        source = source.replace(
            "        canvas.drawLine(Offset(x, cursor), Offset(x, animatedBottom), glow);\n",
            "",
        )

        # Nose and mouth were the two detail strokes. Eyes remain as gaps in
        # the vertical bars, so remove the detail block entirely.
        source = re.sub(
            r"\n    final detailProgress = \(\(progress - \.46\) / \.54\)\.clamp\(0\.0, 1\.0\)\.toDouble\(\);\n"
            r"    if \(detailProgress > 0\) \{.*?\n    \}\n",
            "\n",
            source,
            count=1,
            flags=re.S,
        )
        return source

    return patch_text('lib/brand.dart', transform)


def patch_native_icons() -> bool:
    changed = False
    # Same striped shield/head everywhere. Only eye gaps, no ears, nose or mouth.
    vector = '''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1080"
    android:viewportHeight="1080">
    <path android:strokeColor="#B9A8FF" android:strokeWidth="38" android:strokeLineCap="round" android:pathData="M260,390 L260,700 M320,300 L320,785 M380,245 L380,835 M440,215 L440,870 M500,195 L500,895" />
    <path android:strokeColor="#7B5CFF" android:strokeWidth="38" android:strokeLineCap="round" android:pathData="M560,195 L560,895 M620,215 L620,870 M680,245 L680,835" />
    <path android:strokeColor="#20C7FF" android:strokeWidth="38" android:strokeLineCap="round" android:pathData="M740,300 L740,785 M800,390 L800,700" />
    <path android:strokeColor="#090D18" android:strokeWidth="54" android:strokeLineCap="round" android:pathData="M300,440 L465,440 M615,440 L780,440" />
</vector>\n'''
    splash = vector.replace('android:width="108dp"', 'android:width="164dp"').replace(
        'android:height="108dp"', 'android:height="164dp"'
    )
    for path, content in (
        ('android/app/src/main/res/drawable/chernogram_launcher_icon.xml', vector),
        ('android/app/src/main/res/drawable/launch_logo.xml', splash),
        ('android/app/src/main/res/drawable/ic_launcher_foreground.xml', vector),
    ):
        file = Path(path)
        original = file.read_text(encoding='utf-8') if file.exists() else ''
        if original != content:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(content, encoding='utf-8')
            print(f'Patched {path}')
            changed = True

    # Regenerate the Windows icon with a transparent background and the same
    # striped head silhouette used in the Flutter header.
    try:
        from PIL import Image, ImageDraw

        destination = Path('windows/runner/resources/app_icon.ico')
        if destination.parent.exists():
            size = 256
            image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            colors = [
                (185, 168, 255, 255),
                (123, 92, 255, 255),
                (32, 199, 255, 255),
            ]
            count = 11
            for index in range(count):
                t = index / (count - 1)
                nx = t * 2 - 1
                x = int(size * (.18 + t * .64))
                ellipse = max(0.0, 1.0 - nx * nx) ** .5
                top = int(size * (.19 + (1 - ellipse) * .12))
                bottom = int(size * (.50 + ellipse * .36 - abs(nx) * .03))
                color = colors[min(2, int(t * 3))]
                width = 8
                gaps = []
                if .17 < abs(nx) < .72:
                    gaps.append((int(size * .39), int(size * .46)))
                cursor = top
                for gap_start, gap_end in gaps:
                    if gap_start > cursor:
                        draw.line((x, cursor, x, gap_start), fill=color, width=width)
                    cursor = max(cursor, gap_end)
                if cursor < bottom:
                    draw.line((x, cursor, x, bottom), fill=color, width=width)
            image.save(
                destination,
                format='ICO',
                sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
            )
            print(f'Patched {destination}')
            changed = True
    except Exception as error:
        print(f'Windows icon regeneration skipped: {error}')
    return changed


def patch_version() -> bool:
    changed = False

    def pubspec(source: str) -> str:
        return re.sub(
            r'^version:\s*0\.16\.[0-9]+\+[0-9]+\s*$',
            'version: 0.16.8+39',
            source,
            count=1,
            flags=re.M,
        )

    changed |= patch_text('pubspec.yaml', pubspec)

    def docs(source: str) -> str:
        return re.sub(r'chernogram\.apk\?v=\d+', 'chernogram.apk?v=39', source)

    changed |= patch_text('docs/index.html', docs)

    roadmap = Path('roadmap.md')
    source = roadmap.read_text(encoding='utf-8')
    if '`0.16.8+39`' not in source:
        source = source.rstrip() + (
            '\n- `0.16.8+39` — из существующего полосатого лица удалены нос и рот; '
            'оставлены только глаза и форма головы. Иконка, шапка, splash и Windows ICO '
            'приведены к одному виду. Убрано тяжёлое GPU-размытие первого кадра Windows.\n'
        )
        roadmap.write_text(source, encoding='utf-8')
        changed = True
        print('Patched roadmap.md')
    return changed


def main() -> None:
    changed = False
    changed |= patch_brand()
    changed |= patch_native_icons()
    changed |= patch_version()
    print('Cernogram 0.16.8 logo and Windows startup fixes applied' if changed else '0.16.8 already applied')


if __name__ == '__main__':
    main()
