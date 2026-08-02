import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_access.dart';
import 'android_data_first.dart';
import 'app_navigation.dart';
import 'brand.dart';
import 'update_service.dart';
import 'windows_desktop_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await _prepareWindowsBuild67Storage();
  }
  runApp(const ChernogramApp());
}

Future<void> _prepareWindowsBuild67Storage() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.trim().isEmpty) return;
  final directory = Directory('$appData\\com.example\\chernogram');
  final preferences = File('${directory.path}\\shared_preferences.json');
  final marker = File('${directory.path}\\windows-build67-storage-migrated.flag');
  try {
    await directory.create(recursive: true);
    if (!await marker.exists() && await preferences.exists()) {
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final backup = File(
        '${directory.path}\\shared_preferences.before-build67-$stamp.json',
      );
      try {
        await preferences.rename(backup.path);
      } catch (_) {
        await preferences.copy(backup.path);
        await preferences.delete();
      }
      await marker.writeAsString(backup.path, flush: true);
    }
  } catch (error, stackTrace) {
    try {
      final log = File('${Directory.systemTemp.path}\\chernogram-startup.log');
      await log.writeAsString(
        '${DateTime.now().toIso8601String()} storage migration failed: '
        '$error\n$stackTrace\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }
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
    if (Platform.isWindows) {
      _applySystemUi(true);
      if (!mounted) return;
      setState(() {
        _ru = true;
        _darkMode = true;
      });
      _scheduleUpdateCheck();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 6),
      );
      final dark = prefs.getBool('dark_mode') ?? true;
      _applySystemUi(dark);
      if (!mounted) return;
      setState(() {
        _ru = prefs.getString('lang') != 'en';
        _darkMode = dark;
      });
    } catch (_) {
      _applySystemUi(true);
      if (!mounted) return;
      setState(() {
        _ru = true;
        _darkMode = true;
      });
    }
    _scheduleUpdateCheck();
  }

  Future<void> _toggleLanguage() async {
    final next = !(_ru ?? true);
    if (mounted) setState(() => _ru = next);
    if (Platform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lang', next ? 'ru' : 'en');
    } catch (_) {}
  }

  Future<void> _toggleTheme() async {
    final next = !_darkMode;
    _applySystemUi(next);
    if (mounted) setState(() => _darkMode = next);
    if (Platform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dark_mode', next);
    } catch (_) {}
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

  Widget _applicationHome(BuildContext context) {
    if (Platform.isWindows) {
      return ChernogramWindowsDesktop(
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
      );
    }
    return CgAccessGate(
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
    );
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
            : Builder(builder: _applicationHome),
      ),
    );
  }
}
