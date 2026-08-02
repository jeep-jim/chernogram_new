import 'dart:async';

import 'package:flutter/material.dart';

import '../brand.dart';
import '../hybrid/hybrid_app.dart';
import '../interests/interests_page.dart';
import '../library/library_page.dart';
import '../optical/optical_codec.dart';
import '../optical/optical_models.dart';
import '../optical/optical_store.dart';
import '../optical/optical_transfer_screens.dart';

class ChernogramLibraryNetworkHome extends StatefulWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onCheckUpdates;

  const ChernogramLibraryNetworkHome({
    super.key,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramLibraryNetworkHome> createState() =>
      _ChernogramLibraryNetworkHomeState();
}

class _ChernogramLibraryNetworkHomeState
    extends State<ChernogramLibraryNetworkHome> {
  OpticalProfile? _profile;
  List<OpticalRoom> _rooms = <OpticalRoom>[];
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>(<Future<Object>>[
      OpticalStore.loadProfile(),
      OpticalStore.loadRooms(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = values[0] as OpticalProfile;
      _rooms = values[1] as List<OpticalRoom>;
      _loading = false;
    });
  }

  Future<void> _saveRooms() => OpticalStore.saveRooms(_rooms);

  void _replaceRoom(OpticalRoom room) {
    final rooms = <OpticalRoom>[..._rooms];
    final index = rooms.indexWhere((item) => item.id == room.id);
    if (index < 0) {
      rooms.insert(0, room);
    } else {
      rooms[index] = room;
    }
    rooms.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    if (mounted) setState(() => _rooms = rooms);
    unawaited(_saveRooms());
  }

  Future<OpticalRoom> _createRoomNamed(String name) async {
    final room = OpticalInviteCodec.createRoom(name);
    _replaceRoom(room);
    return room;
  }

  Future<void> _createRoom() async {
    final controller = TextEditingController(text: 'Новая комната');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать комнату'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 72,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название или тема',
            prefixIcon: Icon(Icons.forum_outlined),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final room = await _createRoomNamed(name.trim());
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => OpticalRoomInviteScreen(room: room)),
    );
    if (mounted) await _openRoom(room);
  }

  Future<void> _scanRoom() async {
    final room = await Navigator.push<OpticalRoom>(
      context,
      MaterialPageRoute(builder: (_) => const OpticalRoomScannerScreen()),
    );
    if (room == null || !mounted) return;
    final existing = _rooms.where((item) => item.id == room.id).firstOrNull;
    final selected = existing ?? room;
    if (existing == null) _replaceRoom(room);
    await _openRoom(selected);
  }

  Future<void> _openRoom(OpticalRoom room) async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HybridRoomChatScreen(
          profile: profile,
          room: room,
          darkMode: widget.darkMode,
          onChanged: _replaceRoom,
        ),
      ),
    );
  }

  Future<void> _deleteRoom(OpticalRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить комнату?'),
        content: Text(
          'История «${room.name}» удалится только с этого устройства. Файлы, импортированные отдельно в библиотеку, останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _rooms.removeWhere((item) => item.id == room.id));
    await _saveRooms();
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final controller = TextEditingController(text: profile.nickname);
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Имя профиля'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Имя в комнатах и библиотеке',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nickname == null || nickname.isEmpty) return;
    final updated = profile.copyWith(nickname: nickname);
    await OpticalStore.saveProfile(updated);
    if (mounted) setState(() => _profile = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: ChernogramLogo(size: 136)),
      );
    }

    final pages = <Widget>[
      _RoomsPage(
        rooms: _rooms,
        onCreate: _createRoom,
        onScan: _scanRoom,
        onOpen: _openRoom,
        onDelete: _deleteRoom,
      ),
      ChernogramLibraryPage(
        profile: _profile!,
        rooms: _rooms,
        onOpenRoom: _openRoom,
      ),
      ChernogramInterestsPage(
        profile: _profile!,
        rooms: _rooms,
        onCreateRoom: _createRoomNamed,
        onOpenRoom: _openRoom,
      ),
      _ProfilePage(
        profile: _profile!,
        darkMode: widget.darkMode,
        onEditProfile: _editProfile,
        onToggleTheme: widget.onToggleTheme,
        onCheckUpdates: widget.onCheckUpdates,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
            label: 'Чаты',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: 'Библиотека',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Интересы',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

class _RoomsPage extends StatelessWidget {
  final List<OpticalRoom> rooms;
  final Future<void> Function() onCreate;
  final Future<void> Function() onScan;
  final Future<void> Function(OpticalRoom room) onOpen;
  final Future<void> Function(OpticalRoom room) onDelete;

  const _RoomsPage({
    required this.rooms,
    required this.onCreate,
    required this.onScan,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: 192,
        title: const Text(
          'Чернограм',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 14), child: _NetworkPill()),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 58, 20, 10),
              child: Row(
                children: [
                  const ChernogramLogo(size: 88),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ФАЙЛОВАЯ СЕТЬ\nС ЧАТАМИ',
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Общение, медиа, библиотека и поиск тем в одном месте',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.add_comment_rounded,
                  title: 'Новая комната',
                  subtitle: 'Чат или тема интереса',
                  colors: const <Color>[Color(0xFF745CFF), Color(0xFF4E65D9)],
                  onTap: onCreate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Подключиться',
                  subtitle: 'Считать ключ комнаты',
                  colors: const <Color>[Color(0xFF159A91), Color(0xFF1977A2)],
                  onTap: onScan,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              const Text(
                'КОМНАТЫ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text('${rooms.length}'),
            ],
          ),
        ),
      ),
      if (rooms.isEmpty)
        const SliverFillRemaining(hasScrollBody: false, child: _EmptyRooms())
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
          sliver: SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final last = room.messages.isEmpty ? null : room.messages.last;
              return Card(
                margin: const EdgeInsets.only(bottom: 7),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ChernogramAvatar(size: 52, seed: room.id),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF45D3AF),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      last == null
                          ? 'Комната готова'
                          : last.deleted
                          ? 'Сообщение удалено'
                          : last.isFile
                          ? 'Файл: ${last.fileName}'
                          : last.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') onDelete(room);
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded),
                          title: Text('Удалить'),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => onOpen(room),
                ),
              );
            },
          ),
        ),
    ],
  );
}

