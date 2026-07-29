import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChernogramColors {
  static const background = Color(0xFF070A12);
  static const surface = Color(0xFF101522);
  static const surfaceHigh = Color(0xFF181F30);
  static const violet = Color(0xFF7B5CFF);
  static const violetDeep = Color(0xFF5A3FE3);
  static const cyan = Color(0xFF20C7FF);
  static const cyanLight = Color(0xFFB9F1FF);
  static const textSoft = Color(0xFF9AA8C3);
  static const success = Color(0xFF28D7A1);
  static const danger = Color(0xFFFF4D67);

  static const purple = violet;
  static const orange = violet;
  static const orangeDeep = violetDeep;
  static const gold = cyan;
  static const goldLight = cyanLight;
}

ThemeData chernogramTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ChernogramColors.violet,
        brightness: Brightness.dark,
        surface: ChernogramColors.surface,
      ).copyWith(
        primary: ChernogramColors.violet,
        secondary: ChernogramColors.cyan,
        tertiary: ChernogramColors.cyanLight,
        surface: ChernogramColors.surface,
        surfaceContainerHighest: ChernogramColors.surfaceHigh,
        error: ChernogramColors.danger,
      );
  return _themeFromScheme(
    scheme,
    scaffold: ChernogramColors.background,
    navigation: const Color(0xF2101522),
  );
}

ThemeData chernogramLightTheme() {
  const scaffold = Color(0xFFF2F5FC);
  const surface = Color(0xFFFFFFFF);
  const surfaceHigh = Color(0xFFE8EDF7);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B4CE6),
        brightness: Brightness.light,
        surface: surface,
      ).copyWith(
        primary: const Color(0xFF5B4CE6),
        secondary: const Color(0xFF008FCF),
        tertiary: const Color(0xFF6E5CF2),
        surface: surface,
        surfaceContainerHighest: surfaceHigh,
        onSurface: const Color(0xFF11182A),
        error: const Color(0xFFD62F50),
      );
  return _themeFromScheme(
    scheme,
    scaffold: scaffold,
    navigation: const Color(0xFAFFFFFF),
  );
}

