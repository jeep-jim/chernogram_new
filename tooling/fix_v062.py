from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def fix_pubspec(path: str) -> None:
    source = read(path)
    source = re.sub(
        r"\n  assets:\n(?:    - assets/branding/[^\n]+\n?)+",
        "\n",
        source,
    )
    source = re.sub(r"^version:\s*.*$", "version: 0.6.2+9", source, flags=re.M)
    write(path, source.rstrip() + "\n")


def fix_brand() -> None:
    path = 'lib/brand.dart'
    source = read(path)

    static_logo = r'''class ChernogramLogo extends StatelessWidget {
  final double size;
  final bool withPlate;

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(withPlate ? size * .82 : size),
      painter: const _ChernogramMarkPainter(),
    );

    if (!withPlate) return mark;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ChernogramColors.background,
        borderRadius: BorderRadius.circular(size * .23),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: mark,
    );
  }
}

class _ChernogramMarkPainter extends CustomPainter {
  const _ChernogramMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _paintChernogramMark(canvas, size, progress: 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ChernogramAnimatedIntro'''

    source, count = re.subn(
        r'class ChernogramLogo extends StatelessWidget \{.*?\n\}\n\nclass ChernogramAnimatedIntro',
        static_logo,
        source,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError('Could not replace ChernogramLogo block')

    start = source.index('class _AnimatedLogoPainter extends CustomPainter')
    end = source.index('\nclass BrandHeader extends StatelessWidget', start)
    animated_painter = r'''class _AnimatedLogoPainter extends CustomPainter {
  final double progress;

  const _AnimatedLogoPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    _paintChernogramMark(canvas, size, progress: progress);
  }

  @override
  bool shouldRepaint(covariant _AnimatedLogoPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

void _paintChernogramMark(
  Canvas canvas,
  Size size, {
  required double progress,
}) {
  final w = size.width;
  final h = size.height;
  final center = Offset(w / 2, h / 2);

  double segment(double start, double end) =>
      ((progress - start) / (end - start)).clamp(0.0, 1.0);

  final rearProgress = Curves.easeOutBack.transform(segment(0, .58));
  final goldProgress = Curves.easeOutBack.transform(segment(.14, .76));
  final cutProgress = Curves.easeOutCubic.transform(segment(.42, .88));
  final glowProgress = Curves.easeInOut.transform(segment(.72, 1));

  final rear = Path()
    ..moveTo(w * .50, h * .13)
    ..lineTo(w * .20, h * .84)
    ..lineTo(w * .82, h * .84)
    ..close();

  canvas.save();
  canvas.translate(0, -h * .42 * (1 - rearProgress));
  canvas.translate(center.dx, center.dy);
  canvas.rotate(-.10 * (1 - rearProgress));
  canvas.translate(-center.dx, -center.dy);
  canvas.drawPath(
    rear,
    Paint()
      ..color = ChernogramColors.orange.withValues(
        alpha: rearProgress.clamp(0.0, 1.0),
      ),
  );
  canvas.restore();

  final gold = Path()
    ..moveTo(w * .15, h * .31)
    ..lineTo(w * .87, h * .31)
    ..lineTo(w * .54, h * .93)
    ..lineTo(w * .54, h * .56)
    ..close();

  canvas.save();
  canvas.translate(
    w * .46 * (1 - goldProgress),
    h * .10 * (1 - goldProgress),
  );
  canvas.translate(center.dx, center.dy);
  canvas.rotate(.11 * (1 - goldProgress));
  canvas.translate(-center.dx, -center.dy);
  canvas.drawPath(
    gold,
    Paint()
      ..color = ChernogramColors.gold.withValues(
        alpha: goldProgress.clamp(0.0, 1.0),
      ),
  );
  canvas.restore();

  if (cutProgress > 0) {
    final cut = Path()
      ..moveTo(w * .16, h * .32)
      ..lineTo(w * .50, h * .54)
      ..lineTo(w * .20, h * .81);
    canvas.drawPath(
      cut,
      Paint()
        ..color = ChernogramColors.background.withValues(
          alpha: cutProgress.clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .066
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  if (glowProgress > 0) {
    final pulse = math.sin(glowProgress * math.pi);
    canvas.drawLine(
      Offset(w * .155, h * .303),
      Offset(w * .865, h * .303),
      Paint()
        ..color = ChernogramColors.goldLight.withValues(alpha: .75 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .007,
    );
  }
}
'''
    source = source[:start] + animated_painter + source[end:]
    write(path, source)


def fix_main(path: str) -> None:
    source = read(path)
    if "package:flutter/services.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
            1,
        )
    old = '''void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChernogramApp());
}'''
    new = '''void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: ChernogramColors.background,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ChernogramColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ChernogramApp());
}'''
    if old in source:
        source = source.replace(old, new, 1)
    write(path, source)


