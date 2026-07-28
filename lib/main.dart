import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigation.dart';
import 'app_update_service.dart';
import 'background_realtime_service.dart';
import 'brand.dart';
import 'crash_reporter.dart';
import 'desktop_tray_service.dart';
import 'notification_service.dart';
import 'v12.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChernogramCrashReporter.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(ChernogramCrashReporter.recordFlutterError(details));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      ChernogramCrashReporter.recordError(
        error,
        stack,
        source: 'PLATFORM_DISPATCHER',
      ),
    );
    return true;
  };

  final startup = runZonedGuarded<Future<void>>(
    () async {
      await ChernogramCrashReporter.breadcrumb('audio background init begin');
      try {
        await JustAudioBackground.init(
          androidNotificationChannelId: 'com.example.chernogram.audio',
          androidNotificationChannelName: 'Музыка Чернограма',
          androidNotificationOngoing: true,
        );
        await ChernogramCrashReporter.breadcrumb('audio background init complete');
      } catch (error, stack) {
        await ChernogramCrashReporter.recordError(
          error,
          stack,
          source: 'AUDIO_BACKGROUND_INIT',
        );
      }
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: ChernogramColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: ChernogramColors.background,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
        ),
      );
      await ChernogramCrashReporter.breadcrumb(
        'recovery foreground-only transport; background isolate disabled',
      );
      await ChernogramCrashReporter.breadcrumb('runApp');
      runApp(const ChernogramApp());
    },
    (error, stack) {
      unawaited(
        ChernogramCrashReporter.recordError(
          error,
          stack,
          source: 'ROOT_ZONE',
        ),
      );
    },
  );
  if (startup != null) await startup;
}

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp>
    with WidgetsBindingObserver {
  bool? _ru;
  bool _darkMode = true;
  bool _introDone = false;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(setChernogramAppForeground(true));
    unawaited(_loadSettings());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    unawaited(setChernogramAppForeground(foreground));
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

  void _finishIntro() {
    if (!mounted) return;
    setState(() => _introDone = true);
    _scheduleUpdateCheck();
  }

  void _scheduleUpdateCheck() {
    if (_updateScheduled || _ru == null) return;
    _updateScheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final context = chernogramNavigatorKey.currentContext;
      if (context == null) {
        _updateScheduled = false;
        _scheduleUpdateCheck();
        return;
      }
      unawaited(
        ChernogramAppUpdater.checkAndPrompt(
          context,
          ru: _ru!,
          manual: false,
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(setChernogramAppForeground(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ru != null;
    SystemChrome.setSystemUIOverlayStyle(
      _darkMode
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: ChernogramColors.background,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarDividerColor: ChernogramColors.background,
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFFF2F6FF),
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarDividerColor: Color(0xFFDCE4F2),
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            ),
    );
    return MaterialApp(
      navigatorKey: chernogramNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: _ru == false ? 'Cernogram' : 'Чернограм',
      theme: chernogramLightTheme(),
      darkTheme: chernogramTheme(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: !ready
          ? const Scaffold(
              body: Center(
                child: ChernogramLogo(size: 112),
              ),
            )
          : !_introDone
              ? ChernogramAnimatedIntro(
                  ru: _ru!,
                  onDone: _finishIntro,
                )
              : Builder(
                  builder: (context) => ChernogramV12(
                    ru: _ru!,
                    darkMode: _darkMode,
                    onToggleTheme: _toggleTheme,
                    onChangeLanguage: _toggleLanguage,
                    onCheckUpdates: () {
                      unawaited(
                        ChernogramAppUpdater.checkAndPrompt(
                          context,
                          ru: _ru!,
                          manual: true,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
