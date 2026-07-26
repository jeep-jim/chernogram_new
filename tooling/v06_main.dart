import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'update_service.dart';
import 'v06.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: ChernogramColors.background,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ChernogramColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ChernogramApp());
}

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool? _ru;
  bool _darkMode = true;
  bool _introDone = false;
  bool _automaticUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ru = prefs.getString('lang') != 'en';
      _darkMode = prefs.getBool('dark_mode') ?? true;
    });
  }

  Future<void> _toggleLanguage() async {
    final value = !(_ru ?? true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', value ? 'ru' : 'en');
    if (mounted) setState(() => _ru = value);
  }

  Future<void> _toggleTheme() async {
    final value = !_darkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    if (mounted) setState(() => _darkMode = value);
  }

  void _finishIntro() {
    if (!mounted) return;
    setState(() => _introDone = true);
    _scheduleAutomaticUpdate();
  }

  void _scheduleAutomaticUpdate() {
    if (_automaticUpdateScheduled || _ru == null) return;
    _automaticUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (context == null) {
        _automaticUpdateScheduled = false;
        Future<void>.delayed(
          const Duration(milliseconds: 350),
          _scheduleAutomaticUpdate,
        );
        return;
      }
      ChernogramUpdater.checkAndPrompt(
        context,
        ru: _ru!,
        manual: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsReady = _ru != null;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Chernogram',
      theme: chernogramLightTheme(),
      darkTheme: chernogramTheme(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: !settingsReady
          ? const ColoredBox(
              color: ChernogramColors.background,
              child: Center(
                child: ChernogramLogo(size: 112, withPlate: true),
              ),
            )
          : !_introDone
              ? ChernogramAnimatedIntro(
                  ru: _ru!,
                  onDone: _finishIntro,
                )
              : Builder(
                  builder: (context) => ChernogramV06(
                    ru: _ru!,
                    onChangeLanguage: _toggleLanguage,
                    onCheckUpdates: () => ChernogramUpdater.checkAndPrompt(
                      context,
                      ru: _ru!,
                      manual: true,
                    ),
                    darkMode: _darkMode,
                    onToggleTheme: _toggleTheme,
                  ),
                ),
    );
  }
}
