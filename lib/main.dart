import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'update_service.dart';
import 'v06.dart';

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chernogram',
      theme: chernogramLightTheme(),
      darkTheme: chernogramTheme(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _ru == null
          ? const Scaffold(
              body: Center(
                child: ChernogramLogo(size: 112, withPlate: true),
              ),
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
