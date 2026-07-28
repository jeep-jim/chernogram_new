from pathlib import Path
import math
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write_if_changed(path: str, source: str, original: str) -> bool:
    if source == original:
        return False
    file = Path(path)
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(source, encoding='utf-8')
    print(f'Patched {path}')
    return True


def patch_brand_intro() -> bool:
    path = 'lib/brand.dart'
    source = read(path)
    original = source
    if "import 'dart:math' as math;" not in source:
        source = source.replace("import 'dart:ui';\n", "import 'dart:math' as math;\nimport 'dart:ui';\n", 1)

    start = source.find('class ChernogramAnimatedIntro extends StatefulWidget')
    if start < 0:
        raise RuntimeError('ChernogramAnimatedIntro was not found')
    intro = r'''class ChernogramAnimatedIntro extends StatefulWidget {
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
    duration: const Duration(milliseconds: 1900),
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
        backgroundColor: ChernogramColors.background,
        body: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final stripes = CurvedAnimation(
                parent: _controller,
                curve: const Interval(0, .60, curve: Curves.easeOutCubic),
              ).value;
              final assembly = CurvedAnimation(
                parent: _controller,
                curve: const Interval(.04, .62, curve: Curves.easeOutCubic),
              ).value;
              final eyePhase = CurvedAnimation(
                parent: _controller,
                curve: const Interval(.50, .82, curve: Curves.easeOut),
              ).value;
              final textPhase = CurvedAnimation(
                parent: _controller,
                curve: const Interval(.58, 1, curve: Curves.easeOutCubic),
              ).value;
              final settle = CurvedAnimation(
                parent: _controller,
                curve: const Interval(.62, .90, curve: Curves.easeOut),
              ).value;
              final eyePulse = (eyePhase *
                      (.78 + .22 * math.sin(_controller.value * math.pi * 7)))
                  .clamp(0.0, 1.0)
                  .toDouble();

              const markSize = 156.0;
              final travel = 72 * (1 - assembly);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: .96 + assembly * .06 - settle * .02,
                    child: SizedBox.square(
                      dimension: markSize,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRect(
                            clipper: const _FaceHalfClipper(top: true),
                            child: Transform.translate(
                              offset: Offset(0, -travel),
                              child: ChernogramLogo(
                                size: markSize,
                                progress: stripes,
                              ),
                            ),
                          ),
                          ClipRect(
                            clipper: const _FaceHalfClipper(top: false),
                            child: Transform.translate(
                              offset: Offset(0, travel),
                              child: ChernogramLogo(
                                size: markSize,
                                progress: stripes,
                              ),
                            ),
                          ),
                          if (eyePulse > 0)
                            Opacity(
                              opacity: eyePulse,
                              child: CustomPaint(
                                painter: _IntroEyesPainter(progress: eyePulse),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 19),
                  Opacity(
                    opacity: textPhase,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - textPhase)),
                      child: Column(
                        children: [
                          Text(
                            widget.ru ? 'ЧЕРНОГРАМ' : 'CERNOGRAM',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            widget.ru
                                ? 'СВЯЗЬ БЕЗ ГРАНИЦ'
                                : 'CONNECTION WITHOUT BORDERS',
                            style: const TextStyle(
                              color: ChernogramColors.goldLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _FaceHalfClipper extends CustomClipper<Rect> {
  final bool top;

  const _FaceHalfClipper({required this.top});

  @override
  Rect getClip(Size size) => top
      ? Rect.fromLTWH(0, 0, size.width, size.height / 2)
      : Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2);

  @override
  bool shouldReclip(covariant _FaceHalfClipper oldClipper) =>
      oldClipper.top != top;
}

class _IntroEyesPainter extends CustomPainter {
  final double progress;

  const _IntroEyesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * .040
      ..color = const Color(0x5520C7FF).withValues(alpha: progress * .65);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * .016
      ..color = const Color(0xFFB9F1FF).withValues(alpha: progress);

    final leftStart = Offset(size.width * .285, size.height * .405);
    final leftEnd = Offset(size.width * .430, size.height * .430);
    final rightStart = Offset(size.width * .570, size.height * .430);
    final rightEnd = Offset(size.width * .715, size.height * .405);
    canvas.drawLine(leftStart, leftEnd, outer);
    canvas.drawLine(rightStart, rightEnd, outer);
    canvas.drawLine(leftStart, leftEnd, inner);
    canvas.drawLine(rightStart, rightEnd, inner);
  }

  @override
  bool shouldRepaint(covariant _IntroEyesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
'''
    source = source[:start] + intro
    return write_if_changed(path, source, original)


