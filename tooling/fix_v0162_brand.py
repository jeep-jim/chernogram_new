from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    Path(path).write_text(source, encoding='utf-8')


def patch_brand() -> bool:
    path = Path('lib/brand.dart')
    source = read(str(path))
    original = source
    marker = 'class ChernogramLogo extends StatelessWidget {'
    index = source.find(marker)
    if index < 0:
        raise RuntimeError('Brand logo marker was not found')

    brand = r'''class ChernogramLogo extends StatelessWidget {
  final double size;
  final bool withPlate;
  final double phase;

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
    this.phase = 0,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Transform.rotate(
      angle: phase * .12,
      child: CustomPaint(
        size: Size.square(withPlate ? size * .72 : size),
        painter: _ChernogramMarkPainter(phase: phase),
      ),
    );
    if (!withPlate) return mark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .29),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF181D39), Color(0xFF090B18)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF6F5BFF).withValues(alpha: .28 + phase * .08),
            blurRadius: size * (.28 + phase * .06),
          ),
        ],
      ),
      child: mark,
    );
  }
}

class _ChernogramMarkPainter extends CustomPainter {
  final double phase;

  const _ChernogramMarkPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final stroke = size.width * .115;
    final orbit = Rect.fromCircle(center: center, radius: size.width * .34);
    final gradient = const SweepGradient(
      colors: <Color>[
        Color(0xFF8E7BFF),
        Color(0xFF4E6DFF),
        Color(0xFF16D4FF),
        Color(0xFF8E7BFF),
      ],
    ).createShader(rect);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke * 1.5
      ..shader = gradient
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .07);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = gradient;

    canvas.drawArc(orbit, -.25, 4.72, false, glow);
    canvas.drawArc(orbit, -.25, 4.72, false, line);

    final tail = Path()
      ..moveTo(size.width * .27, size.height * .68)
      ..quadraticBezierTo(
        size.width * .18,
        size.height * .83,
        size.width * .20,
        size.height * .91,
      )
      ..quadraticBezierTo(
        size.width * .36,
        size.height * .86,
        size.width * .44,
        size.height * .77,
      );
    canvas.drawPath(tail, glow);
    canvas.drawPath(tail, line);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke * .46
      ..color = const Color(0xFFBDEFFF);
    canvas.drawLine(
      Offset(size.width * .53, size.height * .48),
      Offset(size.width * .72, size.height * .48),
      inner,
    );

    final pulse = 1 + phase * .18;
    canvas.drawCircle(
      Offset(size.width * .76, size.height * .48),
      size.width * .07 * pulse,
      Paint()..color = const Color(0xFFBDEFFF),
    );
    canvas.drawCircle(
      Offset(size.width * .36, size.height * .37),
      size.width * .045,
      Paint()..color = const Color(0xFF8E7BFF),
    );
  }

  @override
  bool shouldRepaint(covariant _ChernogramMarkPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class BrandHeader extends StatelessWidget {
  final String? subtitle;

  const BrandHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const ChernogramLogo(size: 34, withPlate: true),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Чернограм',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.55,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .46),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

class ChernogramAnimatedIntro extends StatefulWidget {
  final bool ru;
  final VoidCallback onDone;

  const ChernogramAnimatedIntro({
    super.key,
    required this.ru,
    required this.onDone,
  });

  @override
  State<ChernogramAnimatedIntro> createState() =>
      _ChernogramAnimatedIntroState();
}

class _ChernogramAnimatedIntroState extends State<ChernogramAnimatedIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final curved = Curves.easeOutBack.transform(
                _controller.value.clamp(0.0, 1.0),
              );
              final pulse = (.5 - (.5 - _controller.value).abs()) * 2;
              return Opacity(
                opacity: Curves.easeOut.transform(_controller.value),
                child: Transform.scale(
                  scale: .72 + curved * .28,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ChernogramLogo(
                        size: 132,
                        withPlate: true,
                        phase: pulse,
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Чернограм',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.ru
                            ? 'Общайся без впн и рекламы'
                            : 'Chat without VPN or ads',
                        style: const TextStyle(
                          color: ChernogramColors.goldLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}
'''
    source = source[:index] + brand
    if source != original:
        write(str(path), source)
        return True
    return False


