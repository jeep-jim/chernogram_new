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

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(withPlate ? size * .72 : size),
      painter: _ChernogramMarkPainter(
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (!withPlate) return mark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF202A45), Color(0xFF090D18)],
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: ChernogramColors.orange.withValues(alpha: .28),
            blurRadius: size * .35,
          ),
        ],
      ),
      child: mark,
    );
  }
}

class _ChernogramMarkPainter extends CustomPainter {
  final bool dark;

  const _ChernogramMarkPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final stroke = size.width * .14;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.35
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x667C5CFF), Color(0x6618B8FF)],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .08);
    final main = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9C86FF), Color(0xFF19C8FF)],
      ).createShader(rect);

    final arcRect = Rect.fromCircle(center: center, radius: size.width * .34);
    canvas.drawArc(arcRect, .62, 4.95, false, glow);
    canvas.drawArc(arcRect, .62, 4.95, false, main);

    final cutPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * .72
      ..strokeCap = StrokeCap.round
      ..color = dark ? const Color(0xFF070A12) : const Color(0xFFF2F6FF);
    canvas.drawLine(
      Offset(size.width * .54, size.height * .48),
      Offset(size.width * .82, size.height * .48),
      cutPaint,
    );
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .48),
      size.width * .065,
      Paint()..color = const Color(0xFF8DDEFF),
    );
  }

  @override
  bool shouldRepaint(covariant _ChernogramMarkPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class BrandHeader extends StatelessWidget {
  final String? subtitle;

  const BrandHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 34, withPlate: true),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Чернограм',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
    duration: const Duration(milliseconds: 900),
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
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: .84, end: 1).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChernogramLogo(size: 132, withPlate: true),
                  const SizedBox(height: 22),
                  const Text(
                    'CHERNOGRAM',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.ru ? 'СВЯЗЬ БЕЗ ГРАНИЦ' : 'CONNECTION WITHOUT BORDERS',
                    style: const TextStyle(
                      color: ChernogramColors.goldLight,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
