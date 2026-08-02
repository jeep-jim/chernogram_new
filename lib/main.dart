import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_access.dart';
import 'app_navigation.dart';
import 'brand.dart';
import 'optical/optical_app.dart';
import 'update_service.dart';
import 'windows_desktop_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChernogramApp());
}

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp> {
  bool _ru = true;
  bool _darkMode = true;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _applySystemUi(true);
    unawaited(_loadSettings());
  }

  SystemUiOverlayStyle _overlay(bool dark) => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            dark ? ChernogramColors.background : const Color(0xFFF2F5FC),
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      );

  void _applySystemUi(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(_overlay(dark));
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
      final dark = Platform.isAndroid ? true : (prefs.getBool('dark_mode') ?? true);
      if (!mounted) return;
      setState(() {
        _ru = prefs.getString('lang') != 'en';
        _darkMode = dark;
      });
      _applySystemUi(dark);
    } catch (_) {
      // Интерфейс уже запущен с безопасными значениями по умолчанию.
    }
    _scheduleUpdateCheck();
  }

  Future<void> _toggleLanguage() async {
    final next = !_ru;
    if (mounted) setState(() => _ru = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lang', next ? 'ru' : 'en');
    } catch (_) {}
  }

  Future<void> _toggleTheme() async {
    final next = !_darkMode;
    _applySystemUi(next);
    if (mounted) setState(() => _darkMode = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dark_mode', next);
    } catch (_) {}
  }

  void _scheduleUpdateCheck() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final context = chernogramNavigatorKey.currentContext;
      if (context == null) {
        _updateScheduled = false;
        _scheduleUpdateCheck();
        return;
      }
      unawaited(
        ChernogramUpdater.checkAndPrompt(context, ru: _ru, manual: false),
      );
    });
  }

  Widget _applicationHome(BuildContext context) {
    if (Platform.isAndroid) {
      return const ChernogramOpticalHome();
    }
    final desktop = ChernogramWindowsDesktop(
      ru: _ru,
      darkMode: _darkMode,
      onToggleTheme: _toggleTheme,
      onChangeLanguage: _toggleLanguage,
      onCheckUpdates: () {
        unawaited(
          ChernogramUpdater.checkAndPrompt(
            context,
            ru: _ru,
            manual: true,
          ),
        );
      },
    );
    return CgAccessGate(ru: _ru, child: desktop);
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlay(_darkMode),
        child: MaterialApp(
          navigatorKey: chernogramNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Чернограм Optical',
          theme: chernogramLightTheme(),
          darkTheme: chernogramTheme(),
          themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
          themeAnimationDuration: Duration.zero,
          home: Builder(builder: _applicationHome),
        ),
      );
}
