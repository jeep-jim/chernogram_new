import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CgChatPattern { none, constellations, masks, waves, circuit }

class CgChatAppearance {
  final bool enabled;
  final CgChatPattern darkPattern;
  final CgChatPattern lightPattern;
  final double intensity;

  const CgChatAppearance({
    this.enabled = true,
    this.darkPattern = CgChatPattern.constellations,
    this.lightPattern = CgChatPattern.waves,
    this.intensity = .20,
  });

  CgChatAppearance copyWith({
    bool? enabled,
    CgChatPattern? darkPattern,
    CgChatPattern? lightPattern,
    double? intensity,
  }) =>
      CgChatAppearance(
        enabled: enabled ?? this.enabled,
        darkPattern: darkPattern ?? this.darkPattern,
        lightPattern: lightPattern ?? this.lightPattern,
        intensity: intensity ?? this.intensity,
      );
}

class CgChatAppearanceController {
  CgChatAppearanceController._();

  static final CgChatAppearanceController instance =
      CgChatAppearanceController._();

  static const _enabledKey = 'cg_chat_pattern_enabled_v1';
  static const _darkKey = 'cg_chat_pattern_dark_v1';
  static const _lightKey = 'cg_chat_pattern_light_v1';
  static const _intensityKey = 'cg_chat_pattern_intensity_v1';

  final ValueNotifier<CgChatAppearance> appearance =
      ValueNotifier<CgChatAppearance>(const CgChatAppearance());
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    appearance.value = CgChatAppearance(
      enabled: prefs.getBool(_enabledKey) ?? true,
      darkPattern: _parse(prefs.getString(_darkKey)) ??
          CgChatPattern.constellations,
      lightPattern:
          _parse(prefs.getString(_lightKey)) ?? CgChatPattern.waves,
      intensity: (prefs.getDouble(_intensityKey) ?? .20)
          .clamp(.07, .42)
          .toDouble(),
    );
  }

  Future<void> save(CgChatAppearance next) async {
    appearance.value = next;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait<bool>([
      prefs.setBool(_enabledKey, next.enabled),
      prefs.setString(_darkKey, next.darkPattern.name),
      prefs.setString(_lightKey, next.lightPattern.name),
      prefs.setDouble(_intensityKey, next.intensity),
    ]);
  }

  CgChatPattern? _parse(String? value) {
    for (final pattern in CgChatPattern.values) {
      if (pattern.name == value) return pattern;
    }
    return null;
  }

  Future<void> showSettings(BuildContext context, {required bool ru}) async {
    await ensureLoaded();
    if (!context.mounted) return;
    var draft = appearance.value;
    final result = await showModalBottomSheet<CgChatAppearance>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ru ? 'Фон чатов' : 'Chat background',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ru
                      ? 'Лёгкие векторные паттерны не загружают интернет и почти не влияют на слабые Android.'
                      : 'Lightweight vector patterns use no network and have minimal impact on weaker Android devices.',
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ru ? 'Показывать паттерн' : 'Show pattern'),
                  value: draft.enabled,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(enabled: value),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ru ? 'Тёмная тема' : 'Dark theme',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                _patternPicker(
                  context,
                  value: draft.darkPattern,
                  ru: ru,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(darkPattern: value),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  ru ? 'Светлая тема' : 'Light theme',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                _patternPicker(
                  context,
                  value: draft.lightPattern,
                  ru: ru,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(lightPattern: value),
                  ),
                ),
                const SizedBox(height: 16),
                Text(ru ? 'Насыщенность' : 'Intensity'),
                Slider(
                  min: .07,
                  max: .42,
                  value: draft.intensity,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(intensity: value),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 155,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: CgChatBackdropPreview(
                        appearance: draft,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, draft),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(ru ? 'Применить' : 'Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) await save(result);
  }

  Widget _patternPicker(
    BuildContext context, {
    required CgChatPattern value,
    required bool ru,
    required ValueChanged<CgChatPattern> onChanged,
  }) =>
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: CgChatPattern.values.map((pattern) {
          return ChoiceChip(
            selected: pattern == value,
            label: Text(_label(pattern, ru)),
            onSelected: (_) => onChanged(pattern),
          );
        }).toList(),
      );

  String _label(CgChatPattern value, bool ru) => switch (value) {
        CgChatPattern.none => ru ? 'Без фона' : 'None',
        CgChatPattern.constellations => ru ? 'Созвездия' : 'Constellations',
        CgChatPattern.masks => ru ? 'Маски' : 'Masks',
        CgChatPattern.waves => ru ? 'Волны' : 'Waves',
        CgChatPattern.circuit => ru ? 'Схема' : 'Circuit',
      };
}

