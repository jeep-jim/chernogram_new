import 'package:flutter/material.dart';

class HybridTheme {
  static const darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF121826),
      Color(0xFF1B1934),
      Color(0xFF102A35),
    ],
    stops: <double>[0, .52, 1],
  );

  static const lightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFFF7F8FF),
      Color(0xFFF1EDFF),
      Color(0xFFEAF8FA),
    ],
    stops: <double>[0, .52, 1],
  );

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7B68EE),
      brightness: Brightness.dark,
      surface: const Color(0xFF20263A),
    ).copyWith(
      primary: const Color(0xFF9B8CFF),
      secondary: const Color(0xFF4ED7C5),
      surface: const Color(0xFF20263A),
      surfaceContainer: const Color(0xCC252B40),
      surfaceContainerHigh: const Color(0xE62B3148),
      surfaceContainerHighest: const Color(0xFF30374F),
      outline: const Color(0xFF586078),
      outlineVariant: const Color(0xFF41485F),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: const Color(0xFF20263A),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xCC252B40),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x334F5B80)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xB51A2032),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xE61A2032),
        indicatorColor: const Color(0x557B68EE),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xCC252B40),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x33586078)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x33586078)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF9B8CFF), width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF20263A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF20263A),
        modalBackgroundColor: Color(0xFF20263A),
        showDragHandle: true,
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6656D9),
      brightness: Brightness.light,
      surface: const Color(0xFFF9F9FF),
    ).copyWith(
      primary: const Color(0xFF6656D9),
      secondary: const Color(0xFF087F78),
      surface: const Color(0xFFF9F9FF),
      surfaceContainer: const Color(0xE6FFFFFF),
      surfaceContainerHigh: const Color(0xFFF3F1FF),
      surfaceContainerHighest: const Color(0xFFEDEAFB),
      outline: const Color(0xFF77758A),
      outlineVariant: const Color(0xFFD4D0E3),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: const Color(0xFFF9F9FF),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xEFFFFFFF),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x66D4D0E3)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xEFFFFFFF),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xF2FFFFFF),
        indicatorColor: const Color(0x336656D9),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xEFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x66D4D0E3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x66D4D0E3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF6656D9), width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFF9F9FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFF9F9FF),
        modalBackgroundColor: Color(0xFFF9F9FF),
        showDragHandle: true,
      ),
    );
  }
}

class HybridBackdrop extends StatelessWidget {
  final bool dark;
  final Widget child;

  const HybridBackdrop({super.key, required this.dark, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: dark ? HybridTheme.darkGradient : HybridTheme.lightGradient,
        ),
        child: child,
      );
}
