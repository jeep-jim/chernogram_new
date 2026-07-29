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

  SystemUiOverlayStyle _overlay(bool dark) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: dark
        ? ChernogramColors.background
        : const Color(0xFFF2F5FC),
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  void _applySystemUi(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(_overlay(dark));
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool('dark_mode') ?? true;
    _applySystemUi(dark);
    if (!mounted) return;
    setState(() {
      _ru = prefs.getString('lang') != 'en';
      _darkMode = dark;
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
    _applySystemUi(next);
    if (mounted) setState(() => _darkMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', next);
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlay(_darkMode),
      child: MaterialApp(
        navigatorKey: chernogramNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Chernogram',
        theme: chernogramLightTheme(),
        darkTheme: chernogramTheme(),
        themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
        themeAnimationDuration: Duration.zero,
        home: !ready
            ? Scaffold(
                backgroundColor: _darkMode
                    ? ChernogramColors.background
                    : const Color(0xFFF2F5FC),
                body: const Center(child: ChernogramLogo(size: 148)),
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
      ),
    );
  }
}