def create_brand_icons() -> bool:
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return False

    def render(size: int):
        image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        pad = size * .045
        draw.rounded_rectangle(
            (pad, pad, size - pad, size - pad),
            radius=size * .27,
            fill=(9, 11, 24, 255),
        )
        box = (size * .21, size * .19, size * .79, size * .77)
        width = max(2, int(size * .105))
        draw.arc(box, start=-15, end=255, fill=(119, 94, 255, 255), width=width)
        draw.arc(
            (size * .235, size * .215, size * .765, size * .745),
            start=5,
            end=270,
            fill=(26, 205, 255, 255),
            width=max(1, int(size * .043)),
        )
        tail = [
            (size * .28, size * .68),
            (size * .19, size * .88),
            (size * .43, size * .76),
        ]
        draw.line(tail, fill=(87, 113, 255, 255), width=width, joint='curve')
        draw.line(
            (size * .52, size * .48, size * .70, size * .48),
            fill=(190, 240, 255, 255),
            width=max(2, int(size * .045)),
        )
        radius = size * .07
        cx, cy = size * .76, size * .48
        draw.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), fill=(190, 240, 255, 255))
        radius2 = size * .043
        cx2, cy2 = size * .36, size * .37
        draw.ellipse((cx2-radius2, cy2-radius2, cx2+radius2, cy2+radius2), fill=(142, 123, 255, 255))
        return image

    assets = Path('assets/branding')
    assets.mkdir(parents=True, exist_ok=True)
    render(512).save(assets / 'chernogram_logo.png')
    render(256).save(
        assets / 'chernogram_tray.ico',
        format='ICO',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    windows = Path('windows/runner/resources/app_icon.ico')
    if windows.parent.exists():
        render(256).save(
            windows,
            format='ICO',
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )

    vector = Path('android/app/src/main/res/drawable/chernogram_launcher_icon.xml')
    if vector.parent.exists():
        vector.write_text(
            '''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1080"
    android:viewportHeight="1080">
    <path android:fillColor="#090B18"
        android:pathData="M170,70 H910 A100,100 0,0 1,1010 170 V910 A100,100 0,0 1,910 1010 H170 A100,100 0,0 1,70 910 V170 A100,100 0,0 1,170 70 Z" />
    <path android:fillColor="@android:color/transparent"
        android:strokeColor="#775EFF" android:strokeWidth="118"
        android:strokeLineCap="round"
        android:pathData="M790,285 C700,205 560,190 438,240 C300,296 228,435 252,574 C274,706 378,808 512,830 C624,849 734,812 804,732" />
    <path android:fillColor="@android:color/transparent"
        android:strokeColor="#1ACDFF" android:strokeWidth="48"
        android:strokeLineCap="round"
        android:pathData="M780,292 C696,232 580,218 478,258 C360,304 296,424 316,544 C334,657 422,742 536,760 C632,775 722,744 780,680" />
    <path android:fillColor="@android:color/transparent"
        android:strokeColor="#6574FF" android:strokeWidth="112"
        android:strokeLineCap="round" android:strokeLineJoin="round"
        android:pathData="M330,690 L220,900 L448,775" />
    <path android:fillColor="@android:color/transparent"
        android:strokeColor="#BDEFFF" android:strokeWidth="48"
        android:strokeLineCap="round" android:pathData="M545,520 L720,520" />
    <path android:fillColor="#BDEFFF"
        android:pathData="M790,520 A72,72 0,1 1,646 520 A72,72 0,1 1,790 520" />
    <path android:fillColor="#8E7BFF"
        android:pathData="M435,400 A46,46 0,1 1,343 400 A46,46 0,1 1,435 400" />
</vector>
''',
            encoding='utf-8',
        )
    return True


def main() -> None:
    changed = patch_brand()
    changed |= create_brand_icons()
    print('Applied Chernogram 0.16.2 brand and icons' if changed else 'Chernogram 0.16.2 brand already applied')


if __name__ == '__main__':
    main()