def patch_main_crash_capture() -> bool:
    path = 'lib/main.dart'
    source = read(path)
    original = source
    if "import 'dart:ui';" not in source:
        source = source.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:ui';\n", 1)
    if "import 'crash_reporter.dart';" not in source:
        source = source.replace("import 'brand.dart';\n", "import 'brand.dart';\nimport 'crash_reporter.dart';\n", 1)

    start = source.find('Future<void> main() async {')
    end = source.find('class ChernogramApp', start)
    if start < 0 or end < 0:
        raise RuntimeError('main startup block was not found')
    startup = r'''Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChernogramCrashReporter.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(ChernogramCrashReporter.recordFlutterError(details));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      ChernogramCrashReporter.recordError(
        error,
        stack,
        source: 'PLATFORM_DISPATCHER',
      ),
    );
    return true;
  };

  final startup = runZonedGuarded<Future<void>>(
    () async {
      await ChernogramCrashReporter.breadcrumb('audio background init begin');
      try {
        await JustAudioBackground.init(
          androidNotificationChannelId: 'com.example.chernogram.audio',
          androidNotificationChannelName: 'Музыка Чернограма',
          androidNotificationOngoing: true,
        );
        await ChernogramCrashReporter.breadcrumb('audio background init complete');
      } catch (error, stack) {
        await ChernogramCrashReporter.recordError(
          error,
          stack,
          source: 'AUDIO_BACKGROUND_INIT',
        );
      }
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: ChernogramColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: ChernogramColors.background,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
        ),
      );
      await ChernogramCrashReporter.breadcrumb('runApp');
      runApp(const ChernogramApp());
    },
    (error, stack) {
      unawaited(
        ChernogramCrashReporter.recordError(
          error,
          stack,
          source: 'ROOT_ZONE',
        ),
      );
    },
  );
  if (startup != null) await startup;
}

'''
    source = source[:start] + startup + source[end:]
    return write_if_changed(path, source, original)


def patch_profile_diagnostics() -> bool:
    path = 'lib/v12.dart'
    source = read(path)
    original = source
    if "import 'crash_reporter.dart';" not in source:
        local_marker = "import 'core_models.dart';\n"
        if local_marker in source:
            source = source.replace(local_marker, "import 'crash_reporter.dart';\n" + local_marker, 1)
        else:
            source = source.replace("import 'brand.dart';\n", "import 'brand.dart';\nimport 'crash_reporter.dart';\n", 1)

    start = source.find('  Future<void> _showBuildInfo() async')
    end = source.find('  Future<void> _pickAvatar()', start)
    if start >= 0 and end > start:
        block = source[start:end]
        if 'shareDiagnosticReport' not in block:
            insertion_at = block.rfind('            ],')
            if insertion_at < 0:
                raise RuntimeError('build information action list was not found')
            diagnostic_button = r'''              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final shared =
                        await ChernogramCrashReporter.shareDiagnosticReport(
                      ru: widget.ru,
                    );
                    if (!shared && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            widget.ru
                                ? 'Не удалось подготовить журнал ошибок'
                                : 'Could not prepare the crash report',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.bug_report_outlined),
                  label: Text(
                    widget.ru
                        ? 'Отправить журнал ошибок'
                        : 'Share crash report',
                  ),
                ),
              ),
'''
            block = block[:insertion_at] + diagnostic_button + block[insertion_at:]
            source = source[:start] + block + source[end:]
    return write_if_changed(path, source, original)


