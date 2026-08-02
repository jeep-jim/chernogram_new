import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../brand.dart';
import '../internet_core.dart';
import '../optical/optical_codec.dart';
import '../optical/optical_models.dart';
import '../optical/optical_store.dart';
import '../optical/optical_transfer_screens.dart';

class ChernogramHybridHome extends StatefulWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onCheckUpdates;

  const ChernogramHybridHome({
    super.key,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramHybridHome> createState() => _ChernogramHybridHomeState();
}

class _ChernogramHybridHomeState extends State<ChernogramHybridHome> {
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

  Future<void> _createRoom() async {
    final controller = TextEditingController(text: 'Новая комната');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать комнату'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название',
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
    if (name == null) return;
    final room = OpticalInviteCodec.createRoom(name);
    _replaceRoom(room);
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
          'История «${room.name}» будет удалена только с этого устройства.',
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
            labelText: 'Имя в комнатах',
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
      _HybridRoomsPage(
        rooms: _rooms,
        onCreate: _createRoom,
        onScan: _scanRoom,
        onOpen: _openRoom,
        onDelete: _deleteRoom,
      ),
      _HybridFilesPage(rooms: _rooms, onOpenRoom: _openRoom),
      _HybridSettingsPage(
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
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Файлы',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}

class _HybridRoomsPage extends StatelessWidget {
  final List<OpticalRoom> rooms;
  final Future<void> Function() onCreate;
  final Future<void> Function() onScan;
  final Future<void> Function(OpticalRoom room) onOpen;
  final Future<void> Function(OpticalRoom room) onDelete;

  const _HybridRoomsPage({
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
              Padding(
                padding: EdgeInsets.only(right: 14),
                child: _RoutePill(
                  icon: Icons.language_rounded,
                  label: 'HYBRID',
                  color: Color(0xFF59D7C4),
                ),
              ),
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
                              'УДАЛЁННАЯ СВЯЗЬ\nИ ОПТИКА РЯДОМ',
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.05,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Wi‑Fi / 4G автоматически • экран и камера без сети',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                      subtitle: 'Чат на любом расстоянии',
                      colors: const [Color(0xFF745CFF), Color(0xFF4E65D9)],
                      onTap: onCreate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'Подключиться',
                      subtitle: 'Считать ключ комнаты',
                      colors: const [Color(0xFF159A91), Color(0xFF1977A2)],
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
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _HybridEmpty(
                icon: Icons.forum_outlined,
                title: 'Создайте первый удалённый чат',
                subtitle:
                    'Передайте ключ комнаты второму телефону один раз. После этого сообщения и файлы будут идти через интернет автоматически.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
              sliver: SliverList.builder(
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  final last = room.messages.isEmpty ? null : room.messages.last;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Card(
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
                                ? 'Комната готова к удалённой связи'
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
                          itemBuilder: (_) => const [
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
                        onTap: () => onOpen(room),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );
}

class HybridRoomChatScreen extends StatefulWidget {
  final OpticalProfile profile;
  final OpticalRoom room;
  final bool darkMode;
  final ValueChanged<OpticalRoom> onChanged;

  const HybridRoomChatScreen({
    super.key,
    required this.profile,
    required this.room,
    required this.darkMode,
    required this.onChanged,
  });

  @override
  State<HybridRoomChatScreen> createState() => _HybridRoomChatScreenState();
}

class _HybridRoomChatScreenState extends State<HybridRoomChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late OpticalRoom _room = widget.room;
  InternetTunnelSession? _session;
  StreamSubscription<InternetEvent>? _subscription;
  String _networkState = 'connecting';
  int _online = 1;
  bool _sendingFile = false;
  final Map<String, double> _fileProgress = <String, double>{};

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final history = await _historyMaps();
    final session = await InternetRelay.open(
      tunnelId: _room.id,
      secret: _room.secretBase64,
      profileId: widget.profile.id,
      nickname: widget.profile.nickname,
      history: history,
    );
    await _subscription?.cancel();
    _session = session;
    _subscription = session.events.listen(_handleEvent);
    if (!mounted) return;
    setState(() {
      _networkState = session.connected ? 'connected' : 'queued';
      _online = session.onlinePeers;
    });
    unawaited(session.sendHistory());
    _sendReadReceipt();
  }

  Future<List<Map<String, dynamic>>> _historyMaps() async {
    final result = <Map<String, dynamic>>[];
    for (final message in _room.messages) {
      String? data;
      final path = message.filePath;
      if (message.isFile && path != null) {
        final file = File(path);
        if (await file.exists() && await file.length() <= 8 * 1024 * 1024) {
          data = base64Encode(await file.readAsBytes());
        }
      }
      result.add(_messageToWire(message, dataBase64: data));
    }
    return result;
  }

  void _handleEvent(InternetEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'status':
        setState(() {
          _networkState = event.data['state']?.toString() ?? 'queued';
        });
        break;
      case 'presence':
        setState(() {
          _online = int.tryParse(event.data['peers']?.toString() ?? '') ?? 1;
        });
        break;
      case 'message':
        final raw = event.data['message'];
        if (raw is Map) unawaited(_acceptWire(Map<String, dynamic>.from(raw)));
        break;
      case 'history':
        final rawMessages = (event.data['messages'] as List?) ?? const [];
        for (final raw in rawMessages.whereType<Map>()) {
          unawaited(_acceptWire(Map<String, dynamic>.from(raw), history: true));
        }
        break;
      case 'control':
        _applyControl(event.data);
        break;
      case 'file_progress':
        final id = event.data['transferId']?.toString() ?? '';
        final received = int.tryParse(event.data['received']?.toString() ?? '') ?? 0;
        final total = int.tryParse(event.data['total']?.toString() ?? '') ?? 0;
        if (id.isNotEmpty && total > 0) {
          setState(() => _fileProgress[id] = received / total);
        }
        break;
    }
  }

  Future<void> _acceptWire(
    Map<String, dynamic> wire, {
    bool history = false,
  }) async {
    final id = wire['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final rawAttachment = wire['attachment'];
    final attachment = rawAttachment is Map
        ? Map<String, dynamic>.from(rawAttachment)
        : null;
    final rawMeta = wire['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};

    String? localPath;
    final data = attachment?['dataBase64']?.toString();
    if (data != null && data.isNotEmpty) {
      final bytes = base64Decode(data);
      final file = await OpticalStore.persistFile(
        roomId: _room.id,
        messageId: id,
        fileName: attachment?['name']?.toString() ?? 'file.bin',
        bytes: bytes,
      );
      localPath = file.path;
    }

    final reactions = <String, List<String>>{};
    final rawReactions = meta['reactions'];
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        reactions[entry.key.toString()] = ((entry.value as List?) ?? const [])
            .map((value) => value.toString())
            .toList();
      }
    }

    final incoming = OpticalMessage(
      id: id,
      senderId: wire['authorId']?.toString() ??
          wire['senderId']?.toString() ??
          '',
      senderName: wire['authorName']?.toString() ??
          wire['senderName']?.toString() ??
          'Устройство',
      sentAt: DateTime.tryParse(wire['sentAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      kind: attachment == null ? 'text' : 'file',
      text: wire['text']?.toString() ?? '',
      fileName: attachment?['name']?.toString(),
      filePath: localPath,
      fileSize: int.tryParse(attachment?['size']?.toString() ?? '') ?? 0,
      state: attachment != null && data == null && meta['fileReady'] == false
          ? 'receiving'
          : 'received',
      deleted: meta['deleted'] == true,
      reactions: reactions,
      readBy: ((meta['readBy'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(),
    );

    final messages = <OpticalMessage>[..._room.messages];
    final index = messages.indexWhere((message) => message.id == incoming.id);
    if (index < 0) {
      messages.add(incoming);
    } else {
      final old = messages[index];
      messages[index] = incoming.copyWith(
        filePath: incoming.filePath ?? old.filePath,
        state: incoming.state == 'receiving' && old.filePath != null
            ? old.state
            : incoming.state,
      );
    }
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    if (!mounted) return;
    setState(() => _room = _room.copyWith(messages: messages));
    _persist();
    if (!history && incoming.senderId != widget.profile.id) {
      _sendReadReceipt(incoming.id);
    }
  }

  Map<String, dynamic> _messageToWire(
    OpticalMessage message, {
    String? dataBase64,
  }) =>
      <String, dynamic>{
        'id': message.id,
        'authorId': message.senderId,
        'authorName': message.senderName,
        'text': message.text,
        'sentAt': message.sentAt.toUtc().toIso8601String(),
        'type': message.isFile ? 'attachment' : 'text',
        if (message.isFile)
          'attachment': <String, dynamic>{
            'id': 'att_${message.id}',
            'name': message.fileName ?? 'file.bin',
            'size': message.fileSize,
            'kind': 'document',
            if (dataBase64 != null) 'dataBase64': dataBase64,
            if (message.filePath != null) 'localPath': message.filePath,
          },
        'meta': <String, dynamic>{
          'hybridVersion': 1,
          'deleted': message.deleted,
          'reactions': message.reactions,
          'readBy': message.readBy,
        },
      };

  void _persist() {
    widget.onChanged(_room);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    _text.clear();
    final message = OpticalMessage(
      id: opticalRandomId(12),
      senderId: widget.profile.id,
      senderName: widget.profile.nickname,
      sentAt: DateTime.now(),
      kind: 'text',
      text: value,
      state: _session?.connected == true ? 'sent' : 'queued',
    );
    setState(() {
      _room = _room.copyWith(messages: [..._room.messages, message]);
    });
    _persist();
    final session = _session;
    if (session == null) {
      await _connect();
    }
    await (_session?.sendMessage(_messageToWire(message)) ?? Future.value());
  }

  Future<void> _sendFile() async {
    if (_sendingFile) return;
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
    const maxBytes = 8 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      _toast('В build 71 удалённый файл должен быть не больше 8 МБ.');
      return;
    }
    setState(() => _sendingFile = true);
    try {
      final message = OpticalMessage(
        id: opticalRandomId(12),
        senderId: widget.profile.id,
        senderName: widget.profile.nickname,
        sentAt: DateTime.now(),
        kind: 'file',
        fileName: selected.name,
        fileSize: bytes.length,
        state: _session?.connected == true ? 'sent' : 'queued',
      );
      final local = await OpticalStore.persistFile(
        roomId: _room.id,
        messageId: message.id,
        fileName: selected.name,
        bytes: bytes,
      );
      final stored = message.copyWith(filePath: local.path);
      setState(() {
        _room = _room.copyWith(messages: [..._room.messages, stored]);
      });
      _persist();
      await (_session?.sendMessage(
            _messageToWire(stored, dataBase64: base64Encode(bytes)),
          ) ??
          Future.value());
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<void> _receiveOptical() async {
    final message = await Navigator.push<OpticalMessage>(
      context,
      MaterialPageRoute(builder: (_) => OpticalReceiveScreen(room: _room)),
    );
    if (message == null || !mounted) return;
    final messages = <OpticalMessage>[..._room.messages];
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    setState(() => _room = _room.copyWith(messages: messages));
    _persist();
  }

  Future<void> _transmitOptical(OpticalMessage message) async {
    OpticalEncodedTransfer transfer;
    if (message.isFile) {
      final path = message.filePath;
      if (path == null || !await File(path).exists()) {
        _toast('Локальный файл не найден.');
        return;
      }
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        _toast('Для оптической передачи файл должен быть не больше 2 МБ.');
        return;
      }
      transfer = await OpticalTransferCodec.encodeFile(
        room: _room,
        profile: widget.profile,
        message: message,
        fileBytes: bytes,
      );
    } else {
      transfer = await OpticalTransferCodec.encodeText(
        room: _room,
        profile: widget.profile,
        message: message,
      );
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OpticalTransmitScreen(
          transfer: transfer,
          roomName: _room.name,
        ),
      ),
    );
  }

  Future<void> _react(OpticalMessage message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: ['👍', '❤️', '😂', '🔥', '👏', '🤝']
                .map(
                  (value) => InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.pop(context, value),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(value, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (emoji == null) return;
    final reactions = <String, List<String>>{
      for (final entry in message.reactions.entries)
        entry.key: [...entry.value],
    };
    final users = reactions.putIfAbsent(emoji, () => <String>[]);
    if (users.contains(widget.profile.id)) {
      users.remove(widget.profile.id);
      if (users.isEmpty) reactions.remove(emoji);
    } else {
      users.add(widget.profile.id);
    }
    _updateMessage(message.id, message.copyWith(reactions: reactions));
    await _session?.sendControl(<String, dynamic>{
      'action': 'hybrid_reaction',
      'messageId': message.id,
      'emoji': emoji,
      'actor': widget.profile.id,
    });
  }

  Future<void> _messageActions(OpticalMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: const Text('Передать рядом через экран'),
              subtitle: const Text('Без интернета, Wi‑Fi и Bluetooth'),
              onTap: () => Navigator.pop(context, 'optical'),
            ),
            if (message.senderId == widget.profile.id && !message.deleted)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Удалить у всех'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'optical') {
      await _transmitOptical(message);
    } else if (action == 'delete') {
      _updateMessage(message.id, message.copyWith(deleted: true));
      await _session?.sendControl(<String, dynamic>{
        'action': 'hybrid_delete',
        'messageId': message.id,
      });
    }
  }

  void _applyControl(Map<String, dynamic> data) {
    final action = data['action']?.toString() ?? '';
    final messageId = data['messageId']?.toString() ?? '';
    if (messageId.isEmpty) return;
    final message = _room.messages.where((item) => item.id == messageId).firstOrNull;
    if (message == null) return;
    if (action == 'hybrid_delete') {
      _updateMessage(messageId, message.copyWith(deleted: true));
    } else if (action == 'hybrid_reaction') {
      final emoji = data['emoji']?.toString() ?? '';
      final actor = data['actor']?.toString() ?? '';
      if (emoji.isEmpty || actor.isEmpty) return;
      final reactions = <String, List<String>>{
        for (final entry in message.reactions.entries)
          entry.key: [...entry.value],
      };
      final users = reactions.putIfAbsent(emoji, () => <String>[]);
      if (users.contains(actor)) {
        users.remove(actor);
        if (users.isEmpty) reactions.remove(emoji);
      } else {
        users.add(actor);
      }
      _updateMessage(messageId, message.copyWith(reactions: reactions));
    } else if (action == 'hybrid_read') {
      final reader = data['reader']?.toString() ?? '';
      if (reader.isEmpty || message.senderId != widget.profile.id) return;
      final readBy = <String>{...message.readBy, reader}.toList();
      _updateMessage(messageId, message.copyWith(readBy: readBy));
    }
  }

  void _sendReadReceipt([String? target]) {
    OpticalMessage? message;
    if (target != null) {
      message = _room.messages.where((item) => item.id == target).firstOrNull;
    } else {
      for (final candidate in _room.messages.reversed) {
        if (candidate.senderId != widget.profile.id && !candidate.deleted) {
          message = candidate;
          break;
        }
      }
    }
    if (message == null) return;
    unawaited(
      _session?.sendControl(<String, dynamic>{
            'action': 'hybrid_read',
            'messageId': message.id,
            'reader': widget.profile.id,
          }) ??
          Future.value(),
    );
  }

  void _updateMessage(String id, OpticalMessage updated) {
    final messages = <OpticalMessage>[..._room.messages];
    final index = messages.indexWhere((item) => item.id == id);
    if (index < 0) return;
    messages[index] = updated;
    setState(() => _room = _room.copyWith(messages: messages));
    _persist();
  }

  Future<void> _showRoomKey() => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => OpticalRoomInviteScreen(room: _room)),
      );

  void _toast(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String get _statusText {
    if (_networkState == 'connected') {
      return _online > 1 ? 'Интернет • $_online онлайн' : 'Интернет • подключено';
    }
    if (_networkState == 'connecting') return 'Подключаем интернет…';
    return 'В очереди • отправим при подключении';
  }

  @override
  Widget build(BuildContext context) {
    final connected = _networkState == 'connected';
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 7,
                        color: connected
                            ? const Color(0xFF45D3AF)
                            : const Color(0xFFFFB85C),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
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
            tooltip: 'Принять рядом камерой',
            onPressed: _receiveOptical,
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
          IconButton(
            tooltip: 'Ключ комнаты',
            onPressed: _showRoomKey,
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: connected
                ? const Color(0x1827B997)
                : const Color(0x1AFFB45B),
            child: Text(
              connected
                  ? 'Сообщения отправляются удалённо автоматически. Камера нужна только для связи рядом без сети.'
                  : 'Нет интернет-маршрута: сообщения сохраняются в очередь. Рядом можно передать через экран.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, height: 1.3),
            ),
          ),
          Expanded(
            child: _room.messages.isEmpty
                ? const _HybridEmpty(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Удалённый чат готов',
                    subtitle:
                        'Напишите сообщение — второй телефон получит его через Wi‑Fi или мобильную сеть без наведения камеры.',
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                    itemCount: _room.messages.length,
                    itemBuilder: (context, index) {
                      final message = _room.messages[index];
                      return _HybridMessageRow(
                        message: message,
                        mine: message.senderId == widget.profile.id,
                        onReaction: () => _react(message),
                        onLongPress: () => _messageActions(message),
                        onOpenFile: () async {
                          final path = message.filePath;
                          if (path != null && await File(path).exists()) {
                            await OpenFilex.open(path);
                          }
                        },
                      );
                    },
                  ),
          ),
          if (_sendingFile) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Файл через интернет',
                    onPressed: _sendingFile ? null : _sendFile,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение…',
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
                    tooltip: 'Отправить удалённо',
                    onPressed: _sendText,
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
    _subscription?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _HybridMessageRow extends StatelessWidget {
  final OpticalMessage message;
  final bool mine;
  final VoidCallback onReaction;
  final VoidCallback onLongPress;
  final Future<void> Function() onOpenFile;

  const _HybridMessageRow({
    required this.message,
    required this.mine,
    required this.onReaction,
    required this.onLongPress,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time =
        '${message.sentAt.hour.toString().padLeft(2, '0')}:${message.sentAt.minute.toString().padLeft(2, '0')}';
    final receipt = message.state == 'queued'
        ? Icons.schedule_rounded
        : message.isRead
            ? Icons.done_all_rounded
            : Icons.done_rounded;
    final reactions = message.reactions.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine)
              IconButton(
                tooltip: 'Реакция',
                visualDensity: VisualDensity.compact,
                onPressed: message.deleted ? null : onReaction,
                icon: const Icon(Icons.add_reaction_outlined, size: 19),
              ),
            Flexible(
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 330),
                  padding: const EdgeInsets.fromLTRB(13, 10, 12, 8),
                  decoration: BoxDecoration(
                    gradient: mine
                        ? const LinearGradient(
                            colors: [Color(0xFF6559D7), Color(0xFF4166B8)],
                          )
                        : null,
                    color: mine ? null : scheme.surfaceContainerHigh,
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
                              color: Color(0xFF9B8CFF),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      if (message.deleted)
                        const Text(
                          'Сообщение удалено',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        )
                      else if (message.isFile)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: onOpenFile,
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .13),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  message.state == 'receiving'
                                      ? Icons.downloading_rounded
                                      : Icons.description_outlined,
                                ),
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
                                    Text(_formatBytes(message.fileSize)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          message.text,
                          style: const TextStyle(fontSize: 15.5, height: 1.3),
                        ),
                      if (reactions.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final entry in reactions)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .13),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('${entry.key} ${entry.value.length}'),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (mine) ...[
                            Icon(
                              receipt,
                              size: 14,
                              color: message.isRead
                                  ? const Color(0xFF71F0D0)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: mine
                                  ? Colors.white70
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (mine)
              IconButton(
                tooltip: 'Реакция',
                visualDensity: VisualDensity.compact,
                onPressed: message.deleted ? null : onReaction,
                icon: const Icon(Icons.add_reaction_outlined, size: 19),
              ),
          ],
        ),
      ),
    );
  }
}

class _HybridFilesPage extends StatelessWidget {
  final List<OpticalRoom> rooms;
  final Future<void> Function(OpticalRoom room) onOpenRoom;

  const _HybridFilesPage({required this.rooms, required this.onOpenRoom});

  @override
  Widget build(BuildContext context) {
    final entries = <({OpticalRoom room, OpticalMessage message})>[];
    for (final room in rooms) {
      for (final message in room.messages) {
        if (message.isFile && !message.deleted) {
          entries.add((room: room, message: message));
        }
      }
    }
    entries.sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Файлы', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: entries.isEmpty
          ? const _HybridEmpty(
              icon: Icons.folder_copy_outlined,
              title: 'Файлов пока нет',
              subtitle: 'Файлы из удалённых и оптических сеансов появятся здесь.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Card(
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
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () async {
                        final path = entry.message.filePath;
                        if (path != null && await File(path).exists()) {
                          await OpenFilex.open(path);
                        } else {
                          await onOpenRoom(entry.room);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HybridSettingsPage extends StatelessWidget {
  final OpticalProfile profile;
  final bool darkMode;
  final Future<void> Function() onEditProfile;
  final VoidCallback onToggleTheme;
  final VoidCallback onCheckUpdates;

  const _HybridSettingsPage({
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
            'Настройки',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: ChernogramAvatar(size: 58, seed: profile.id),
                title: Text(
                  profile.nickname,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(profile.id),
                trailing: const Icon(Icons.edit_rounded),
                onTap: onEditProfile,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: darkMode,
                    onChanged: (_) => onToggleTheme(),
                    secondary: Icon(
                      darkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                    ),
                    title: Text(
                      darkMode ? 'Мягкая тёмная тема' : 'Светлая тема',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text('Выбор сохраняется после перезапуска'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_alt_rounded),
                    title: const Text(
                      'Проверить обновления',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text('Скачать новую версию через интернет'),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: onCheckUpdates,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'МАРШРУТЫ СВЯЗИ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: 12),
                    _SettingRoute(
                      icon: Icons.language_rounded,
                      title: 'Интернет',
                      subtitle: 'Основной канал для любого расстояния',
                      color: Color(0xFF59D7C4),
                    ),
                    _SettingRoute(
                      icon: Icons.center_focus_strong_rounded,
                      title: 'Экран и камера',
                      subtitle: 'Резервный канал рядом без сети',
                      color: Color(0xFF9B8CFF),
                    ),
                    _SettingRoute(
                      icon: Icons.inventory_2_outlined,
                      title: 'Очередь',
                      subtitle: 'Хранит сообщения до восстановления сети',
                      color: Color(0xFFFFBC66),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Чернограм Hybrid 0.31 — удалённые зашифрованные чаты и файлы через интернет, оптическая передача как дополнительный офлайн-канал.',
                  style: TextStyle(height: 1.45),
                ),
              ),
            ),
          ],
        ),
      );
}

class _SettingRoute extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SettingRoute({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .16),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RoutePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RoutePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      );
}

class _HybridEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HybridEmpty({
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
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .65),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
}
