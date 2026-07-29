import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CgChatPatternSettings {
  final bool lightEnabled;
  final bool darkEnabled;
  final String lightPattern;
  final String darkPattern;

  const CgChatPatternSettings({
    this.lightEnabled = false,
    this.darkEnabled = true,
    this.lightPattern = 'dots',
    this.darkPattern = 'mask',
  });

  CgChatPatternSettings copyWith({
    bool? lightEnabled,
    bool? darkEnabled,
    String? lightPattern,
    String? darkPattern,
  }) =>
      CgChatPatternSettings(
        lightEnabled: lightEnabled ?? this.lightEnabled,
        darkEnabled: darkEnabled ?? this.darkEnabled,
        lightPattern: lightPattern ?? this.lightPattern,
        darkPattern: darkPattern ?? this.darkPattern,
      );
}

class CgChatPatternController {
  CgChatPatternController._();

  static final CgChatPatternController instance = CgChatPatternController._();
  static const String _lightEnabledKey = 'cg_pattern_light_enabled_v1';
  static const String _darkEnabledKey = 'cg_pattern_dark_enabled_v1';
  static const String _lightPatternKey = 'cg_pattern_light_kind_v1';
  static const String _darkPatternKey = 'cg_pattern_dark_kind_v1';

  final ValueNotifier<CgChatPatternSettings> settings =
      ValueNotifier<CgChatPatternSettings>(const CgChatPatternSettings());
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    settings.value = CgChatPatternSettings(
      lightEnabled: prefs.getBool(_lightEnabledKey) ?? false,
      darkEnabled: prefs.getBool(_darkEnabledKey) ?? true,
      lightPattern: prefs.getString(_lightPatternKey) ?? 'dots',
      darkPattern: prefs.getString(_darkPatternKey) ?? 'mask',
    );
  }

  Future<void> save(CgChatPatternSettings value) async {
    settings.value = value;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait<bool>(<Future<bool>>[
      prefs.setBool(_lightEnabledKey, value.lightEnabled),
      prefs.setBool(_darkEnabledKey, value.darkEnabled),
      prefs.setString(_lightPatternKey, value.lightPattern),
      prefs.setString(_darkPatternKey, value.darkPattern),
    ]);
  }
}

class CgChatPatternLayer extends StatefulWidget {
  const CgChatPatternLayer({super.key});

  @override
  State<CgChatPatternLayer> createState() => _CgChatPatternLayerState();
}

class _CgChatPatternLayerState extends State<CgChatPatternLayer> {
  final CgChatPatternController _controller = CgChatPatternController.instance;