def patch_android_native_crash_capture() -> bool:
    path = 'android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt'
    source = read(path)
    original = source
    if 'import android.os.Bundle' not in source:
        source = source.replace('import android.os.Build\n', 'import android.os.Build\nimport android.os.Bundle\n', 1)
    if 'import java.io.File' not in source:
        source = source.replace('import io.flutter.plugin.common.MethodChannel\n', 'import io.flutter.plugin.common.MethodChannel\nimport java.io.File\nimport java.util.Date\n', 1)

    if 'crashHandlerInstalled' not in source:
        source = source.replace(
            'class MainActivity : AudioServiceActivity() {\n',
            '''class MainActivity : AudioServiceActivity() {
    companion object {
        @Volatile
        private var crashHandlerInstalled = false
    }

''',
            1,
        )
        marker = '    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n'
        handler = '''    override fun onCreate(savedInstanceState: Bundle?) {
        if (!crashHandlerInstalled) {
            crashHandlerInstalled = true
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            val appFiles = applicationContext.filesDir
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                try {
                    val report = buildString {
                        appendLine("===== ${Date()} ANDROID NATIVE CRASH =====")
                        appendLine("Thread: ${thread.name}")
                        appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
                        appendLine("Android: ${Build.VERSION.RELEASE} SDK ${Build.VERSION.SDK_INT}")
                        appendLine(throwable.stackTraceToString())
                        appendLine()
                    }
                    File(appFiles, "chernogram_native_crash.log").appendText(report)
                } catch (_: Throwable) {
                }
                if (previous != null) {
                    previous.uncaughtException(thread, throwable)
                } else {
                    android.os.Process.killProcess(android.os.Process.myPid())
                }
            }
        }
        super.onCreate(savedInstanceState)
    }

'''
        source = source.replace(marker, handler + marker, 1)
    return write_if_changed(path, source, original)


def face_geometry(size: int, count: int = 15):
    result = []
    for index in range(count):
        t = index / (count - 1)
        nx = t * 2 - 1
        x = size * (.14 + t * .72)
        ellipse = math.sqrt(max(0.0, 1 - nx * nx))
        top = size * (.11 + (1 - ellipse) * .12)
        bottom = size * (.48 + ellipse * .36 - abs(nx) * .035)
        gaps = []
        if .17 < abs(nx) < .72:
            gaps.append((size * .37, size * .445))
        result.append((t, x, top, bottom, gaps))
    return result


def interpolate_color(t: float):
    stops = [(185, 168, 255), (123, 92, 255), (32, 199, 255)]
    if t <= .5:
        p = t * 2
        a, b = stops[0], stops[1]
    else:
        p = (t - .5) * 2
        a, b = stops[1], stops[2]
    values = tuple(round(a[i] + (b[i] - a[i]) * p) for i in range(3))
    return '#%02X%02X%02X' % values


def build_android_vector(background: bool, notification: bool = False) -> str:
    lines = [
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:width="108dp"',
        '    android:height="108dp"',
        '    android:viewportWidth="1080"',
        '    android:viewportHeight="1080">',
    ]
    if background:
        lines.append('    <path android:fillColor="#070A12" android:pathData="M0,0 H1080 V1080 H0 Z" />')
    for t, x, top, bottom, gaps in face_geometry(1080):
        color = '#FFFFFFFF' if notification else interpolate_color(t)
        cursor = top
        segments = []
        for gap_start, gap_end in gaps:
            if gap_start > cursor:
                segments.append((cursor, gap_start))
            cursor = max(cursor, gap_end)
        if cursor < bottom:
            segments.append((cursor, bottom))
        for y1, y2 in segments:
            lines.append(
                f'    <path android:strokeColor="{color}" android:strokeWidth="34" '
                f'android:strokeLineCap="round" android:pathData="M{x:.1f},{y1:.1f} L{x:.1f},{y2:.1f}" />'
            )
    lines.append('</vector>')
    return '\n'.join(lines) + '\n'