ThemeData _themeFromScheme(
  ColorScheme scheme, {
  required Color scaffold,
  required Color navigation,
}) {
  final dark = scheme.brightness == Brightness.dark;
  const radius = 20.0;
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
              statusBarColor: Color(0xFFF2F5FC),
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFFF2F5FC),
              systemNavigationBarIconBrightness: Brightness.dark,
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
        letterSpacing: -.3,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: navigation,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 10.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: .52),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: .56),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(
        alpha: dark ? .75 : .88,
      ),
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .42)),
      labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .64)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface.withValues(alpha: dark ? .86 : .96),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: .82),
      selectedColor: scheme.primary.withValues(alpha: .16),
      checkmarkColor: Colors.transparent,
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: .72),
        minimumSize: const Size(0, 50),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerColor: Colors.transparent,
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
            color: color ?? scheme.surface.withValues(alpha: dark ? .76 : .88),
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .15 : .05),
                blurRadius: 24,
                offset: const Offset(0, 9),
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
  final Color? foregroundColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = false,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: .17)
            : scheme.surface.withValues(alpha: .60),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 21,
              color:
                  foregroundColor ??
                  (active ? scheme.primary : scheme.onSurface),
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
  final Color? tint;

  const ChernogramLogo({
    super.key,
    required this.size,
    this.withPlate = false,
    this.progress = 1,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _ChernogramFacePainter(
        progress: progress.clamp(0.0, 1.0).toDouble(),
        tint: tint,
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
              color: (tint ?? ChernogramColors.violet).withValues(alpha: .16),
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
  final double progress;
  final Color? tint;

  const _ChernogramFacePainter({required this.progress, this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stripeCount = size.width < 48 ? 11 : 15;
    final lineWidth = size.width / (stripeCount * 3.15);
    final topBase = size.height * .11;
    final centerY = size.height * .48;
    final faceHeight = size.height * .72;
    final shader = tint == null
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB9A8FF), Color(0xFF7B5CFF), Color(0xFF20C7FF)],
          ).createShader(rect)
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(tint!, Colors.white, .34)!,
              tint!,
              Color.lerp(tint!, ChernogramColors.cyan, .38)!,
            ],
          ).createShader(rect);

    for (var index = 0; index < stripeCount; index++) {
      final t = index / (stripeCount - 1);
      final normalizedX = t * 2 - 1;
      final x = size.width * (.14 + t * .72);
      final ellipse = math.sqrt(math.max(0, 1 - normalizedX * normalizedX));
      final top = topBase + (1 - ellipse) * size.height * .12;
      final jaw =
          ellipse * faceHeight * .50 - normalizedX.abs() * size.height * .035;
      final bottom = centerY + jaw;
      final stagger = (progress * 1.42 - t * .34).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(stagger.toDouble());
      if (eased <= 0) continue;
      final animatedTop = centerY + (top - centerY) * eased;
      final animatedBottom = centerY + (bottom - centerY) * eased;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader;

      final eyeGap = normalizedX.abs() > .17 && normalizedX.abs() < .72;
      if (!eyeGap) {
        canvas.drawLine(
          Offset(x, animatedTop),
          Offset(x, animatedBottom),
          paint,
        );
        continue;
      }
      final gapStart = (size.height * .37).clamp(animatedTop, animatedBottom);
      final gapEnd = (size.height * .445).clamp(animatedTop, animatedBottom);
      if (gapStart > animatedTop) {
        canvas.drawLine(
          Offset(x, animatedTop),
          Offset(x, gapStart.toDouble()),
          paint,
        );
      }
      if (gapEnd < animatedBottom) {
        canvas.drawLine(
          Offset(x, gapEnd.toDouble()),
          Offset(x, animatedBottom),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChernogramFacePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tint != tint;
}

class ChernogramAvatar extends StatelessWidget {
  final double size;
  final String seed;
  final String? avatarBase64;

  const ChernogramAvatar({
    super.key,
    required this.size,
    required this.seed,
    this.avatarBase64,
  });

  static const _palette = <Color>[
    Color(0xFF7B5CFF),
    Color(0xFF20C7FF),
    Color(0xFF19C6A3),
    Color(0xFFFF6B8A),
    Color(0xFFFFA44C),
    Color(0xFF9877FF),
  ];

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        bytes = Uint8List.fromList(base64Decode(avatarBase64!));
      } catch (_) {}
    }
    final color = _palette[seed.hashCode.abs() % _palette.length];
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: .28),
                      color.withValues(alpha: .08),
                    ],
                  ),
                ),
                child: Center(
                  child: ChernogramLogo(size: size * .66, tint: color),
                ),
              ),
      ),
    );
  }
}

class ChernogramEqualizerLogo extends StatefulWidget {
  final double size;
  final bool active;

  const ChernogramEqualizerLogo({
    super.key,
    required this.size,
    required this.active,
  });

  @override
  State<ChernogramEqualizerLogo> createState() =>
      _ChernogramEqualizerLogoState();
}

class _ChernogramEqualizerLogoState extends State<ChernogramEqualizerLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ChernogramEqualizerLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.animateTo(1, duration: const Duration(milliseconds: 240));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Transform.scale(
      scale: widget.active
          ? .96 + math.sin(_controller.value * math.pi) * .05
          : 1,
      child: ChernogramLogo(
        size: widget.size,
        progress: widget.active ? .62 + _controller.value * .38 : 1,
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class BrandHeader extends StatelessWidget {
  final String? subtitle;
  final bool ru;
  final VoidCallback? onTap;

  const BrandHeader({super.key, this.subtitle, this.ru = true, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 40),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class CgChatPatternBackground extends StatelessWidget {
  final Widget child;

  const CgChatPatternBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ChatPatternPainter(
      dark: Theme.of(context).brightness == Brightness.dark,
      accent: Theme.of(context).colorScheme.primary,
    ),
    child: child,
  );
}

class _ChatPatternPainter extends CustomPainter {
  final bool dark;
  final Color accent;

  const _ChatPatternPainter({required this.dark, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: dark ? .038 : .032)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    const step = 72.0;
    for (double y = -step; y < size.height + step; y += step) {
      final shift = ((y / step).round().isEven) ? 0.0 : step / 2;
      for (double x = -step + shift; x < size.width + step; x += step) {
        final center = Offset(x, y);
        canvas.drawCircle(center, 8, paint);
        canvas.drawLine(
          Offset(center.dx - 11, center.dy + 13),
          Offset(center.dx + 11, center.dy - 13),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.accent != accent;
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
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ChernogramColors.background,
    body: Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ChernogramLogo(
          size: 148,
          progress: Curves.easeOutCubic.transform(_controller.value),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