def fix_v06(path: str) -> None:
    target = ROOT / path
    if not target.exists():
        return
    source = target.read_text(encoding='utf-8')
    source = source.replace(
        "https://jeep-jim.github.io/chernogram_new/",
        "https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html",
    )
    target.write_text(source, encoding='utf-8')


def write_android_resources() -> None:
    icon = '''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1080"
    android:viewportHeight="1080">
    <path android:fillColor="#F46B00" android:pathData="M540,140 L216,907 L886,907 Z" />
    <path android:fillColor="#D1A246" android:pathData="M162,335 L940,335 L583,1004 L583,605 Z" />
    <path
        android:fillColor="@android:color/transparent"
        android:strokeColor="#080808"
        android:strokeWidth="72"
        android:strokeLineCap="square"
        android:strokeLineJoin="miter"
        android:pathData="M173,346 L540,583 L216,875" />
    <path
        android:fillColor="@android:color/transparent"
        android:strokeColor="#F1C56D"
        android:strokeWidth="8"
        android:pathData="M168,327 L934,327" />
</vector>
'''
    launch = icon.replace('android:width="108dp"', 'android:width="164dp"').replace(
        'android:height="108dp"', 'android:height="164dp"'
    )
    write('tooling/v06_icon_foreground.xml', icon)
    write('tooling/v06_launch_logo.xml', launch)
    write('android/app/src/main/res/drawable/ic_launcher_foreground.xml', icon)
    write('android/app/src/main/res/drawable/launch_logo.xml', launch)

    styles = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:statusBarColor">#080808</item>
        <item name="android:navigationBarColor">#080808</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar">false</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">#080808</item>
        <item name="android:statusBarColor">#080808</item>
        <item name="android:navigationBarColor">#080808</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar">false</item>
    </style>
</resources>
'''
    write('android/app/src/main/res/values/styles.xml', styles)
    write('android/app/src/main/res/values-night/styles.xml', styles)

    styles_v31 = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowSplashScreenBackground">#080808</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/launch_logo</item>
        <item name="android:windowSplashScreenIconBackgroundColor">#080808</item>
        <item name="android:postSplashScreenTheme">@style/NormalTheme</item>
        <item name="android:statusBarColor">#080808</item>
        <item name="android:navigationBarColor">#080808</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar">false</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">#080808</item>
        <item name="android:statusBarColor">#080808</item>
        <item name="android:navigationBarColor">#080808</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar">false</item>
    </style>
</resources>
'''
    write('android/app/src/main/res/values-v31/styles.xml', styles_v31)
    write('android/app/src/main/res/values-night-v31/styles.xml', styles_v31)


def main() -> None:
    for path in ('pubspec.yaml', 'tooling/v06_pubspec.yaml'):
        fix_pubspec(path)
    fix_brand()
    for path in ('lib/main.dart', 'tooling/v06_main.dart'):
        fix_main(path)
    for path in ('lib/v06.dart', 'tooling/v06.dart'):
        fix_v06(path)
    write_android_resources()
    print('Applied Chernogram 0.6.2 logo, dark splash, stable landing and asset-free branding')


if __name__ == '__main__':
    main()
