import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigation.dart';
import 'light/light_chat_app.dart';
import 'light/light_theme.dart';
import 'push_service.dart';
import 'update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(chernogramFirebaseBackgroundHandler);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ChernogramApp());
  unawaited(CgPushService.initialize());
}

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp> {
  bool _darkMode = true;
  bool _ready = false;
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
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  void _applySystemUi(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(_overlay(dark));
  }

  Future<void> _loadSettings() async {
    var dark = true;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
      dark = prefs.getBool('dark_mode') ?? true;
    } catch (_) {}
    _applySystemUi(dark);
    if (!mounted) return;
    setState(() {
      _darkMode = dark;
      _ready = true;
    });
    _scheduleUpdateCheck();
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
        ChernogramUpdater.checkAndPrompt(context, ru: true, manual: false),
      );
    });
  }

  Widget _home(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ChernogramLightHome(
      darkMode: _darkMode,
      onToggleTheme: _toggleTheme,
      onCheckUpdates: () {
        unawaited(
          ChernogramUpdater.checkAndPrompt(context, ru: true, manual: true),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _overlay(_darkMode),
    child: MaterialApp(
      navigatorKey: chernogramNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Чернограм',
      theme: lightChatTheme(Brightness.light),
      darkTheme: lightChatTheme(Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 180),
      home: Builder(builder: _home),
      builder: (context, child) => LightBackdrop(
        dark: _darkMode,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
