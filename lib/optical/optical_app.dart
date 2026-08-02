import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../brand.dart';
import 'optical_codec.dart';
import 'optical_models.dart';
import 'optical_store.dart';
import 'optical_transfer_screens.dart';

class ChernogramOpticalHome extends StatefulWidget {
  const ChernogramOpticalHome({super.key});

  @override
  State<ChernogramOpticalHome> createState() => _ChernogramOpticalHomeState();
}

class _ChernogramOpticalHomeState extends State<ChernogramOpticalHome> {
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

  Future<void> _createRoom() async {
    final controller = TextEditingController(text: 'Оптическая комната');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая оптическая комната'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название комнаты',
            prefixIcon: Icon(Icons.blur_on_rounded),
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
    if (name == null) return;
    final room = OpticalInviteCodec.createRoom(name);
    setState(() => _rooms = <OpticalRoom>[room, ..._rooms]);
    await _saveRooms();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => OpticalRoomInviteScreen(room: room)),
    );
    if (!mounted) return;
    await _openRoom(room);
  }

  Future<void> _scanRoom() async {
    final room = await Navigator.push<OpticalRoom>(
      context,
      MaterialPageRoute(builder: (_) => const OpticalRoomScannerScreen()),
    );
    if (room == null || !mounted) return;
    final existing = _rooms.indexWhere((item) => item.id == room.id);
    OpticalRoom selected = room;
    if (existing >= 0) {
      selected = _rooms[existing];
    } else {
      setState(() => _rooms = <OpticalRoom>[room, ..._rooms]);
      await _saveRooms();
    }
    if (!mounted) return;
    await _openRoom(selected);
  }

  Future<void> _openRoom(OpticalRoom room) async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OpticalRoomChatScreen(
          profile: profile,
          room: room,
          onChanged: _replaceRoom,
        ),
      ),
    );
  }

  void _replaceRoom(OpticalRoom updated) {
    final rooms = <OpticalRoom>[..._rooms];
    final index = rooms.indexWhere((room) => room.id == updated.id);
    if (index < 0) {
      rooms.add(updated);
    } else {
      rooms[index] = updated;
    }
    rooms.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    setState(() => _rooms = rooms);
    unawaited(_saveRooms());
  }

  Future<void> _deleteRoom(OpticalRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить комнату?'),
        content: Text(
          'Локальная история «${room.name}» будет удалена с этого устройства.',
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
        title: const Text('Имя устройства'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Как вас увидит второе устройство',
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
      return const Scaffold(body: Center(child: ChernogramLogo(size: 148)));
    }
    final pages = <Widget>[
      _RoomsPage(
        rooms: _rooms,
        onCreate: _createRoom,
        onScan: _scanRoom,
        onOpen: _openRoom,
        onDelete: _deleteRoom,
      ),
      _FilesPage(rooms: _rooms, onOpenRoom: _openRoom),
      _LaboratoryPage(profile: _profile!, onEditProfile: _editProfile),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub_rounded),
            label: 'Каналы',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Файлы',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science_rounded),
            label: 'Лаборатория',
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 202,
          title: const Text(
            'Чернограм',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x332BD9A4),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0x6634D6A0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF35D6A2)),
                  SizedBox(width: 6),
                  Text(
                    'OPTICAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFF111426),
                    Color(0xFF17132D),
                    Color(0xFF07131D),
                  ],
                ),
              ),
              child: const SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 58, 20, 12),
                  child: Row(
                    children: [
                      ChernogramLogo(size: 92),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'СВЯЗЬ ЧЕРЕЗ\nЭКРАН И КАМЕРУ',
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.05,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .4,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              'Без Wi‑Fi • без Bluetooth • без интернета',
                              style: TextStyle(
                                color: Color(0xFFB9B3D5),
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
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.add_rounded,
                    title: 'Новая комната',
                    subtitle: 'Создать ключ и показать QR',
                    gradient: const <Color>[
                      Color(0xFF745CFF),
                      Color(0xFF4A62E8),
                    ],
                    onTap: onCreate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Сканировать',
                    subtitle: 'Войти камерой в комнату',
                    gradient: const <Color>[
                      Color(0xFF0D9D92),
                      Color(0xFF1478A8),
                    ],
                    onTap: onScan,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Text(
                  'КОМНАТЫ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rooms.length}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (rooms.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.blur_on_rounded,
                      size: 70,
                      color: scheme.primary.withValues(alpha: .6),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Создайте первую комнату',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Один телефон покажет ключ комнаты, второй считает его камерой. После этого можно передавать сообщения и файлы.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
            sliver: SliverList.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                return _RoomCard(
                  room: room,
                  onTap: () => onOpen(room),
                  onDelete: () => onDelete(room),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _FilesPage extends StatelessWidget {
  final List<OpticalRoom> rooms;
  final Future<void> Function(OpticalRoom room) onOpenRoom;

  const _FilesPage({required this.rooms, required this.onOpenRoom});

  @override
  Widget build(BuildContext context) {
    final entries = <_OpticalFileEntry>[];
    for (final room in rooms) {
      for (final message in room.messages) {
        if (message.isFile) entries.add(_OpticalFileEntry(room, message));
      }
    }
    entries.sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Файлы',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: entries.isEmpty
          ? const _EmptyState(
              icon: Icons.folder_copy_outlined,
              title: 'Файлов пока нет',
              subtitle:
                  'Откройте комнату, выберите файл и передайте его через экран.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.description_outlined),
                    ),
                    title: Text(
                      entry.message.fileName ?? 'Файл',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${entry.room.name} • ${_formatBytes(entry.message.fileSize)}',
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                    onTap: () async {
                      final path = entry.message.filePath;
                      if (path != null && File(path).existsSync()) {
                        await OpenFilex.open(path);
                      } else {
                        await onOpenRoom(entry.room);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _LaboratoryPage extends StatelessWidget {
  final OpticalProfile profile;
  final Future<void> Function() onEditProfile;

  const _LaboratoryPage({required this.profile, required this.onEditProfile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Лаборатория',
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
                colors: <Color>[Color(0xFF201B42), Color(0xFF10263A)],
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
                      const Text(
                        'OPTICAL MVP 01',
                        style: TextStyle(
                          color: Color(0xFF9C8CFF),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        profile.nickname,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEditProfile,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _LabSection(
            title: 'ТЕКУЩИЙ ПРОТОКОЛ',
            children: [
              _LabRow(
                icon: Icons.qr_code_2_rounded,
                title: 'Визуальный поток',
                value: '620 байт/кадр • 5–10 FPS',
              ),
              _LabRow(
                icon: Icons.lock_rounded,
                title: 'Шифрование',
                value: 'ChaCha20‑Poly1305',
              ),
              _LabRow(
                icon: Icons.verified_rounded,
                title: 'Целостность',
                value: 'SHA‑256',
              ),
              _LabRow(
                icon: Icons.cloud_off_rounded,
                title: 'Сеть',
                value: 'Не используется',
              ),
              _LabRow(
                icon: Icons.file_present_rounded,
                title: 'Лимит файла MVP',
                value: '2 МБ',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _LabSection(
            title: 'КАК ПРОВЕРИТЬ',
            children: [
              _NumberedStep(
                number: '1',
                text: 'На первом телефоне создайте комнату и покажите её QR.',
              ),
              _NumberedStep(
                number: '2',
                text: 'На втором телефоне отсканируйте комнату.',
              ),
              _NumberedStep(
                number: '3',
                text: 'На принимающем телефоне нажмите камеру в чате.',
              ),
              _NumberedStep(
                number: '4',
                text: 'На отправляющем введите текст или выберите файл.',
              ),
              _NumberedStep(
                number: '5',
                text: 'Держите движущийся QR полностью внутри рамки камеры.',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x221FAF8A),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x5534D6A0)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_rounded, color: Color(0xFF35D6A2)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Это исследовательская сборка. Первый тест нужен для замера реальной частоты распознавания на ваших двух Android и выбора размера кадра для следующей версии.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class OpticalRoomChatScreen extends StatefulWidget {
  final OpticalProfile profile;
  final OpticalRoom room;
  final ValueChanged<OpticalRoom> onChanged;

  const OpticalRoomChatScreen({
    super.key,
    required this.profile,
    required this.room,
    required this.onChanged,
  });

  @override
  State<OpticalRoomChatScreen> createState() => _OpticalRoomChatScreenState();
}

class _OpticalRoomChatScreenState extends State<OpticalRoomChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late OpticalRoom _room = widget.room;
  bool _preparing = false;

  void _persist() {
    widget.onChanged(_room);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showInvite() => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => OpticalRoomInviteScreen(room: _room)),
  );

  Future<void> _receive() async {
    final message = await Navigator.push<OpticalMessage>(
      context,
      MaterialPageRoute(builder: (_) => OpticalReceiveScreen(room: _room)),
    );
    if (message == null || !mounted) return;
    if (_room.messages.any((item) => item.id == message.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Этот пакет уже был получен.')),
      );
      return;
    }
    setState(() {
      _room = _room.copyWith(
        messages: <OpticalMessage>[..._room.messages, message],
      );
    });
    _persist();
  }

  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty || _preparing) return;
    _text.clear();
    final message = OpticalMessage(
      id: opticalRandomId(12),
      senderId: widget.profile.id,
      senderName: widget.profile.nickname,
      sentAt: DateTime.now(),
      kind: 'text',
      text: value,
      state: 'shown',
    );
    setState(() {
      _room = _room.copyWith(
        messages: <OpticalMessage>[..._room.messages, message],
      );
      _preparing = true;
    });
    _persist();
    try {
      final transfer = await OpticalTransferCodec.encodeText(
        room: _room,
        profile: widget.profile,
        message: message,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OpticalTransmitScreen(transfer: transfer, roomName: _room.name),
        ),
      );
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _sendFile() async {
    if (_preparing) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.first;
    var bytes = selected.bytes;
    if (bytes == null && selected.path != null) {
      bytes = await File(selected.path!).readAsBytes();
    }
    if (bytes == null) {
      _toast('Не удалось прочитать файл.');
      return;
    }
    const maxBytes = 2 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      _toast('В первом Optical MVP файл должен быть не больше 2 МБ.');
      return;
    }
    final message = OpticalMessage(
      id: opticalRandomId(12),
      senderId: widget.profile.id,
      senderName: widget.profile.nickname,
      sentAt: DateTime.now(),
      kind: 'file',
      fileName: selected.name,
      fileSize: bytes.length,
      state: 'shown',
    );
    final local = await OpticalStore.persistFile(
      roomId: _room.id,
      messageId: message.id,
      fileName: selected.name,
      bytes: bytes,
    );
    final storedMessage = message.copyWith(filePath: local.path);
    setState(() {
      _room = _room.copyWith(
        messages: <OpticalMessage>[..._room.messages, storedMessage],
      );
      _preparing = true;
    });
    _persist();
    try {
      final transfer = await OpticalTransferCodec.encodeFile(
        room: _room,
        profile: widget.profile,
        message: storedMessage,
        fileBytes: bytes,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OpticalTransmitScreen(transfer: transfer, roomName: _room.name),
        ),
      );
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const ChernogramLogo(size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: Color(0xFF35D6A2)),
                      SizedBox(width: 5),
                      Text(
                        'ОПТИЧЕСКИЙ КАНАЛ • ОФЛАЙН',
                        style: TextStyle(
                          color: Color(0xFF35D6A2),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .55,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Показать ключ комнаты',
            onPressed: _showInvite,
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0x161CBE95),
            child: const Text(
              'Для приёма нажмите камеру. Для отправки введите текст или выберите файл — появится движущийся QR-поток.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1.3),
            ),
          ),
          Expanded(
            child: _room.messages.isEmpty
                ? const _EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Комната готова',
                    subtitle:
                        'На одном устройстве нажмите камеру, на другом отправьте первое сообщение.',
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    itemCount: _room.messages.length,
                    itemBuilder: (context, index) {
                      final message = _room.messages[index];
                      final mine = message.senderId == widget.profile.id;
                      return _OpticalMessageBubble(
                        message: message,
                        mine: mine,
                        onOpenFile: () async {
                          final path = message.filePath;
                          if (path != null && File(path).existsSync()) {
                            await OpenFilex.open(path);
                          }
                        },
                      );
                    },
                  ),
          ),
          if (_preparing) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filled(
                    tooltip: 'Принимать камерой',
                    onPressed: _preparing ? null : _receive,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF128C7E),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.center_focus_strong_rounded),
                  ),
                  const SizedBox(width: 7),
                  IconButton.filledTonal(
                    tooltip: 'Передать файл',
                    onPressed: _preparing ? null : _sendFile,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_preparing,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение через экран…',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 11,
                        ),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  const SizedBox(width: 7),
                  IconButton.filled(
                    tooltip: 'Передать через экран',
                    onPressed: _preparing ? null : _sendText,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _OpticalMessageBubble extends StatelessWidget {
  final OpticalMessage message;
  final bool mine;
  final Future<void> Function() onOpenFile;

  const _OpticalMessageBubble({
    required this.message,
    required this.mine,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time =
        '${message.sentAt.hour.toString().padLeft(2, '0')}:${message.sentAt.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(13, 10, 12, 8),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  colors: <Color>[Color(0xFF5E50CE), Color(0xFF3D57B8)],
                )
              : null,
          color: mine ? null : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 5),
            bottomRight: Radius.circular(mine ? 5 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    color: Color(0xFF9C8CFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (message.isFile)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onOpenFile,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.description_outlined),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.fileName ?? 'Файл',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _formatBytes(message.fileSize),
                              style: TextStyle(
                                fontSize: 11,
                                color: mine
                                    ? Colors.white70
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Text(
                message.text,
                style: const TextStyle(fontSize: 15.5, height: 1.3),
              ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.state == 'received'
                      ? Icons.center_focus_strong_rounded
                      : Icons.qr_code_2_rounded,
                  size: 12,
                  color: mine ? Colors.white60 : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  message.state == 'received'
                      ? 'получено камерой'
                      : 'показано на экране',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: mine ? Colors.white60 : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: mine ? Colors.white60 : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final Future<void> Function() onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        height: 128,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: Colors.white),
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

class _RoomCard extends StatelessWidget {
  final OpticalRoom room;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RoomCard({
    required this.room,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  color: const Color(0xFF35D6A2),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 3),
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
                ? 'Ключ создан • ждёт первого сеанса'
                : last.isFile
                ? 'Файл: ${last.fileName}'
                : last.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded),
                  SizedBox(width: 10),
                  Text('Удалить'),
                ],
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _LabSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _LabSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.35,
          ),
        ),
        const SizedBox(height: 9),
        ...children,
      ],
    ),
  );
}

class _LabRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _LabRow({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: const Color(0xFF8A7BFF)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    trailing: Flexible(
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _NumberedStep extends StatelessWidget {
  final String number;
  final String text;

  const _NumberedStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF6656D9),
          foregroundColor: Colors.white,
          child: Text(
            number,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 66,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .6),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
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

class _OpticalFileEntry {
  final OpticalRoom room;
  final OpticalMessage message;

  const _OpticalFileEntry(this.room, this.message);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
}