def patch_native_icons() -> bool:
    changed = False
    launcher = build_android_vector(background=True)
    splash = launcher.replace('android:width="108dp"', 'android:width="164dp"').replace(
        'android:height="108dp"', 'android:height="164dp"'
    )
    foreground = build_android_vector(background=False)
    notification = build_android_vector(background=False, notification=True)
    for path, content in (
        ('android/app/src/main/res/drawable/chernogram_launcher_icon.xml', launcher),
        ('android/app/src/main/res/drawable/launch_logo.xml', splash),
        ('android/app/src/main/res/drawable/ic_launcher_foreground.xml', foreground),
        ('android/app/src/main/res/drawable/chernogram_notification_icon.xml', notification),
    ):
        file = Path(path)
        original = file.read_text(encoding='utf-8') if file.exists() else ''
        if original != content:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(content, encoding='utf-8')
            print(f'Patched {path}')
            changed = True

    background_service = Path('lib/background_realtime_service.dart')
    source = background_service.read_text(encoding='utf-8')
    original = source
    source = source.replace(
        "AndroidInitializationSettings('chernogram_launcher_icon')",
        "AndroidInitializationSettings('chernogram_notification_icon')",
    )
    if source != original:
        background_service.write_text(source, encoding='utf-8')
        print('Patched lib/background_realtime_service.dart')
        changed = True

    try:
        from PIL import Image, ImageDraw

        destination = Path('windows/runner/resources/app_icon.ico')
        if destination.parent.exists():
            size = 256
            image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            draw.rounded_rectangle((5, 5, 251, 251), radius=54, fill=(7, 10, 18, 255))
            for t, x, top, bottom, gaps in face_geometry(size):
                rgb = interpolate_color(t).lstrip('#')
                color = tuple(int(rgb[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
                cursor = top
                for gap_start, gap_end in gaps:
                    if gap_start > cursor:
                        draw.line((x, cursor, x, gap_start), fill=color, width=7)
                    cursor = max(cursor, gap_end)
                if cursor < bottom:
                    draw.line((x, cursor, x, bottom), fill=color, width=7)
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


def patch_metadata() -> bool:
    changed = False
    path = 'pubspec.yaml'
    source = read(path)
    original = source
    source = re.sub(
        r'^version:\s*0\.16\.[0-9]+\+[0-9]+\s*$',
        'version: 0.16.9+40',
        source,
        count=1,
        flags=re.M,
    )
    changed |= write_if_changed(path, source, original)

    path = 'docs/index.html'
    source = read(path)
    original = source
    source = re.sub(r'chernogram\.apk\?v=\d+', 'chernogram.apk?v=40', source)
    changed |= write_if_changed(path, source, original)

    path = 'roadmap.md'
    source = read(path)
    original = source
    if '`0.16.9+40`' not in source:
        source = source.rstrip() + (
            '\n- `0.16.9+40` — одинаковая маска с глазами на чёрном фоне для Android и Windows, '
            'загрузка со встречей верхней и нижней половин и импульсом глаз, локальный журнал '
            'Dart/Flutter и Android-native аварий с отправкой из карточки версии.\n'
        )
    changed |= write_if_changed(path, source, original)
    return changed


def main() -> None:
    changed = False
    changed |= patch_brand_intro()
    changed |= patch_main_crash_capture()
    changed |= patch_profile_diagnostics()
    changed |= patch_android_native_crash_capture()
    changed |= patch_native_icons()
    changed |= patch_metadata()
    print('Cernogram 0.16.9 icon, intro and crash diagnostics applied' if changed else '0.16.9 already applied')


if __name__ == '__main__':
    main()