class CgChatBackdrop extends StatefulWidget {
  const CgChatBackdrop({super.key});

  @override
  State<CgChatBackdrop> createState() => _CgChatBackdropState();
}

class _CgChatBackdropState extends State<CgChatBackdrop> {
  final controller = CgChatAppearanceController.instance;

  @override
  void initState() {
    super.initState();
    controller.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ValueListenableBuilder<CgChatAppearance>(
          valueListenable: controller.appearance,
          builder: (context, appearance, _) => CgChatBackdropPreview(
            appearance: appearance,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
      );
}

class CgChatBackdropPreview extends StatelessWidget {
  final CgChatAppearance appearance;
  final bool dark;

  const CgChatBackdropPreview({
    super.key,
    required this.appearance,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final pattern = dark ? appearance.darkPattern : appearance.lightPattern;
    if (!appearance.enabled || pattern == CgChatPattern.none) {
      return const SizedBox.expand();
    }
    final primary = Theme.of(context).colorScheme.primary;
    return CustomPaint(
      painter: _CgChatPatternPainter(
        pattern: pattern,
        color: primary.withValues(alpha: appearance.intensity),
        dark: dark,
      ),
      size: Size.infinite,
    );
  }
}

class _CgChatPatternPainter extends CustomPainter {
  final CgChatPattern pattern;
  final Color color;
  final bool dark;

  const _CgChatPatternPainter({
    required this.pattern,
    required this.color,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    switch (pattern) {
      case CgChatPattern.constellations:
        _constellations(canvas, size, paint);
      case CgChatPattern.masks:
        _masks(canvas, size, paint);
      case CgChatPattern.waves:
        _waves(canvas, size, paint);
      case CgChatPattern.circuit:
        _circuit(canvas, size, paint);
      case CgChatPattern.none:
        break;
    }
  }

  void _constellations(Canvas canvas, Size size, Paint paint) {
    const cell = 92.0;
    for (double y = -20; y < size.height + cell; y += cell) {
      for (double x = -10; x < size.width + cell; x += cell) {
        final offset = ((y / cell).round().isOdd ? cell * .42 : 0);
        final p1 = Offset(x + offset + 14, y + 18);
        final p2 = Offset(x + offset + 51, y + 34);
        final p3 = Offset(x + offset + 36, y + 70);
        canvas.drawLine(p1, p2, paint);
        canvas.drawLine(p2, p3, paint);
        for (final point in <Offset>[p1, p2, p3]) {
          canvas.drawCircle(point, 1.8, paint..style = PaintingStyle.fill);
        }
        paint.style = PaintingStyle.stroke;
      }
    }
  }

  void _masks(Canvas canvas, Size size, Paint paint) {
    const cell = 108.0;
    for (double y = 8; y < size.height + cell; y += cell) {
      for (double x = 8; x < size.width + cell; x += cell) {
        final center = Offset(x + 35, y + 39);
        final rect = Rect.fromCenter(center: center, width: 42, height: 55);
        canvas.drawArc(rect, math.pi * 1.06, math.pi * .88, false, paint);
        canvas.drawArc(rect, math.pi * .06, math.pi * .88, false, paint);
        canvas.drawLine(
          Offset(center.dx - 13, center.dy - 4),
          Offset(center.dx - 4, center.dy - 4),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx + 4, center.dy - 4),
          Offset(center.dx + 13, center.dy - 4),
          paint,
        );
      }
    }
  }

  void _waves(Canvas canvas, Size size, Paint paint) {
    const step = 58.0;
    for (double y = -20; y < size.height + step; y += step) {
      final path = Path()..moveTo(-20, y);
      for (double x = -20; x < size.width + 40; x += 40) {
        path.quadraticBezierTo(x + 20, y + 14, x + 40, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _circuit(Canvas canvas, Size size, Paint paint) {
    const cell = 88.0;
    for (double y = 0; y < size.height + cell; y += cell) {
      for (double x = 0; x < size.width + cell; x += cell) {
        final start = Offset(x + 8, y + 20);
        final mid = Offset(x + 38, y + 20);
        final down = Offset(x + 38, y + 54);
        final end = Offset(x + 70, y + 54);
        canvas.drawLine(start, mid, paint);
        canvas.drawLine(mid, down, paint);
        canvas.drawLine(down, end, paint);
        canvas.drawCircle(start, 2.1, paint..style = PaintingStyle.fill);
        canvas.drawCircle(end, 2.1, paint);
        paint.style = PaintingStyle.stroke;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CgChatPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.color != color ||
      oldDelegate.dark != dark;
}