  @override
  void initState() {
    super.initState();
    _controller.settings.addListener(_refresh);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.settings.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final settings = _controller.settings.value;
    final enabled = dark ? settings.darkEnabled : settings.lightEnabled;
    final pattern = dark ? settings.darkPattern : settings.lightPattern;
    if (!enabled || pattern == 'none') return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CgPatternPainter(
            pattern: pattern,
            color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: dark ? .055 : .045,
                ),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CgPatternPainter extends CustomPainter {
  final String pattern;
  final Color color;

  const _CgPatternPainter({required this.pattern, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    switch (pattern) {
      case 'mask':
        _paintMasks(canvas, size, paint);
        break;
      case 'waves':
        _paintWaves(canvas, size, paint);
        break;
      case 'constellations':
        _paintConstellations(canvas, size, paint);
        break;
      default:
        _paintDots(canvas, size, paint);
    }
  }

  void _paintDots(Canvas canvas, Size size, Paint paint) {
    final fill = Paint()..color = color;
    const step = 34.0;
    for (double y = 18; y < size.height; y += step) {
      final shift = ((y / step).round().isEven ? 0.0 : step / 2);
      for (double x = 18 + shift; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.35, fill);
      }
    }
  }

  void _paintWaves(Canvas canvas, Size size, Paint paint) {
    const stepY = 48.0;
    for (double y = 10; y < size.height + 24; y += stepY) {
      final path = Path()..moveTo(-30, y);
      for (double x = -30; x < size.width + 60; x += 24) {
        path.quadraticBezierTo(x + 12, y - 9, x + 24, y);
        path.quadraticBezierTo(x + 36, y + 9, x + 48, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintConstellations(Canvas canvas, Size size, Paint paint) {
    final fill = Paint()..color = color.withValues(alpha: .9);
    const cell = 86.0;
    for (double y = 0; y < size.height + cell; y += cell) {
      for (double x = 0; x < size.width + cell; x += cell) {
        final seed = (x ~/ cell) * 31 + (y ~/ cell) * 17;
        final a = Offset(x + 16 + seed % 17, y + 18 + seed % 13);
        final b = Offset(x + 55 + seed % 11, y + 34 + seed % 19);
        final c = Offset(x + 31 + seed % 23, y + 67 + seed % 7);
        canvas.drawLine(a, b, paint);
        canvas.drawLine(b, c, paint);
        canvas.drawCircle(a, 1.7, fill);
        canvas.drawCircle(b, 1.35, fill);
        canvas.drawCircle(c, 1.6, fill);
      }
    }
  }

  void _paintMasks(Canvas canvas, Size size, Paint paint) {
    const cellW = 92.0;
    const cellH = 98.0;
    for (double y = -20; y < size.height + cellH; y += cellH) {
      for (double x = -18; x < size.width + cellW; x += cellW) {
        final center = Offset(
          x + cellW / 2 + (((y / cellH).round().isEven) ? 0 : 22),
          y + cellH / 2,
        );
        final path = Path();
        for (var index = 0; index < 9; index++) {
          final dx = (index - 4) * 4.2;
          final arch = 1 - (index - 4).abs() / 5;
          final top = center.dy - 19 * arch;
          final bottom = center.dy + 22 * arch;
          path
            ..moveTo(center.dx + dx, top)
            ..lineTo(center.dx + dx, bottom);
        }
        canvas.drawPath(path, paint);
        final eyePaint = Paint()
          ..color = color.withValues(alpha: math.min(1, color.a + .18))
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - 10, center.dy - 2),
          Offset(center.dx - 3, center.dy - 2),
          eyePaint,
        );
        canvas.drawLine(
          Offset(center.dx + 3, center.dy - 2),
          Offset(center.dx + 10, center.dy - 2),
          eyePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CgPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color;
}

class CgChatPatternSettingsScreen extends StatefulWidget {
  final bool ru;

  const CgChatPatternSettingsScreen({super.key, required this.ru});

  @override
  State<CgChatPatternSettingsScreen> createState() =>
      _CgChatPatternSettingsScreenState();
}

class _CgChatPatternSettingsScreenState
    extends State<CgChatPatternSettingsScreen> {
  final CgChatPatternController _controller = CgChatPatternController.instance;
  late CgChatPatternSettings _settings = _controller.settings.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _controller.load();
    if (mounted) setState(() => _settings = _controller.settings.value);
  }

  Future<void> _save(CgChatPatternSettings value) async {
    setState(() => _settings = value);
    await _controller.save(value);
  }

  String _name(String kind) => switch (kind) {
        'mask' => widget.ru ? 'Маски Cernogram' : 'Cernogram masks',
        'waves' => widget.ru ? 'Волны' : 'Waves',
        'constellations' => widget.ru ? 'Созвездия' : 'Constellations',
        'dots' => widget.ru ? 'Точки' : 'Dots',
        _ => widget.ru ? 'Без паттерна' : 'No pattern',
      };

  Widget _themeSection({required bool dark}) {
    final enabled = dark ? _settings.darkEnabled : _settings.lightEnabled;
    final selected = dark ? _settings.darkPattern : _settings.lightPattern;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: (value) => _save(
                dark
                    ? _settings.copyWith(darkEnabled: value)
                    : _settings.copyWith(lightEnabled: value),
              ),
              secondary: Icon(
                dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              ),
              title: Text(
                dark
                    ? (widget.ru ? 'Тёмная тема' : 'Dark theme')
                    : (widget.ru ? 'Светлая тема' : 'Light theme'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (enabled)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const <String>[
                  'mask',
                  'waves',
                  'constellations',
                  'dots',
                  'none',
                ].map((kind) {
                  return ChoiceChip(
                    selected: selected == kind,
                    label: Text(_name(kind)),
                    onSelected: (_) => _save(
                      dark
                          ? _settings.copyWith(darkPattern: kind)
                          : _settings.copyWith(lightPattern: kind),
                    ),
                  );
                }).toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Фон чатов' : 'Chat background'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            widget.ru
                ? 'Лёгкие векторные паттерны не загружают изображения и почти не влияют на слабые телефоны.'
                : 'Lightweight vector patterns use no image assets and have minimal impact on slower phones.',
          ),
          const SizedBox(height: 12),
          _themeSection(dark: true),
          _themeSection(dark: false),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: const CgChatPatternLayer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
