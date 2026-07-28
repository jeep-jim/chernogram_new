import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChernogramColors {
  static const background = Color(0xFF070A12);
  static const surface = Color(0xFF111725);
  static const surfaceHigh = Color(0xFF1A2235);
  static const orange = Color(0xFF7C5CFF);
  static const orangeDeep = Color(0xFF5A3FE3);
  static const gold = Color(0xFF18B8FF);
  static const goldLight = Color(0xFF8DDEFF);
  static const textSoft = Color(0xFF9AA8C3);
  static const success = Color(0xFF28D7A1);
  static const danger = Color(0xFFFF5D7A);
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
    error: ChernogramColors.danger,
  );
  return _themeFromScheme(
    scheme,
    scaffold: ChernogramColors.background,
    navigation: const Color(0xE6111725),
    outline: const Color(0x336F87B5),
  );
}

ThemeData chernogramLightTheme() {
  const scaffold = Color(0xFFF2F6FF);
  const surface = Color(0xFFFFFFFF);
  const surfaceHigh = Color(0xFFE8EEFA);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F46E5),
    brightness: Brightness.light,
    surface: surface,
  ).copyWith(
    primary: const Color(0xFF4F46E5),
    secondary: const Color(0xFF008CCF),
    tertiary: const Color(0xFF6D5FF5),
    surface: surface,
    surfaceContainerHighest: surfaceHigh,
    onSurface: const Color(0xFF11182A),
    error: const Color(0xFFD92D52),
  );
  return _themeFromScheme(
    scheme,
    scaffold: scaffold,
    navigation: const Color(0xF7FFFFFF),
    outline: const Color(0x33546A91),
  );
}

ThemeData _themeFromScheme(
  ColorScheme scheme, {
  required Color scaffold,
  required Color navigation,
  required Color outline,
}) {
  final dark = scheme.brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    scaffoldBackgroundColor: scaffold,
    colorScheme: scheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      systemOverlayStyle: dark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: ChernogramColors.background,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Color(0xFFF2F6FF),
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFFF2F6FF),
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarDividerColor: Color(0xFFDCE4F2),
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: navigation,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? .24 : .13),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 10.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: .58),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: dark ? .72 : .82),
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .42)),
      labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .64)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface.withValues(alpha: dark ? .84 : .94),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: scheme.primary.withValues(alpha: .32)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerColor: outline,
  );
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;
  final Color? color;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? scheme.surface.withValues(alpha: dark ? .72 : .80),
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .12 : .04),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: .18)
            : scheme.surface.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 21,
              color: active ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class ChernogramLogo extends StatelessWidget {
  final double size;
  final bool withPlate;
  final double progress;

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
    this.progress = 1,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _ChernogramFacePainter(
        dark: Theme.of(context).brightness == Brightness.dark,
        progress: progress.clamp(0.0, 1.0).toDouble(),
      ),
    );
    if (!withPlate) return mark;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ChernogramColors.orange.withValues(alpha: .13),
              blurRadius: size * .42,
              spreadRadius: -size * .12,
            ),
          ],
        ),
        child: mark,
      ),
    );
  }
}

class _ChernogramFacePainter extends CustomPainter {
  final bool dark;
  final double progress;

  const _ChernogramFacePainter({required this.dark, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stripeCount = size.width < 52 ? 11 : 15;
    final lineWidth = size.width / (stripeCount * 3.15);
    final topBase = size.height * .11;
    final centerY = size.height * .48;
    final faceHeight = size.height * .72;
    final mainShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB9A8FF), Color(0xFF7B5CFF), Color(0xFF20C7FF)],
    ).createShader(rect);

    for (var index = 0; index < stripeCount; index++) {
      final t = stripeCount == 1 ? .5 : index / (stripeCount - 1);
      final normalizedX = t * 2 - 1;
      final x = size.width * (.14 + t * .72);
      final ellipse = math.sqrt(math.max(0, 1 - normalizedX * normalizedX));
      final top = topBase + (1 - ellipse) * size.height * .12;
      final jaw = ellipse * faceHeight * .50 - normalizedX.abs() * size.height * .035;
      final bottom = centerY + jaw;
      final stagger = (progress * 1.42 - t * .34).clamp(0.0, 1.0).toDouble();
      final eased = Curves.easeOutCubic.transform(stagger);
      if (eased <= 0) continue;
      final animatedTop = centerY + (top - centerY) * eased;
      final animatedBottom = centerY + (bottom - centerY) * eased;
      final alpha = (255 * eased).round();

      final main = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..shader = mainShader
        ..color = Colors.white.withAlpha(alpha);

      final gaps = <(double, double)>[];
      if (normalizedX.abs() > .17 && normalizedX.abs() < .72) {
        gaps.add((size.height * .37, size.height * .445));
      }
      var cursor = animatedTop;
      for (final gap in gaps) {
        final gapStart = gap.$1.clamp(animatedTop, animatedBottom).toDouble();
        final gapEnd = gap.$2.clamp(animatedTop, animatedBottom).toDouble();
        if (gapStart > cursor) {
          canvas.drawLine(Offset(x, cursor), Offset(x, gapStart), main);
        }
        cursor = math.max(cursor, gapEnd).toDouble();
      }
      if (cursor < animatedBottom) {
        canvas.drawLine(Offset(x, cursor), Offset(x, animatedBottom), main);
      }
    }

  }

  @override
  bool shouldRepaint(covariant _ChernogramFacePainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.progress != progress;
}

class BrandHeader extends StatelessWidget {
  final String? subtitle;
  final bool ru;

  const BrandHeader({super.key, this.subtitle, this.ru = true});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 39),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ru ? 'Чернограм' : 'Cernogram',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.45,
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
