import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'media_studio.dart';
import 'tunnels.dart';
import 'update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChernogramApp());
}

enum AppLanguage { ru, en }

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp> {
  AppLanguage? _language;
  LocalProfile? _profile;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = await LocalTunnelStore.loadProfile();
    if (!mounted) return;
    setState(() {
      _language = prefs.getString('lang') == 'en'
          ? AppLanguage.en
          : AppLanguage.ru;
      _profile = profile;
    });
  }

  Future<void> _setLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', language.name);
    if (mounted) setState(() => _language = language);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chernogram',
      theme: chernogramTheme(),
      home: _language == null
          ? const _SplashScreen()
          : ChernogramHome(
              language: _language!,
              profile: _profile,
              onLanguageChanged: _setLanguage,
              onProfileChanged: (profile) => setState(() => _profile = profile),
            ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChernogramLogo(size: 150, withPlate: true),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class ChernogramHome extends StatefulWidget {
  final AppLanguage language;
  final LocalProfile? profile;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final ValueChanged<LocalProfile> onProfileChanged;

  const ChernogramHome({
    super.key,
    required this.language,
    required this.profile,
    required this.onLanguageChanged,
    required this.onProfileChanged,
  });

  @override
  State<ChernogramHome> createState() => _ChernogramHomeState();
}

class _ChernogramHomeState extends State<ChernogramHome> {
  int _tab = 0;

  bool get _ru => widget.language == AppLanguage.ru;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ChernogramUpdater.checkAndPrompt(context, ru: _ru);
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('onboarding_040_shown') ?? false;
      if (!shown && mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _WelcomeSheet(ru: _ru),
        );
        await prefs.setBool('onboarding_040_shown', true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MediaLibraryScreen(ru: _ru),
      DraftStudioScreen(ru: _ru),
      TunnelsScreen(ru: _ru, profile: widget.profile),
      ProfileScreen(
        ru: _ru,
        profile: widget.profile,
        onProfileChanged: widget.onProfileChanged,
        onCheckUpdates: () => ChernogramUpdater.checkAndPrompt(
          context,
          ru: _ru,
          manual: true,
        ),
        onChangeLanguage: () => widget.onLanguageChanged(
          _ru ? AppLanguage.en : AppLanguage.ru,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: BrandHeader(
          subtitle: _ru
              ? 'ЛОКАЛЬНАЯ МЕДИАСТУДИЯ И ТУННЕЛИ'
              : 'LOCAL MEDIA STUDIO & TUNNELS',
        ),
        actions: [
          IconButton(
            tooltip: _ru ? 'Проверить обновления' : 'Check for updates',
            onPressed: () => ChernogramUpdater.checkAndPrompt(
              context,
              ru: _ru,
              manual: true,
            ),
            icon: const Icon(Icons.system_update_alt_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: _ru ? 'Медиа' : 'Media',
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_fix_high_outlined),
            selectedIcon: const Icon(Icons.auto_fix_high),
            label: _ru ? 'Студия' : 'Studio',
          ),
          NavigationDestination(
            icon: const Icon(Icons.cable_outlined),
            selectedIcon: const Icon(Icons.cable),
            label: _ru ? 'Туннели' : 'Tunnels',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: _ru ? 'Профиль' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _WelcomeSheet extends StatelessWidget {
  final bool ru;

  const _WelcomeSheet({required this.ru});

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        Icons.photo_library_outlined,
        ru ? 'Вся галерея телефона' : 'Your complete device gallery',
        ru
            ? 'Фото и видео остаются локально и не загружаются в облако.'
            : 'Photos and videos remain local and are not uploaded to the cloud.',
      ),
      (
        Icons.auto_fix_high,
        ru ? 'Предпросмотр и фильтры' : 'Preview and filters',
        ru
            ? 'Проверьте публикацию в стиле Instagram или Telegram до отправки.'
            : 'Preview content as Instagram or Telegram before publishing.',
      ),
      (
        Icons.cable,
        ru ? 'Туннели для обмена' : 'Sharing tunnels',
        ru
            ? 'Создавайте чат-ссылку, прикрепляйте медиа и приглашайте контакты.'
            : 'Create a chat link, attach media and invite contacts.',
      ),
      (
        Icons.edit_note,
        ru ? 'Текстовый конструктор' : 'Text composer',
        ru
            ? 'Разметка, эмодзи и готовый текст для публикации.'
            : 'Formatting, emoji and publication-ready copy.',
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChernogramLogo(size: 96, withPlate: true),
            const SizedBox(height: 12),
            Text(
              ru ? 'Что умеет Чернограм' : 'What Chernogram can do',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ChernogramColors.surface,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: ChernogramColors.orange.withValues(alpha: .22),
                        child: Icon(card.$1, color: ChernogramColors.goldLight),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.$2, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text(
                              card.$3,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ChernogramColors.textSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ru ? 'Начать' : 'Get started'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
