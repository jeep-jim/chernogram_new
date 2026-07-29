import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'app_monitor.dart';
import 'brand.dart';
import 'call_service.dart';
import 'chat_media.dart';
import 'core_models.dart';
import 'group_call_service.dart';
import 'internet_core.dart';
import 'sound_service.dart';

const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';

class CgChatScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final CgTunnel tunnel;
  final bool privacyLens;
  final bool autoInvite;
  final ValueChanged<CgTunnel> onChanged;
  final ValueChanged<CgContact>? onContactSeen;

  const CgChatScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnel,
    required this.privacyLens,
    required this.onChanged,
    this.onContactSeen,
    this.autoInvite = false,
  });

  @override
  State<CgChatScreen> createState() => _CgChatScreenState();
}

class _CgChatScreenState extends State<CgChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Set<String> _announcedPeers = <String>{};

  late CgTunnel _tunnel;
  InternetTunnelSession? _session;
  StreamSubscription<InternetEvent>? _subscription;
  String _networkState = 'connecting';
  int _onlinePeers = 1;
  bool _sendingFile = false;
  bool _hasText = false;

  bool get _isOwner => widget.profile.id == _tunnel.ownerId;

  bool get _isGroupChat {
    final authors = _tunnel.messages
        .map((message) => message.authorId)
        .where((id) => id.isNotEmpty)
        .toSet();
    authors.add(_tunnel.ownerId);
    return authors.length > 2 ||
        _tunnel.messages.any((message) => message.meta['group'] == true);
  }

  @override
  void initState() {
    super.initState();
    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connect());
    if (widget.autoInvite) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showInvite());
      });
    }
  }

  void _onComposerChanged() {
    final next = _text.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }

  Future<void> _connect() async {
    try {
      final session = await InternetRelay.open(
        tunnelId: _tunnel.id,
        secret: _tunnel.secret,
        profileId: widget.profile.id,
        nickname: widget.profile.nickname,
        history: _tunnel.messages.map((message) => message.toJson()).toList(),
      );
      if (!mounted) return;
      await _subscription?.cancel();
      _session = session;
      _subscription = session.events.listen(_onInternetEvent);
      setState(() {
        _networkState = session.connected ? 'connected' : 'connecting';
        _onlinePeers = session.onlinePeers;
      });
      unawaited(session.sendHistory());
    } catch (_) {
      if (!mounted) return;
      setState(() => _networkState = 'error');
    }
  }

  void _onInternetEvent(InternetEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'message':
        if (event.data['message'] is Map) {
          final raw = Map<String, dynamic>.from(event.data['message'] as Map);
          _playIncomingMessageSound(raw);
          _mergeMessages([raw]);
          _rememberContact(
            raw['authorId']?.toString() ??
                event.data['relaySender']?.toString() ??
                '',
            raw['authorName']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
          );
        }
        break;
      case 'history':
        final messages = ((event.data['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _mergeMessages(messages);
        for (final raw in messages) {
          _rememberContact(
            raw['authorId']?.toString() ?? '',
            raw['authorName']?.toString() ??
                raw['author']?.toString() ??
                'user',
          );
        }
        break;
      case 'peer':
        final id = event.data['id']?.toString() ?? '';
        final name = event.data['name']?.toString() ?? 'user';
        _rememberContact(id, name);
        if (_announcedPeers.add(id)) {
          unawaited(_session?.sendHistory());
          if (_isOwner) unawaited(_sendTunnelSnapshot());
        }
        break;
      case 'presence':
        setState(() {
          _onlinePeers =
              int.tryParse(event.data['peers']?.toString() ?? '') ?? 1;
        });
        break;
      case 'status':
        setState(() {
          _networkState = event.data['state']?.toString() ?? 'connecting';
        });
        break;
      case 'control':
        unawaited(_handleControl(event.data));
        break;
      case 'signal':
        _handleSignal(event.data);
        break;
    }
  }

  void _rememberContact(String id, String name) {
    if (id.isEmpty || id == widget.profile.id) return;
    widget.onContactSeen?.call(
      CgContact(
        id: id,
        nickname: name.trim().isEmpty ? 'user' : name,
        lastSeenAt: DateTime.now(),
        tunnelIds: [_tunnel.id],
      ),
    );
  }

  void _playIncomingMessageSound(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    if (!CgMessageSoundRegistry.claim(id)) return;
    final sentAt = DateTime.tryParse(raw['sentAt']?.toString() ?? '');
    if (sentAt != null &&
        DateTime.now().difference(sentAt.toLocal()).inSeconds.abs() > 30) {
      return;
    }
    unawaited(ChernogramSound.playMessage());
  }

  void _mergeMessages(List<Map<String, dynamic>> raw) {
    final messages = <CgMessage>[..._tunnel.messages];
    var changed = false;
    for (final item in raw) {
      var incoming = CgMessage.fromJson(item);
      if (incoming.id.isEmpty) continue;
      final index = messages.indexWhere((message) => message.id == incoming.id);
      final existing = index < 0 ? null : messages[index];
      incoming = CgMediaStore.preserveLocalPurge(existing, incoming);
      if (index < 0) {
        messages.add(incoming);
        changed = true;
        continue;
      }
      if (jsonEncode(messages[index].toJson()) !=
          jsonEncode(incoming.toJson())) {
        messages[index] = incoming;
        changed = true;
      }
    }
    if (!changed) return;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    _scrollToBottom();
  }

  Future<void> _handleControl(Map<String, dynamic> data) async {
    final action = data['action']?.toString() ?? '';
    final sender = data['relaySender']?.toString() ?? '';
    switch (action) {
      case 'message_delete':
        final messageId = data['messageId']?.toString() ?? '';
        final index = _tunnel.messages.indexWhere(
          (message) => message.id == messageId,
        );
        if (index < 0) return;
        final message = _tunnel.messages[index];
        if (sender != message.authorId) return;
        _replaceMessage(message.copyWith(deleted: true));
        break;
      case 'reaction_toggle':
        final messageId = data['messageId']?.toString() ?? '';
        final emoji = data['emoji']?.toString() ?? '';
        if (messageId.isEmpty || emoji.isEmpty || sender.isEmpty) return;
        final index = _tunnel.messages.indexWhere(
          (message) => message.id == messageId,
        );
        if (index < 0) return;
        final message = _tunnel.messages[index];
        final reactions = <String, List<String>>{
          for (final entry in message.reactions.entries)
            entry.key: [...entry.value],
        };
        final users = reactions.putIfAbsent(emoji, () => <String>[]);
        final add = data['add'] == true;
        if (add && !users.contains(sender)) users.add(sender);
        if (!add) users.remove(sender);
        if (users.isEmpty) reactions.remove(emoji);
        _replaceMessage(message.copyWith(reactions: reactions));
        break;
      case 'tunnel_update':
        if (sender != _tunnel.ownerId) return;
        final revision = int.tryParse(data['revision']?.toString() ?? '') ?? 0;
        if (revision < _tunnel.revision) return;
        final nextSecret = data['secret']?.toString() ?? _tunnel.secret;
        final secretChanged = nextSecret != _tunnel.secret;
        final nextAvatar = data['avatarBase64']?.toString();
        setState(() {
          _tunnel = _tunnel.copyWith(
            name: data['name']?.toString() ?? _tunnel.name,
            isPrivate: data['isPrivate'] != false,
            secret: nextSecret,
            avatarBase64: nextAvatar ?? _tunnel.avatarBase64,
            revision: revision,
          );
        });
        _persist();
        if (secretChanged) {
          await InternetRelay.close(_tunnel.id);
          await _connect();
        }
        break;
    }
  }

  void _replaceMessage(CgMessage updated) {
    final index = _tunnel.messages.indexWhere(
      (message) => message.id == updated.id,
    );
    if (index < 0) return;
    final messages = [..._tunnel.messages];
    messages[index] = updated;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
  }

  void _persist() {
    widget.onChanged(_tunnel);
    _session?.replaceHistory(
      _tunnel.messages.map((message) => message.toJson()).toList(),
    );
  }

  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: value,
      sentAt: DateTime.now(),
    );
    _text.clear();
    _appendLocal(message);
    await _session?.sendMessage(message.toJson());
  }

  void _appendLocal(CgMessage message) {
    if (_tunnel.messages.any((item) => item.id == message.id)) return;
    setState(() {
      _tunnel = _tunnel.copyWith(messages: [..._tunnel.messages, message]);
    });
    _persist();
    _scrollToBottom();
  }

  Future<void> _deleteMessage(CgMessage message) async {
    if (message.authorId != widget.profile.id || message.deleted) return;
    _replaceMessage(message.copyWith(deleted: true));
    await _session?.sendControl({
      'operationId': CgIds.random(24),
      'action': 'message_delete',
      'messageId': message.id,
    });
  }

  Future<void> _toggleReaction(CgMessage message, String emoji) async {
    if (message.deleted) return;
    final users = message.reactions[emoji] ?? const <String>[];
    final add = !users.contains(widget.profile.id);
    final reactions = <String, List<String>>{
      for (final entry in message.reactions.entries)
        entry.key: [...entry.value],
    };
    final nextUsers = reactions.putIfAbsent(emoji, () => <String>[]);
    if (add) {
      nextUsers.add(widget.profile.id);
    } else {
      nextUsers.remove(widget.profile.id);
    }
    if (nextUsers.isEmpty) reactions.remove(emoji);
    _replaceMessage(message.copyWith(reactions: reactions));
    await _session?.sendControl({
      'operationId': CgIds.random(24),
      'action': 'reaction_toggle',
      'messageId': message.id,
      'emoji': emoji,
      'add': add,
    });
  }

  Future<void> _showMessageActions(CgMessage message) async {
    if (message.deleted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Действия с сообщением' : 'Message actions',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: ['👍', '❤️', '😂', '🔥', '👏', '🤝']
                    .map(
                      (emoji) => ActionChip(
                        label: Text(
                          emoji,
                          style: const TextStyle(fontSize: 23),
                        ),
                        onPressed: () => Navigator.pop(context, emoji),
                      ),
                    )
                    .toList(),
              ),
              if (message.authorId == widget.profile.id) ...[
                const Divider(height: 28),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: ChernogramColors.danger,
                  ),
                  title: Text(
                    widget.ru ? 'Удалить сообщение' : 'Delete message',
                    style: const TextStyle(
                      color: ChernogramColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, '__delete__'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__delete__') {
      await _deleteMessage(message);
    } else {
      await _toggleReaction(message, selected);
    }
  }

  Future<void> _pickAttachment(
    FileType type, {
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    const maxBytes = 20 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Сейчас можно отправить файл до 20 МБ. Большие медиа лучше отправлять короткими фрагментами.'
                : 'Files up to 20 MB are supported. Send very large media as shorter clips.',
          ),
        ),
      );
      return;
    }
    setState(() => _sendingFile = true);
    try {
      final id = CgIds.random(20);
      final local = await CgMediaStore.persistBytes(
        attachmentId: id,
        name: file.name,
        bytes: bytes,
      );
      final attachment = CgAttachment(
        id: id,
        name: file.name,
        size: bytes.length,
        kind: _attachmentKind(file.name),
        dataBase64: base64Encode(bytes),
        localPath: local.path,
      );
      await _sendAttachment(attachment);
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<void> _sendAttachment(CgAttachment attachment) async {
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: attachment,
    );
    _appendLocal(message);
    await _session?.sendMessage(message.toJson());
  }

  Future<void> _sendVoice(File file, Duration duration) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    final id = CgIds.random(20);
    final local = await CgMediaStore.persistBytes(
      attachmentId: id,
      name: 'voice.m4a',
      bytes: bytes,
    );
    await _sendAttachment(
      CgAttachment(
        id: id,
        name: 'Голосовое ${duration.inSeconds} сек.m4a',
        size: bytes.length,
        kind: 'voice',
        dataBase64: base64Encode(bytes),
        localPath: local.path,
      ),
    );
  }

  Future<void> _recordCircle() async {
    final attachment = await Navigator.push<CgAttachment>(
      context,
      MaterialPageRoute(builder: (_) => CgCircleRecorderScreen(ru: widget.ru)),
    );
    if (attachment != null) await _sendAttachment(attachment);
  }

  Future<void> _showAttachmentMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Отправить' : 'Send',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  _AttachmentAction(
                    icon: Icons.photo_library_outlined,
                    label: widget.ru ? 'Фото' : 'Photo',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAttachment(FileType.image);
                    },
                  ),
                  _AttachmentAction(
                    icon: Icons.movie_creation_outlined,
                    label: widget.ru ? 'Видео' : 'Video',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAttachment(FileType.video);
                    },
                  ),

                  _AttachmentAction(
                    icon: Icons.radio_button_checked_rounded,
                    label: widget.ru ? 'Кружок' : 'Circle',
                    onTap: () {
                      Navigator.pop(context);
                      _recordCircle();
                    },
                  ),
                  _AttachmentAction(
                    icon: Icons.headphones_outlined,
                    label: widget.ru ? 'Аудио' : 'Audio',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAttachment(FileType.audio);
                    },
                  ),
                  _AttachmentAction(
                    icon: Icons.description_outlined,
                    label: widget.ru ? 'Документ' : 'Document',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAttachment(
                        FileType.custom,
                        allowedExtensions: [
                          'pdf',
                          'doc',
                          'docx',
                          'xls',
                          'xlsx',
                          'ppt',
                          'pptx',
                          'txt',
                          'rtf',
                        ],
                      );
                    },
                  ),
                  _AttachmentAction(
                    icon: Icons.folder_zip_outlined,
                    label: widget.ru ? 'Архив' : 'Archive',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAttachment(
                        FileType.custom,
                        allowedExtensions: ['zip', 'rar', '7z', 'tar', 'gz'],
                      );
                    },
                  ),
                  _AttachmentAction(
                    icon: Icons.attach_file_rounded,
                    label: widget.ru ? 'Любой файл' : 'Any file',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAttachment(FileType.any);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _attachmentKind(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (<String>{'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'}.contains(ext)) {
      return 'image';
    }
    if (<String>{'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus'}.contains(ext)) {
      return 'audio';
    }
    if (<String>{'mp4', 'mov', 'mkv', 'webm'}.contains(ext)) return 'video';
    if (<String>{'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) {
      return 'archive';
    }
    return 'document';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  String get _inviteUrl =>
      '$_landingBase?v=15&invite=${Uri.encodeQueryComponent(_tunnel.inviteToken)}';

  String get _deepInvite =>
      'chernogram://join/${Uri.encodeComponent(_tunnel.inviteToken)}';

  Future<void> _showInvite() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Пригласить в туннель' : 'Invite to tunnel',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'Ссылка работает через интернет. Участники могут находиться в разных городах и сетях.'
                    : 'The invite works over the internet, across cities and networks.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .58),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(data: _deepInvite, size: 220),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Открой чат в Чернограме: $_deepInvite\n\nЕсли приложение не открылось: $_inviteUrl'
                        : 'Open the Chernogram chat: $_deepInvite\n\nIf the app did not open: $_inviteUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(widget.ru ? 'Отправить ссылку' : 'Share invite'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendTunnelSnapshot() async {
    if (!_isOwner) return;
    await _session?.sendControl({
      'operationId': CgIds.random(24),
      'action': 'tunnel_update',
      'name': _tunnel.name,
      'isPrivate': _tunnel.isPrivate,
      'avatarBase64': _tunnel.avatarBase64,
      'secret': _tunnel.secret,
      'revision': _tunnel.revision,
    });
  }

  Future<void> _applyOwnerUpdate(CgTunnel updated) async {
    if (!_isOwner) return;
    final secretChanged = updated.secret != _tunnel.secret;
    await _session?.sendControl({
      'operationId': CgIds.random(24),
      'action': 'tunnel_update',
      'name': updated.name,
      'isPrivate': updated.isPrivate,
      'avatarBase64': updated.avatarBase64,
      'secret': updated.secret,
      'revision': updated.revision,
    });
    setState(() => _tunnel = updated);
    _persist();
    if (secretChanged) {
      await InternetRelay.close(_tunnel.id);
      await _connect();
    }
  }

  Future<void> _changeAvatar() async {
    if (!_isOwner) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    if (bytes.length > 2 * 1024 * 1024 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Для аватарки выберите изображение меньше 2 МБ.'
                : 'Choose an avatar image under 2 MB.',
          ),
        ),
      );
      return;
    }
    final updated = _tunnel.copyWith(
      avatarBase64: base64Encode(bytes),
      revision: _tunnel.revision + 1,
    );
    await _applyOwnerUpdate(updated);
  }

  Future<void> _showSettings() async {
    if (!_isOwner) return;
    final name = TextEditingController(text: _tunnel.name);
    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    final result =
        await showModalBottomSheet<
          ({String name, bool isPrivate, bool revoke})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.ru ? 'Настройки туннеля' : 'Tunnel settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: widget.ru
                          ? 'Название — необязательно'
                          : 'Name — optional',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: isPrivate,
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      isPrivate ? Icons.visibility_off_outlined : Icons.public,
                    ),
                    title: Text(
                      isPrivate
                          ? (widget.ru ? 'Приватный' : 'Private')
                          : (widget.ru ? 'Открытый' : 'Open'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      isPrivate
                          ? (widget.ru
                                ? 'Вход только по секретной ссылке или QR.'
                                : 'Join only with the secret invite or QR.')
                          : (widget.ru
                                ? 'Ссылку можно свободно пересылать.'
                                : 'The invite may be freely forwarded.'),
                    ),
                    onChanged: (value) =>
                        setSheetState(() => isPrivate = value),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: revoke,
                    onChanged: (value) =>
                        setSheetState(() => revoke = value ?? false),
                    title: Text(
                      widget.ru
                          ? 'Отозвать старую ссылку и QR'
                          : 'Revoke the old link and QR',
                    ),
                    subtitle: Text(
                      widget.ru
                          ? 'Все уже подключённые участники получат новый ключ автоматически.'
                          : 'Connected members receive the new key automatically.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, (
                        name: name.text.trim(),
                        isPrivate: isPrivate,
                        revoke: revoke,
                      )),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(widget.ru ? 'Сохранить' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    name.dispose();
    if (result == null) return;
    final updated = _tunnel.copyWith(
      name: result.name,
      isPrivate: result.isPrivate,
      secret: result.revoke ? CgIds.random(42) : _tunnel.secret,
      revision: _tunnel.revision + 1,
    );
    await _applyOwnerUpdate(updated);
  }

  Future<void> _startCall(bool video) async {
    if (_networkState != 'connected') {
      _showNotConnected();
      return;
    }
    final callId = CgIds.random(22);
    final outcome = await Navigator.push<CgCallOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ChernogramCallScreen(
          tunnelName: _tunnel.displayName,
          tunnelId: _tunnel.id,
          secret: _tunnel.secret,
          profileId: widget.profile.id,
          nickname: widget.profile.nickname,
          callId: callId,
          isCaller: true,
          video: video,
          ru: widget.ru,
        ),
      ),
    );
    if (outcome != null) {
      await _appendCallEvent(
        video: video,
        group: false,
        status: outcome.status,
        durationSeconds: outcome.durationSeconds,
        participants: outcome.connected ? 2 : 1,
      );
    }
  }

  Future<void> _startGroupCall({required bool video}) async {
    if (_networkState != 'connected') {
      _showNotConnected();
      return;
    }
    final callId = CgIds.random(22);
    final outcome = await Navigator.push<CgCallOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ChernogramGroupCallScreen(
          tunnelName: _tunnel.displayName,
          tunnelId: _tunnel.id,
          secret: _tunnel.secret,
          profileId: widget.profile.id,
          nickname: widget.profile.nickname,
          callId: callId,
          isHost: true,
          video: video,
          ru: widget.ru,
        ),
      ),
    );
    if (outcome != null) {
      await _appendCallEvent(
        video: video,
        group: true,
        status: outcome.status,
        durationSeconds: outcome.durationSeconds,
        participants: _onlinePeers.clamp(1, 6).toInt(),
      );
    }
  }

  Future<void> _appendCallEvent({
    required bool video,
    required bool group,
    required String status,
    required int durationSeconds,
    required int participants,
  }) async {
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'call',
      meta: {
        'video': video,
        'group': group,
        'status': status,
        'durationSeconds': durationSeconds,
        'participants': participants,
      },
    );
    _appendLocal(message);
    await _session?.sendMessage(message.toJson());
  }

  void _showNotConnected() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'Сначала дождитесь подключения туннеля.'
              : 'Wait for the tunnel to connect first.',
        ),
      ),
    );
  }

  void _handleSignal(Map<String, dynamic> signal) {
    final action = signal['action']?.toString() ?? '';
    if (action == 'call_invite') {
      _handleDirectInvite(signal);
    } else if (action == 'group_call_invite') {
      _handleGroupInvite(signal);
    }
  }

  void _handleDirectInvite(Map<String, dynamic> signal) {
    final callId = signal['callId']?.toString() ?? '';
    final from =
        signal['from']?.toString() ?? signal['relaySender']?.toString() ?? '';
    if (callId.isEmpty || from.isEmpty || from == widget.profile.id) return;
    if (!CgSignalRegistry.claim(callId)) return;
    final video = signal['video'] == true;
    final fromName =
        signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        (widget.ru ? 'Собеседник' : 'Peer');
    _rememberContact(from, fromName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showIncomingCall(callId, from, fromName, video));
      }
    });
  }

  void _handleGroupInvite(Map<String, dynamic> signal) {
    final callId = signal['callId']?.toString() ?? '';
    final from =
        signal['from']?.toString() ?? signal['relaySender']?.toString() ?? '';
    if (callId.isEmpty || from.isEmpty || from == widget.profile.id) return;
    if (!CgSignalRegistry.claim(callId)) return;
    final video = signal['video'] != false;
    final fromName =
        signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        (widget.ru ? 'Организатор' : 'Host');
    _rememberContact(from, fromName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_showIncomingGroupCall(callId, fromName, video));
      }
    });
  }

  Future<void> _showIncomingCall(
    String callId,
    String fromId,
    String fromName,
    bool video,
  ) async {
    await ChernogramSound.startIncomingCall(video: video);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          video ? Icons.videocam_rounded : Icons.call_rounded,
          size: 38,
        ),
        title: Text(
          video
              ? (widget.ru ? 'Видеозвонок' : 'Video call')
              : (widget.ru ? 'Аудиозвонок' : 'Audio call'),
        ),
        content: Text(
          widget.ru ? '$fromName звонит вам' : '$fromName is calling you',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.danger,
            ),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.call_end),
          ),
          const SizedBox(width: 20),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.success,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call),
          ),
        ],
      ),
    );
    await ChernogramSound.stopIncomingCall();
    if (accepted != true) {
      await _session?.sendSignal({
        'action': 'call_decline',
        'callId': callId,
        'from': widget.profile.id,
        'target': fromId,
      });
      return;
    }
    if (!mounted) return;
    await Navigator.push<CgCallOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ChernogramCallScreen(
          tunnelName: _tunnel.displayName,
          tunnelId: _tunnel.id,
          secret: _tunnel.secret,
          profileId: widget.profile.id,
          nickname: widget.profile.nickname,
          peerId: fromId,
          peerName: fromName,
          callId: callId,
          isCaller: false,
          video: video,
          ru: widget.ru,
        ),
      ),
    );
  }

  Future<void> _showIncomingGroupCall(
    String callId,
    String fromName,
    bool video,
  ) async {
    await ChernogramSound.startIncomingCall(video: video);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          video ? Icons.groups_2_rounded : Icons.group_rounded,
          size: 40,
        ),
        title: Text(
          video
              ? (widget.ru ? 'Групповой видеозвонок' : 'Group video call')
              : (widget.ru ? 'Групповой звонок' : 'Group call'),
        ),
        content: Text(
          widget.ru
              ? '$fromName приглашает в звонок до 6 участников.'
              : '$fromName invites you to a call for up to 6 participants.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Пропустить' : 'Dismiss'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call_rounded),
            label: Text(widget.ru ? 'Подключиться' : 'Join'),
          ),
        ],
      ),
    );
    await ChernogramSound.stopIncomingCall();
    if (accepted != true || !mounted) return;
    await Navigator.push<CgCallOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ChernogramGroupCallScreen(
          tunnelName: _tunnel.displayName,
          tunnelId: _tunnel.id,
          secret: _tunnel.secret,
          profileId: widget.profile.id,
          nickname: widget.profile.nickname,
          callId: callId,
          isHost: false,
          video: video,
          ru: widget.ru,
        ),
      ),
    );
  }

  String get _statusText {
    if (_networkState == 'connected') {
      return widget.ru ? 'Онлайн • $_onlinePeers' : 'Online • $_onlinePeers';
    }
    if (_networkState == 'queued') {
      return widget.ru ? 'Отправим при подключении' : 'Will send when online';
    }
    if (_networkState == 'error' || _networkState == 'disconnected') {
      return widget.ru ? 'Переподключаемся…' : 'Reconnecting…';
    }
    return widget.ru ? 'Подключение…' : 'Connecting…';
  }

  @override
  void dispose() {
    unawaited(ChernogramSound.stopIncomingCall());
    unawaited(_subscription?.cancel());
    _text.removeListener(_onComposerChanged);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canInvite = _isOwner || !_tunnel.isPrivate;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: _isGroupChat ? 58 : 50,
        leading: _isGroupChat
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ChernogramAvatar(
                  size: 42,
                  seed: _tunnel.id,
                  avatarBase64: _tunnel.avatarBase64,
                ),
              )
            : const BackButton(),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.privacyLens ? '••••••••' : _tunnel.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              _statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: _networkState == 'connected'
                    ? ChernogramColors.success
                    : scheme.onSurface.withValues(alpha: .46),
              ),
            ),
          ],
        ),
        actions: [
          GlassIconButton(
            icon: Icons.call_outlined,
            tooltip: widget.ru ? 'Позвонить' : 'Call',
            onPressed: () => _startCall(false),
          ),
          PopupMenuButton<String>(
            tooltip: widget.ru ? 'Действия' : 'Actions',
            onSelected: (value) {
              switch (value) {
                case 'video':
                  _startCall(true);
                  break;
                case 'group_video':
                  _startGroupCall(video: true);
                  break;
                case 'group_audio':
                  _startGroupCall(video: false);
                  break;
                case 'invite':
                  _showInvite();
                  break;
                case 'avatar':
                  _changeAvatar();
                  break;
                case 'settings':
                  _showSettings();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'video',
                child: ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(widget.ru ? 'Видеозвонок' : 'Video call'),
                ),
              ),
              PopupMenuItem(
                value: 'group_video',
                child: ListTile(
                  leading: const Icon(Icons.groups_2_outlined),
                  title: Text(
                    widget.ru ? 'Групповое видео до 6' : 'Group video up to 6',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'group_audio',
                child: ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: Text(
                    widget.ru ? 'Групповой аудиозвонок' : 'Group audio call',
                  ),
                ),
              ),
              if (canInvite)
                PopupMenuItem(
                  value: 'invite',
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(widget.ru ? 'Пригласить' : 'Invite'),
                  ),
                ),
              if (_isOwner)
                PopupMenuItem(
                  value: 'avatar',
                  child: ListTile(
                    leading: const Icon(Icons.add_photo_alternate_outlined),
                    title: Text(widget.ru ? 'Аватар туннеля' : 'Tunnel avatar'),
                  ),
                ),
              if (_isOwner)
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(widget.ru ? 'Настройки' : 'Settings'),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CgChatPatternBackground(
        child: Column(
          children: [
            if (_networkState != 'connected')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                child: Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .62),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _tunnel.messages.isEmpty
                  ? _EmptyChat(
                      ru: widget.ru,
                      onInvite: canInvite ? _showInvite : null,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                      itemCount: _tunnel.messages.length,
                      itemBuilder: (context, index) {
                        final message = _tunnel.messages[index];
                        final mine =
                            message.authorId == widget.profile.id ||
                            (message.authorId.isEmpty &&
                                message.authorName == widget.profile.nickname);
                        return _MessageBubble(
                          message: message,
                          mine: mine,
                          groupChat: _isGroupChat,
                          privacyLens: widget.privacyLens,
                          ru: widget.ru,
                          onLongPress: () => _showMessageActions(message),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: GlassPanel(
                  padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                  borderRadius: BorderRadius.circular(22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: widget.ru ? 'Добавить' : 'Add',
                        onPressed: _sendingFile ? null : _showAttachmentMenu,
                        icon: _sendingFile
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _sendText(),
                          decoration: InputDecoration(
                            hintText: widget.ru ? 'Сообщение' : 'Message',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _hasText
                            ? IconButton.filled(
                                key: const ValueKey('send'),
                                onPressed: _sendText,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              )
                            : CgVoiceRecordButton(
                                key: const ValueKey('voice'),
                                ru: widget.ru,
                                enabled: _networkState == 'connected',
                                onRecorded: _sendVoice,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 31, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TunnelAvatar extends StatelessWidget {
  final CgTunnel tunnel;
  final double size;

  const _TunnelAvatar({required this.tunnel, required this.size});

  @override
  Widget build(BuildContext context) {
    final raw = tunnel.avatarBase64;
    if (raw != null) {
      try {
        final bytes = base64Decode(raw);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * .32),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(
          colors: tunnel.isPrivate
              ? const [Color(0xFF795DFF), Color(0xFF27396F)]
              : const [Color(0xFF00A9D9), Color(0xFF3867E8)],
        ),
      ),
      child: Icon(
        tunnel.isPrivate ? Icons.visibility_off_outlined : Icons.public,
        color: Colors.white,
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final bool ru;
  final VoidCallback? onInvite;

  const _EmptyChat({required this.ru, required this.onInvite});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChernogramLogo(size: 82),
          const SizedBox(height: 18),
          Text(
            ru ? 'Туннель готов' : 'Tunnel is ready',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            onInvite != null
                ? (ru
                      ? 'Отправьте ссылку человеку — после подключения можно писать, звонить и обмениваться файлами.'
                      : 'Share the invite to message, call and exchange files.')
                : (ru
                      ? 'Ожидайте сообщения от участников.'
                      : 'Waiting for messages from members.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .55),
            ),
          ),
          if (onInvite != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(ru ? 'Пригласить человека' : 'Invite someone'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  final CgMessage message;
  final bool mine;
  final bool groupChat;
  final bool privacyLens;
  final bool ru;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.groupChat,
    required this.privacyLens,
    required this.ru,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (message.type == 'call') {
      return _CallMessageCard(
        message: message,
        mine: mine,
        ru: ru,
        privacyLens: privacyLens,
        onLongPress: onLongPress,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final attachment = message.attachment;
    final showAvatar = groupChat && !mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChernogramAvatar(
                    size: 27,
                    seed: message.authorId.isEmpty
                        ? message.authorName
                        : message.authorId,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    privacyLens ? '••••' : message.authorName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface.withValues(alpha: .52),
                    ),
                  ),
                ],
              ),
            ),
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 350),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: mine
                    ? scheme.primary.withValues(alpha: .88)
                    : scheme.surfaceContainerHighest.withValues(alpha: .91),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(mine ? 20 : 5),
                  topRight: Radius.circular(mine ? 5 : 20),
                  bottomLeft: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.deleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: mine
                              ? Colors.white60
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          ru ? 'Сообщение удалено' : 'Message deleted',
                          style: TextStyle(
                            color: mine
                                ? Colors.white60
                                : scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    if (attachment != null)
                      CgInlineAttachment(
                        attachment: attachment,
                        hidden: privacyLens,
                      ),
                    if (message.text.isNotEmpty) ...[
                      if (attachment != null) const SizedBox(height: 7),
                      Text(
                        privacyLens ? '••••••••••' : message.text,
                        style: TextStyle(
                          color: mine ? Colors.white : scheme.onSurface,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                  if (!message.deleted && message.reactions.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: message.reactions.entries
                          .where((entry) => entry.value.isNotEmpty)
                          .map(
                            (entry) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .13),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${entry.key} ${entry.value.length}',
                                style: TextStyle(
                                  color: mine ? Colors.white : scheme.onSurface,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatTime(message.sentAt),
                      style: TextStyle(
                        fontSize: 9,
                        color: mine
                            ? Colors.white60
                            : scheme.onSurface.withValues(alpha: .42),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _CallMessageCard extends StatelessWidget {
  final CgMessage message;
  final bool mine;
  final bool ru;
  final bool privacyLens;
  final VoidCallback onLongPress;

  const _CallMessageCard({
    required this.message,
    required this.mine,
    required this.ru,
    required this.privacyLens,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final video = message.meta['video'] == true;
    final group = message.meta['group'] == true;
    final status = message.meta['status']?.toString() ?? 'completed';
    final seconds =
        int.tryParse(message.meta['durationSeconds']?.toString() ?? '') ?? 0;
    final participants =
        int.tryParse(message.meta['participants']?.toString() ?? '') ?? 2;
    final successful = status == 'completed';
    final title = group
        ? (video
              ? (ru ? 'Групповой видеозвонок' : 'Group video call')
              : (ru ? 'Групповой звонок' : 'Group call'))
        : (video
              ? (ru ? 'Видеозвонок' : 'Video call')
              : (ru ? 'Аудиозвонок' : 'Audio call'));
    String subtitle;
    if (successful) {
      subtitle =
          '${mine ? (ru ? 'Исходящий' : 'Outgoing') : (ru ? 'Входящий' : 'Incoming')}'
          '${group ? ' • $participants' : ''}'
          ' • ${_durationText(seconds, ru)}';
    } else if (status == 'declined') {
      subtitle = mine
          ? (ru ? 'Звонок отклонён' : 'Call declined')
          : (ru ? 'Отклонённый звонок' : 'Declined call');
    } else if (status == 'cancelled') {
      subtitle = ru ? 'Звонок отменён' : 'Call cancelled';
    } else {
      subtitle = mine
          ? (ru ? 'Нет ответа' : 'No answer')
          : (ru ? 'Пропущенный звонок' : 'Missed call');
    }

    final cardColor = dark ? const Color(0xFF0B0E15) : const Color(0xFFE9EDF5);
    final accent = successful
        ? (video ? ChernogramColors.cyan : ChernogramColors.success)
        : ChernogramColors.danger;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 335),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      privacyLens ? '••••••••' : title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      privacyLens ? '••••••••' : subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .58),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _MessageBubble._formatTime(message.sentAt),
                      style: TextStyle(
                        fontSize: 9,
                        color: scheme.onSurface.withValues(alpha: .38),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  group
                      ? Icons.groups_2_rounded
                      : video
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  color: accent,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _durationText(int seconds, bool ru) {
    if (seconds <= 0) return ru ? 'меньше минуты' : 'under a minute';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes == 0) return '$rest ${ru ? 'сек' : 'sec'}';
    if (rest == 0) return '$minutes ${ru ? 'мин' : 'min'}';
    return '$minutes ${ru ? 'мин' : 'min'} $rest ${ru ? 'сек' : 'sec'}';
  }
}

class _AttachmentPreview extends StatelessWidget {
  final CgAttachment attachment;
  final bool hidden;

  const _AttachmentPreview({required this.attachment, required this.hidden});

  Uint8List? get _bytes {
    final raw = attachment.dataBase64;
    if (raw == null) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (hidden) {
      return Container(
        width: 240,
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.visibility_off_outlined, color: Colors.white70),
      );
    }
    final bytes = _bytes;
    if (attachment.kind == 'image' && bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          bytes,
          width: 260,
          height: 190,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            attachment.kind == 'audio'
                ? Icons.graphic_eq_rounded
                : attachment.kind == 'video'
                ? Icons.movie_outlined
                : attachment.kind == 'archive'
                ? Icons.folder_zip_outlined
                : Icons.description_outlined,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  _fileSize(attachment.size),
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
