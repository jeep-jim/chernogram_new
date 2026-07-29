import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_access.dart';
import 'android_data_first.dart';
import 'app_navigation.dart';
import 'brand.dart';
import 'update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ChernogramColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
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
  bool? _ru;
  bool _darkMode = true;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait<Object?>([
      SharedPreferences.getInstance(),
      Future<void>.delayed(const Duration(milliseconds: 850)),
    ]);
    final prefs = results.first! as SharedPreferences;
    if (!mounted) return;
    setState(() {
      _ru = prefs.getString('lang') != 'en';
      _darkMode = prefs.getBool('dark_mode') ?? true;
    });
    _scheduleUpdateCheck();
  }

  Future<void> _toggleLanguage() async {
    final next = !(_ru ?? true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', next ? 'ru' : 'en');
    if (mounted) setState(() => _ru = next);
  }

  Future<void> _toggleTheme() async {
    final next = !_darkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', next);
    if (mounted) setState(() => _darkMode = next);
  }

  void _scheduleUpdateCheck() {
    if (_updateScheduled || _ru == null) return;
    _updateScheduled = true;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      final context = chernogramNavigatorKey.currentContext;
      if (context == null) {
        _updateScheduled = false;
        _scheduleUpdateCheck();
        return;
      }
      unawaited(
        ChernogramUpdater.checkAndPrompt(context, ru: _ru!, manual: false),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ru != null;
    return MaterialApp(
      navigatorKey: chernogramNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Chernogram',
      theme: chernogramLightTheme(),
      darkTheme: chernogramTheme(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: !ready
          ? const Scaffold(
              backgroundColor: ChernogramColors.background,
              body: Center(child: ChernogramLogo(size: 148)),
            )
          : Builder(
              builder: (context) => CgAccessGate(
                ru: _ru!,
                child: ChernogramDataFirst(
                  ru: _ru!,
                  darkMode: _darkMode,
                  onToggleTheme: _toggleTheme,
                  onChangeLanguage: _toggleLanguage,
                  onCheckUpdates: () {
                    unawaited(
                      ChernogramUpdater.checkAndPrompt(
                        context,
                        ru: _ru!,
                        manual: true,
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
