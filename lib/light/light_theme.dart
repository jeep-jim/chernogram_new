import 'dart:ui';

import 'package:flutter/material.dart';

abstract final class LightChatColors {
  static const Color violet = Color(0xFF7564F4);
  static const Color cyan = Color(0xFF4AC9E8);
  static const Color mint = Color(0xFF38C99A);
  static const Color darkTop = Color(0xFF202A43);
  static const Color darkMiddle = Color(0xFF151D32);
  static const Color darkBottom = Color(0xFF25203B);
  static const Color lightTop = Color(0xFFF8F9FF);
  static const Color lightBottom = Color(0xFFEFF2FA);
}

ThemeData lightChatTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: LightChatColors.violet,
        brightness: brightness,
        surface: dark ? const Color(0xFF20283A) : Colors.white,
      ).copyWith(
        primary: LightChatColors.violet,
        secondary: LightChatColors.cyan,
        tertiary: LightChatColors.mint,
        surface: dark ? const Color(0xFF20283A) : Colors.white,
        surfaceContainerHighest: dark
            ? const Color(0xFF2A3348)
            : const Color(0xFFE9EDF7),
        onSurface: dark ? const Color(0xFFF4F5FF) : const Color(0xFF172033),
      );

  OutlineInputBorder inputBorder() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surface.withValues(alpha: dark ? .52 : .70),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface.withValues(alpha: dark ? .56 : .76),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: inputBorder(),
      enabledBorder: inputBorder(),
      focusedBorder: inputBorder(),
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: .44)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(46, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 54),
        backgroundColor: scheme.surface.withValues(alpha: dark ? .46 : .70),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: .06)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: dark ? const Color(0xF5232B3D) : const Color(0xF7FFFFFF),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: dark ? const Color(0xF5262E42) : const Color(0xF8FFFFFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xEE30394E) : const Color(0xEE1E2738),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: .15),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
    ),
    dividerColor: Colors.transparent,
  );
}

class LightBackdrop extends StatelessWidget {
  final bool dark;
  final Widget child;

  const LightBackdrop({super.key, required this.dark, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const <Color>[
                LightChatColors.darkTop,
                LightChatColors.darkMiddle,
                LightChatColors.darkBottom,
              ]
            : const <Color>[
                LightChatColors.lightTop,
                Color(0xFFF2F5FD),
                LightChatColors.lightBottom,
              ],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -90,
          top: 70,
          child: _Glow(
            color: LightChatColors.violet.withValues(alpha: dark ? .14 : .11),
            size: 280,
          ),
        ),
        Positioned(
          right: -110,
          bottom: 110,
          child: _Glow(
            color: LightChatColors.cyan.withValues(alpha: dark ? .11 : .09),
            size: 310,
          ),
        ),
        child,
      ],
    ),
  );
}

class LightGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final Color? color;
  final double blur;

  const LightGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(30)),
    this.color,
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? scheme.surface.withValues(alpha: dark ? .47 : .68),
            borderRadius: borderRadius,
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: dark ? .07 : .055),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    ),
  );
}