class _NetworkPill extends StatelessWidget {
  const _NetworkPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x2239D2A6),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: const Color(0x5539D2A6)),
    ),
    child: const Row(
      children: [
        Icon(Icons.circle, size: 8, color: Color(0xFF42D3A7)),
        SizedBox(width: 6),
        Text(
          'LIBRARY',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Future<void> Function() onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        height: 122,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 29, color: Colors.white),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 86),
          const SizedBox(height: 14),
          const Text(
            'Создайте первую комнату',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            'Вложения из комнат автоматически попадут в библиотеку и станут доступны для поиска и воспроизведения.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfilePage extends StatelessWidget {
  final OpticalProfile profile;
  final bool darkMode;
  final Future<void> Function() onEditProfile;
  final VoidCallback onToggleTheme;
  final VoidCallback onCheckUpdates;

  const _ProfilePage({
    required this.profile,
    required this.darkMode,
    required this.onEditProfile,
    required this.onToggleTheme,
    required this.onCheckUpdates,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const Text(
        'Профиль',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF3F3374), Color(0xFF163D58)],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              const ChernogramLogo(size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      profile.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEditProfile,
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  darkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                ),
                title: const Text('Тема'),
                subtitle: Text(darkMode ? 'Градиентная тёмная' : 'Светлая'),
                trailing: Switch(
                  value: darkMode,
                  onChanged: (_) => onToggleTheme(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text('Проверить обновления'),
                subtitle: const Text('Скачать новую версию из GitHub Release'),
                onTap: onCheckUpdates,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.storage_rounded),
                title: Text('Локальное хранилище'),
                subtitle: Text('Файлы и индекс остаются на вашем устройстве'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.devices_rounded),
                title: Text('Мои устройства'),
                subtitle: Text(
                  'Этот телефон зарегистрирован как локальный узел',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
