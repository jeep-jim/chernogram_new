import 'dart:math' as math;

import 'package:flutter/material.dart';

class ChernogramColors {
  static const background = Color(0xFF080808);
  static const surface = Color(0xFF12100F);
  static const surfaceHigh = Color(0xFF1B1714);
  static const orange = Color(0xFFF46B00);
  static const orangeDeep = Color(0xFFC65300);
  static const gold = Color(0xFFD1A246);
  static const goldLight = Color(0xFFF1C56D);
  static const textSoft = Color(0xFFB9B3AC);
}

ThemeData chernogramTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ChernogramColors.orange,
    brightness: Brightness.dark,
    surface: ChernogramColors.surface,
  ).copyWith(
    primary: ChernogramColors.orange,
    secondary: ChernogramColors.gold,
    tertiary: ChernogramColors.goldLight,
    surface: ChernogramColors.surface,
    surfaceContainerHighest: ChernogramColors.surfaceHigh,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: ChernogramColors.background,
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: ChernogramColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ChernogramColors.surface,
      indicatorColor: ChernogramColors.orange.withValues(alpha: .24),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? ChernogramColors.goldLight
              : ChernogramColors.textSoft,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ChernogramColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: ChernogramColors.orange),
      ),
    ),
    cardTheme: CardThemeData(
      color: ChernogramColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ChernogramColors.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ChernogramColors.goldLight,
        side: const BorderSide(color: Color(0xFF5F4930)),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

ThemeData chernogramLightTheme() {
  const background = Color(0xFFFFF8F1);
  const surface = Color(0xFFFFFFFF);
  const surfaceHigh = Color(0xFFF2E9DF);
  final scheme = ColorScheme.fromSeed(
    seedColor: ChernogramColors.orange,
    brightness: Brightness.light,
    surface: surface,
  ).copyWith(
    primary: ChernogramColors.orangeDeep,
    secondary: ChernogramColors.gold,
    tertiary: ChernogramColors.orange,
    surface: surface,
    surfaceContainerHighest: surfaceHigh,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: background,
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: Color(0xFF21160E),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: ChernogramColors.orange.withValues(alpha: .18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? ChernogramColors.orangeDeep
              : const Color(0xFF6A6057),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: ChernogramColors.orange),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ChernogramColors.orangeDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ChernogramColors.orangeDeep,
        side: const BorderSide(color: ChernogramColors.gold),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

class ChernogramLogo extends StatelessWidget {
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
    duration: const Duration(milliseconds: 1750),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChernogramColors.background,
      child: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final value = Curves.easeOutCubic.transform(_controller.value);
              final textValue = ((_controller.value - .62) / .38)
                  .clamp(0.0, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size.square(230),
                    painter: _AnimatedLogoPainter(progress: value),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: textValue,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - textValue)),
                      child: Column(
                        children: [
                          const Text(
                            'CHERNOGRAM',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4.2,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.ru
                                ? 'ВАШИ ФАЙЛЫ. ВАШИ ПРАВИЛА.'
                                : 'YOUR FILES. YOUR RULES.',
                            style: const TextStyle(
                              color: ChernogramColors.goldLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              decoration: TextDecoration.none,
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
      ),
    );
  }
}

class _AnimatedLogoPainter extends CustomPainter {
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

class BrandHeader extends StatelessWidget {
  final String subtitle;

  const BrandHeader({super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ChernogramLogo(size: 38, withPlate: true),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CHERNOGRAM',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  color: ChernogramColors.textSoft,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
