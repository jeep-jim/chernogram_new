import 'package:flutter/material.dart';

class ChernogramColors {
  static const background = Color(0xFF080808);
  static const surface = Color(0xFF12100F);
  static const surfaceHigh = Color(0xFF1B1714);
  static const orange = Color(0xFFE96800);
  static const orangeDeep = Color(0xFFB94800);
  static const gold = Color(0xFFC99A45);
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
      size: Size.square(size),
      painter: _ChernogramLogoPainter(),
    );
    if (!withPlate) return mark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0A0A),
        borderRadius: BorderRadius.circular(size * .23),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      padding: EdgeInsets.all(size * .09),
      child: mark,
    );
  }
}

class _ChernogramLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final orangePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF27900), Color(0xFFD94F00)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final goldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0BF61), Color(0xFFC58E35), Color(0xFF9B5F22)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final rear = Path()
      ..moveTo(w * .50, h * .08)
      ..lineTo(w * .14, h * .80)
      ..lineTo(w * .86, h * .80)
      ..close();
    canvas.drawPath(rear, orangePaint);

    final gold = Path()
      ..moveTo(w * .11, h * .29)
      ..lineTo(w * .88, h * .29)
      ..lineTo(w * .52, h * .94)
      ..lineTo(w * .52, h * .52)
      ..close();
    canvas.drawPath(gold, goldPaint);

    final cutPaint = Paint()
      ..color = const Color(0xFF0A0909)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .035
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final cut = Path()
      ..moveTo(w * .12, h * .31)
      ..lineTo(w * .49, h * .52)
      ..lineTo(w * .14, h * .79);
    canvas.drawPath(cut, cutPaint);

    final highlight = Paint()
      ..color = const Color(0xFFFFDB86).withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .007;
    final topHighlight = Path()
      ..moveTo(w * .12, h * .285)
      ..lineTo(w * .86, h * .285);
    canvas.drawPath(topHighlight, highlight);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
