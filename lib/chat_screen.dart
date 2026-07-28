import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_monitor.dart';
import 'brand.dart';
import 'call_avatar.dart';
import 'call_service.dart';
import 'chat_background.dart';
import 'chat_media.dart';
import 'core_models.dart';
import 'group_call_service.dart';
import 'internet_core.dart';
import 'music_player.dart';
import 'shared_library.dart';
import 'sound_service.dart';

const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';
const String _androidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';

class CgChatScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final CgTunnel tunnel;
  final bool privacyLens;
  final bool autoInvite;
  final ValueChanged<CgTunnel> onChanged;
  final Future<void> Function(CgTunnel tunnel)? onDelete;
  final Future<void> Function(CgMessage message)? onForward;
  final ValueChanged<CgContact>? onContactSeen;

  const CgChatScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnel,
    required this.privacyLens,
    required this.onChanged,
    this.onDelete,
    this.onForward,
    this.onContactSeen,
    this.autoInvite = false,
  });

  @override
  State<CgChatScreen> createState() => _CgChatScreenState();
}

class _CgChatScreenState extends State<CgChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'chat-composer');
  final Set<String> _announcedPeers = <String>{};

  late CgTunnel _tunnel;
  InternetTunnelSession? _session;
  StreamSubscription<InternetEvent>? _subscription;
  String _networkState = 'connecting';
  int _onlinePeers = 0;
  bool _sendingFile = false;
  bool _hasText = false;
  CgMessage? _replyingTo;

  bool get _isOwner => widget.profile.id == _tunnel.ownerId;

  bool get _canWrite => _isOwner || _tunnel.permissions.canWriteMessages;
  bool get _canSendMedia => _isOwner || _tunnel.permissions.canSendMedia;
  bool get _canDownload => _isOwner || _tunnel.permissions.canDownload;
  bool get _canInvite =>
      _isOwner || _tunnel.permissions.canInvite || !_tunnel.isPrivate;
  bool get _canCall => _isOwner || _tunnel.permissions.canCall;

  String? get _preferredPeerId {
    final session = _session;
    if (session == null) return null;
    for (final member in session.members) {
      if (member['self'] == true) continue;
      final id = member['id']?.toString() ?? '';
      if (id.isNotEmpty && id != widget.profile.id) return id;
    }
    return null;
  }

  String? get _preferredPeerName {
    for (final message in _tunnel.messages.reversed) {
      final id = message.authorId.trim();
      if (id.isNotEmpty && id != widget.profile.id) return message.authorName;
    }
    return null;
  }

  Future<void> _sendBytes(String name, List<int> bytes) async {
    if (!_canSendMedia || bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      return;
    }
    final id = CgIds.random(20);
    final local = await CgMediaStore.persistBytes(
      attachmentId: id,
      name: name,
      bytes: bytes,
    );
    await _sendAttachment(
      CgAttachment(
        id: id,
        name: name,
        size: bytes.length,
        kind: CgSharedLibraryStore.kindForName(name),
        dataBase64: base64Encode(bytes),
        localPath: local.path,
      ),
    );
  }

  Future<void> _sendFilePath(String path, {String? displayName}) async {
    if (!_canSendMedia) return;
    final file = File(path);
    if (!await file.exists()) return;
    final length = await file.length();
    if (length <= 0 || length > 20 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Можно отправлять файлы до 20 МБ.'
                  : 'Files up to 20 MB can be sent.',
            ),
          ),
        );
      }
      return;
    }
    await _sendBytes(
      displayName ?? path.split(Platform.pathSeparator).last,
      await file.readAsBytes(),
    );
  }

  Future<void> _handleDropped(DropDoneDetails details) async {
    if (!_canSendMedia) return;
    setState(() => _sendingFile = true);
    try {
      for (final item in details.files) {
        if (item is DropItemDirectory) continue;
        final length = await item.length();
        if (length <= 0 || length > 20 * 1024 * 1024) continue;
        await _sendBytes(item.name, await item.readAsBytes());
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Future<File?> _ensureAttachment(CgMessage message) async {
    final attachment = message.attachment;
    if (attachment == null) return null;
    final existing = await CgMediaStore.existingFile(attachment);
    if (existing != null) return existing;
    await _session?.sendControl(<String, dynamic>{
      'operationId': CgIds.random(24),
      'action': 'attachment_request',
      'target': message.authorId,
      'messageId': message.id,
      'attachmentId': attachment.id,
    });
    for (var attempt = 0; attempt < 80; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final currentIndex = _tunnel.messages.indexWhere(
        (item) => item.id == message.id,
      );
      if (currentIndex < 0) break;
      final current = _tunnel.messages[currentIndex].attachment;
      if (current == null) break;
      final file = await CgMediaStore.existingFile(current);
      if (file != null) return file;
    }
    return null;
  }

  Future<void> _playAttachment(CgAttachment attachment, File file) async {
    await CgMusicHub.instance.playFile(
      id: 'chat:${_tunnel.id}:${attachment.id}',
      title: attachment.name,
      subtitle: _tunnel.displayName,
      path: file.path,
    );
  }

  Future<void> _handleAttachmentRequest(
    Map<String, dynamic> data,
    String sender,
  ) async {
    final target = data['target']?.toString() ?? '';
    if (target.isNotEmpty && target != widget.profile.id) return;
    final messageId = data['messageId']?.toString() ?? '';
    final index = _tunnel.messages.indexWhere((item) => item.id == messageId);
    if (index < 0) return;
    final message = _tunnel.messages[index];
    if (message.authorId != widget.profile.id || message.attachment == null)
      return;
    final file = await CgMediaStore.existingFile(message.attachment!);
    if (file == null || !await file.exists()) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) return;
    await _session?.sendControl(<String, dynamic>{
      'operationId': CgIds.random(24),
      'action': 'attachment_response',
      'target': sender,
      'messageId': message.id,
      'attachment': <String, dynamic>{
        ...message.attachment!.metadataJson(),
        'dataBase64': base64Encode(bytes),
      },
    });
  }

  Future<void> _handleAttachmentResponse(Map<String, dynamic> data) async {
    if (data['target']?.toString() != widget.profile.id) return;
    final messageId = data['messageId']?.toString() ?? '';
    final rawAttachment = data['attachment'];
    if (rawAttachment is! Map) return;
    final index = _tunnel.messages.indexWhere((item) => item.id == messageId);
    if (index < 0) return;
    final incoming = CgAttachment.fromJson(
      Map<String, dynamic>.from(rawAttachment),
    );
    final cached = await CgMediaStore.cacheIncomingMessage(
      _tunnel.messages[index].copyWith(attachment: incoming),
    );
    _replaceMessage(cached);
  }

  Future<void> _handleShareRequest(
    Map<String, dynamic> data,
    String sender,
  ) async {
    final target = data['target']?.toString() ?? '';
    if (target.isNotEmpty && target != widget.profile.id) return;
    final fileId = data['fileId']?.toString() ?? '';
    final item = await CgSharedLibraryStore.find(_tunnel.id, fileId);
    if (item == null) return;
    await _sendFilePath(item.path, displayName: item.info.name);
  }

  Future<void> _showSharedLibrary() async {
    var local = await CgSharedLibraryStore.loadTunnelFiles(_tunnel.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.ru ? 'Общие файлы' : 'Shared files',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (_isOwner && Platform.isWindows)
                        FilledButton.icon(
                          onPressed: () async {
                            local = await CgSharedLibraryStore.chooseFolder(
                              _tunnel.id,
                            );
                            final updated = _tunnel.copyWith(
                              sharedFiles: local
                                  .map((item) => item.info)
                                  .toList(),
                              revision: _tunnel.revision + 1,
                            );
                            await _applyOwnerUpdate(updated);
                            if (context.mounted) setSheetState(() {});
                          },
                          icon: const Icon(Icons.folder_shared_outlined),
                          label: Text(
                            widget.ru ? 'Выбрать папку' : 'Choose folder',
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _tunnel.sharedFiles.isEmpty
                      ? Center(
                          child: Text(
                            widget.ru
                                ? 'Общая папка пока не настроена.'
                                : 'No shared folder yet.',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                          itemCount: _tunnel.sharedFiles.length,
                          itemBuilder: (context, index) {
                            final item = _tunnel.sharedFiles[index];
                            return ListTile(
                              leading: Icon(
                                item.kind == 'audio'
                                    ? Icons.music_note_rounded
                                    : item.kind == 'image'
                                    ? Icons.image_outlined
                                    : item.kind == 'video'
                                    ? Icons.movie_outlined
                                    : Icons.insert_drive_file_outlined,
                              ),
                              title: Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(CgMediaStore.fileSize(item.size)),
                              trailing: const Icon(Icons.download_rounded),
                              onTap: () async {
                                if (_isOwner) {
                                  final own = await CgSharedLibraryStore.find(
                                    _tunnel.id,
                                    item.id,
                                  );
                                  if (own != null) {
                                    await _sendFilePath(
                                      own.path,
                                      displayName: item.name,
                                    );
                                  }
                                } else {
                                  await _session?.sendControl(<String, dynamic>{
                                    'operationId': CgIds.random(24),
                                    'action': 'share_request',
                                    'target': _tunnel.ownerId,
                                    'requester': widget.profile.id,
                                    'fileId': item.id,
                                  });
                                }
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connect());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _composerFocus.unfocus();
      _scrollToBottom(animate: false);
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _scrollToBottom(animate: false);
      });
    });
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

  Map<String, dynamic> _replyMeta() {
    final reply = _replyingTo;
    if (reply == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'replyToId': reply.id,
      'replyAuthor': reply.authorName,
      'replyText': reply.text,
      'replyAttachmentName': reply.attachment?.name,
    };
  }

  void _replyTo(CgMessage message) {
    if (message.deleted) return;
    setState(() => _replyingTo = message);
    _composerFocus.requestFocus();
  }

  Future<void> _forward(CgMessage message) async {
    if (message.deleted) return;
    await widget.onForward?.call(message);
  }

  Future<void> _connect() async {
    try {
      final session = await InternetRelay.open(
        tunnelId: _tunnel.id,
        secret: _tunnel.secret,
        profileId: widget.profile.id,
        nickname: widget.profile.nickname,
        history: _tunnel.historyJson(),
      );
      if (!mounted) return;
      await _subscription?.cancel();
      _session = session;
      _subscription = session.events.listen(_onInternetEvent);
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': widget.profile.nickname,
          if (widget.profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': widget.profile.avatarBase64,
        }),
      );
      setState(() {
        _networkState = session.connected ? 'connected' : 'connecting';
        _onlinePeers = (session.onlinePeers - 1).clamp(0, 999).toInt();
      });
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
          unawaited(_mergeMessages([raw]));
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
        unawaited(_mergeMessages(messages));
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
          if (_tunnel.permissions.canSeeHistory) {
            unawaited(_session?.sendHistory());
          }
          if (_isOwner) unawaited(_sendTunnelSnapshot());
        }
        break;
      case 'presence':
        setState(() {
          final total =
              int.tryParse(event.data['peers']?.toString() ?? '') ?? 1;
          _onlinePeers = (total - 1).clamp(0, 999).toInt();
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

  void _rememberContact(String id, String name, {String? avatarBase64}) {
    if (id.isEmpty || id == widget.profile.id) return;
    widget.onContactSeen?.call(
      CgContact(
        id: id,
        nickname: name.trim().isEmpty ? 'user' : name,
        lastSeenAt: DateTime.now(),
        tunnelIds: [_tunnel.id],
        avatarBase64: avatarBase64,
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

  Future<void> _mergeMessages(List<Map<String, dynamic>> raw) async {
    final shouldFollowBottom = _isNearBottom;
    final messages = <CgMessage>[..._tunnel.messages];
    var changed = false;
    for (final item in raw) {
      var incoming = await CgMediaStore.cacheIncomingMessage(
        CgMessage.fromJson(item),
      );
      if (incoming.id.isEmpty) continue;
      final index = messages.indexWhere((message) => message.id == incoming.id);
      final existing = index < 0 ? null : messages[index];
      incoming = CgMediaStore.preserveLocalPurge(existing, incoming);
      if (index < 0) {
        messages.add(incoming);
        changed = true;
        continue;
      }
      if (!messages[index].sameVisibleContent(incoming)) {
        messages[index] = incoming;
        changed = true;
      }
    }
    if (!changed) return;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    if (shouldFollowBottom) _scrollToBottom();
  }

  Future<void> _handleControl(Map<String, dynamic> data) async {
    final action = data['action']?.toString() ?? '';
    final sender = data['relaySender']?.toString() ?? '';
    switch (action) {
      case 'profile_card':
        _rememberContact(
          sender,
          data['nickname']?.toString() ??
              data['relaySenderName']?.toString() ??
              'user',
          avatarBase64: data['avatarBase64']?.toString(),
        );
        break;
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
      case 'attachment_request':
        await _handleAttachmentRequest(data, sender);
        break;
      case 'attachment_response':
        await _handleAttachmentResponse(data);
        break;
      case 'share_request':
        await _handleShareRequest(data, sender);
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
            permissions: data['permissions'] is Map
                ? CgPermissions.fromJson(
                    Map<String, dynamic>.from(data['permissions'] as Map),
                  )
                : _tunnel.permissions,
            sharedFiles: ((data['sharedFiles'] as List?) ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (item) => CgSharedFileInfo.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(),
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
    _session?.replaceHistory(_tunnel.historyJson());
  }

  Future<void> _sendText() async {
    if (!_canWrite) return;
    final value = _text.text.trim();
    if (value.isEmpty) return;
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: value,
      sentAt: DateTime.now(),
      meta: _replyMeta(),
    );
    _text.clear();
    setState(() => _replyingTo = null);
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
              const Divider(height: 28),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(widget.ru ? 'Ответить' : 'Reply'),
                onTap: () => Navigator.pop(context, '__reply__'),
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: Text(widget.ru ? 'Переслать' : 'Forward'),
                onTap: () => Navigator.pop(context, '__forward__'),
              ),
              if (message.text.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(widget.ru ? 'Копировать текст' : 'Copy text'),
                  onTap: () => Navigator.pop(context, '__copy__'),
                ),
              if (message.authorId == widget.profile.id) ...[
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
    } else if (selected == '__reply__') {
      _replyTo(message);
    } else if (selected == '__forward__') {
      await _forward(message);
    } else if (selected == '__copy__') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.ru ? 'Текст скопирован' : 'Text copied'),
          ),
        );
      }
    } else {
      await _toggleReaction(message, selected);
    }
  }

  Future<void> _pickAttachment(
    FileType type, {
    List<String>? allowedExtensions,
  }) async {
    if (!_canSendMedia) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _sendingFile = true);
    try {
      for (final file in result.files) {
        if (file.path != null) {
          await _sendFilePath(file.path!, displayName: file.name);
        } else if (file.bytes != null) {
          await _sendBytes(file.name, file.bytes!);
        }
      }
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
      meta: _replyMeta(),
    );
    setState(() => _replyingTo = null);
    final localMessage = message.copyWith(
      attachment: attachment.copyWith(clearData: true),
    );
    _appendLocal(localMessage);
    await _session?.sendMessage(message.toJson(includeLocalPaths: false));
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

  bool get _isNearBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 120;
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

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (!animate) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  String get _inviteUrl =>
      '$_landingBase?v=35&invite=${Uri.encodeQueryComponent(_tunnel.inviteToken)}';

  String get _deepInvite =>
      'chernogram://join/${Uri.encodeComponent(_tunnel.inviteToken)}';

  Future<void> _showChatProfile() async {
    final members = _session?.members ?? const <Map<String, dynamic>>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            children: [
              _TunnelAvatar(tunnel: _tunnel, size: 86),
              const SizedBox(height: 12),
              Text(
                widget.privacyLens ? '••••••••' : _tunnel.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _tunnel.isPrivate
                    ? (widget.ru ? 'Приватный чат' : 'Private chat')
                    : (widget.ru ? 'Публичный чат' : 'Public chat'),
              ),
              const SizedBox(height: 12),
              SelectableText(
                'ID ${_tunnel.id}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .50),
                ),
              ),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.ru ? 'Участники' : 'Members',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 6),
              if (members.isEmpty)
                ListTile(
                  leading: const Icon(Icons.hourglass_empty_rounded),
                  title: Text(
                    widget.ru
                        ? 'Участники появятся после подключения'
                        : 'Members appear after connecting',
                  ),
                )
              else
                for (final member in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        (member['name']?.toString().trim().isNotEmpty == true
                                ? member['name'].toString().trim()[0]
                                : '?')
                            .toUpperCase(),
                      ),
                    ),
                    title: Text(member['name']?.toString() ?? 'user'),
                    subtitle: Text(member['id']?.toString() ?? ''),
                    trailing: member['self'] == true
                        ? Text(widget.ru ? 'вы' : 'you')
                        : null,
                  ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_canInvite)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(_showInvite());
                        },
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          widget.ru ? 'Добавить людей' : 'Add people',
                        ),
                      ),
                    ),
                  if (_canInvite) const SizedBox(width: 9),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(_showSettings());
                      },
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(widget.ru ? 'Разрешения' : 'Permissions'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                        : 'Open the Cernogram chat: $_deepInvite\n\nIf the app did not open: $_inviteUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(widget.ru ? 'Отправить ссылку' : 'Share invite'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Установить Чернограм для Android:\n$_androidInstallUrl'
                        : 'Install Cernogram for Android:\n$_androidInstallUrl',
                  ),
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: Text(
                    widget.ru
                        ? 'Поделиться ссылкой на установку'
                        : 'Share installation link',
                  ),
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
      'permissions': _tunnel.permissions.toJson(),
      'sharedFiles': _tunnel.sharedFiles.map((item) => item.toJson()).toList(),
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
      'permissions': updated.permissions.toJson(),
      'sharedFiles': updated.sharedFiles.map((item) => item.toJson()).toList(),
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

  Future<void> _leaveAndDeleteChat() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever_rounded,
          color: ChernogramColors.danger,
          size: 40,
        ),
        title: Text(
          widget.ru ? 'Выйти и удалить чат?' : 'Leave and delete chat?',
        ),
        content: Text(
          widget.ru
              ? 'История и все локальные файлы этого чата будут полностью удалены с телефона. У других участников останутся их копии.'
              : 'The history and all local files for this chat are permanently removed from this phone. Other participants keep their copies.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ChernogramColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Удалить полностью' : 'Delete permanently'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _session?.sendControl(<String, dynamic>{
      'operationId': CgIds.random(24),
      'action': 'member_left',
      'memberId': widget.profile.id,
      'memberName': widget.profile.nickname,
    });
    await widget.onDelete?.call(_tunnel);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showSettings() async {
    final name = TextEditingController(text: _tunnel.name);
    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    var permissions = _tunnel.permissions;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .92,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.ru ? 'Настройки чата' : 'Chat settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    readOnly: !_isOwner,
                    decoration: InputDecoration(
                      labelText: widget.ru ? 'Название чата' : 'Chat name',
                      prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fingerprint_rounded),
                    title: Text(widget.ru ? 'ID чата' : 'Chat ID'),
                    subtitle: SelectableText(_tunnel.id),
                    trailing: Text('v${_tunnel.revision}'),
                  ),
                  if (_isOwner) ...[
                    const Divider(height: 26),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isPrivate,
                      onChanged: (value) =>
                          setSheetState(() => isPrivate = value),
                      secondary: Icon(
                        isPrivate ? Icons.lock_outline_rounded : Icons.public,
                      ),
                      title: Text(
                        isPrivate
                            ? (widget.ru ? 'Приватный чат' : 'Private chat')
                            : (widget.ru ? 'Открытый чат' : 'Open chat'),
                      ),
                    ),
                    Text(
                      widget.ru ? 'Права участников' : 'Member permissions',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: permissions.canWriteMessages,
                      secondary: const Icon(Icons.chat_outlined),
                      title: Text(
                        widget.ru ? 'Писать сообщения' : 'Send messages',
                      ),
                      onChanged: (value) => setSheetState(
                        () => permissions = permissions.copyWith(
                          canWriteMessages: value,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: permissions.canSendMedia,
                      secondary: const Icon(Icons.attach_file_rounded),
                      title: Text(
                        widget.ru ? 'Отправлять файлы' : 'Send files',
                      ),
                      onChanged: (value) => setSheetState(
                        () => permissions = permissions.copyWith(
                          canSendMedia: value,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: permissions.canDownload,
                      secondary: const Icon(Icons.download_outlined),
                      title: Text(
                        widget.ru ? 'Скачивать файлы' : 'Download files',
                      ),
                      onChanged: (value) => setSheetState(
                        () => permissions = permissions.copyWith(
                          canDownload: value,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: permissions.canInvite,
                      secondary: const Icon(Icons.person_add_alt_1_outlined),
                      title: Text(
                        widget.ru ? 'Приглашать людей' : 'Invite people',
                      ),
                      onChanged: (value) => setSheetState(
                        () => permissions = permissions.copyWith(
                          canInvite: value,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: permissions.canSeeHistory,
                      secondary: const Icon(Icons.history_rounded),
                      title: Text(widget.ru ? 'Видеть историю' : 'See history'),
                      onChanged: (value) => setSheetState(
                        () => permissions = permissions.copyWith(
                          canSeeHistory: value,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: permissions.canCall,
                      secondary: const Icon(Icons.call_outlined),
                      title: Text(widget.ru ? 'Звонить' : 'Make calls'),
                      onChanged: (value) => setSheetState(
                        () =>
                            permissions = permissions.copyWith(canCall: value),
                      ),
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
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'save'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(widget.ru ? 'Сохранить' : 'Save'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: ChernogramColors.danger,
                      ),
                      label: Text(
                        widget.ru
                            ? 'Выйти и удалить чат с устройства'
                            : 'Leave and delete chat from device',
                        style: const TextStyle(color: ChernogramColors.danger),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (action == 'save' && _isOwner) {
      final updated = _tunnel.copyWith(
        name: name.text.trim(),
        isPrivate: isPrivate,
        secret: revoke ? CgIds.random(42) : _tunnel.secret,
        permissions: permissions,
        revision: _tunnel.revision + 1,
      );
      name.dispose();
      await _applyOwnerUpdate(updated);
      return;
    }
    name.dispose();
    if (action == 'delete' && mounted) await _leaveAndDeleteChat();
  }

  Future<void> _startCall(bool video) async {
    if (!_canCall) return;
    unawaited(_session?.connect());
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
          peerId: _preferredPeerId,
          peerName: _preferredPeerName,
          peerAvatarBase64: _tunnel.avatarBase64,
          myAvatarBase64: widget.profile.avatarBase64,
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
    if (!_canCall || _session == null) {
      _showNotConnected();
      return;
    }
    unawaited(_session!.connect());
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
          myAvatarBase64: widget.profile.avatarBase64,
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
    final target = signal['target']?.toString() ?? '';
    if (target.isNotEmpty && target != widget.profile.id) return;
    final signalAt = DateTime.tryParse(
      signal['receivedAt']?.toString() ?? signal['sentAt']?.toString() ?? '',
    );
    if (signalAt != null &&
        DateTime.now().toUtc().difference(signalAt.toUtc()).inSeconds > 25) {
      return;
    }
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
        unawaited(
          _showIncomingCall(callId, from, fromName, callerAvatar, video),
        );
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
        unawaited(
          _showIncomingGroupCall(
            callId,
            fromName,
            signal['avatarBase64']?.toString(),
            video,
          ),
        );
      }
    });
  }

  Future<void> _showIncomingCall(
    String callId,
    String fromId,
    String fromName,
    String? callerAvatar,
    bool video,
  ) async {
    await ChernogramSound.startIncomingCall(video: video);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: CgCallAvatar(
          avatarBase64: callerAvatar,
          name: fromName,
          size: 78,
          fallbackIcon: video ? Icons.videocam_rounded : Icons.call_rounded,
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
              shape: const CircleBorder(),
              fixedSize: const Size.square(54),
            ),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.call_end),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.success,
              shape: const CircleBorder(),
              fixedSize: const Size.square(54),
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call),
          ),
        ],
      ),
    );
    await ChernogramSound.stopIncomingCall();
    if (accepted != true) {
      unawaited(
        _session?.sendSignal({
          'action': 'call_decline',
          'callId': callId,
          'from': widget.profile.id,
          'target': fromId,
        }),
      );
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
          peerAvatarBase64: callerAvatar,
          myAvatarBase64: widget.profile.avatarBase64,
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
    String? callerAvatar,
    bool video,
  ) async {
    await ChernogramSound.startIncomingCall(video: video);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: CgCallAvatar(
          avatarBase64: callerAvatar,
          name: fromName,
          size: 78,
          fallbackIcon: video ? Icons.groups_2_rounded : Icons.group_rounded,
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
          myAvatarBase64: widget.profile.avatarBase64,
        ),
      ),
    );
  }

  String get _statusText {
    if (_networkState == 'connected') {
      if (_onlinePeers > 0) {
        return widget.ru ? 'В сети • $_onlinePeers' : 'Online • $_onlinePeers';
      }
      return widget.ru ? 'Ожидаем собеседника' : 'Waiting for peer';
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
    _composerFocus.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canInvite = _canInvite;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: Navigator.of(context).canPop() ? 106 : 58,
        leading: Row(
          children: [
            if (Navigator.of(context).canPop())
              IconButton(
                tooltip: widget.ru ? 'Назад' : 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: _showChatProfile,
                child: _TunnelAvatar(tunnel: _tunnel, size: 42),
              ),
            ),
          ],
        ),
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
            onPressed: _canCall ? () => _startCall(false) : null,
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
                case 'shared':
                  _showSharedLibrary();
                  break;
                case 'profile':
                  _showChatProfile();
                  break;
                case 'appearance':
                  CgChatAppearanceController.instance.showSettings(
                    context,
                    ru: widget.ru,
                  );
                  break;
                case 'settings':
                  _showSettings();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(widget.ru ? 'Профиль чата' : 'Chat profile'),
                ),
              ),
              PopupMenuItem(
                value: 'shared',
                child: ListTile(
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: Text(widget.ru ? 'Общие файлы' : 'Shared files'),
                ),
              ),
              PopupMenuItem(
                value: 'appearance',
                child: ListTile(
                  leading: const Icon(Icons.wallpaper_rounded),
                  title: Text(
                    widget.ru ? 'Фон и паттерн' : 'Background pattern',
                  ),
                ),
              ),
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
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: Text(widget.ru ? 'Настройки чата' : 'Chat settings'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DropTarget(
        enable: Platform.isWindows || Platform.isLinux || Platform.isMacOS,
        onDragDone: _handleDropped,
        child: Column(
          children: [
            Expanded(
              child: _tunnel.messages.isEmpty
                  ? _EmptyChat(
                      ru: widget.ru,
                      onInvite: canInvite ? _showInvite : null,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      physics: const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      dragStartBehavior: DragStartBehavior.down,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                      itemCount: _tunnel.messages.length,
                      itemBuilder: (context, index) {
                        final message = _tunnel.messages[index];
                        final mine =
                            message.authorId == widget.profile.id ||
                            (message.authorId.isEmpty &&
                                message.authorName == widget.profile.nickname);
                        return Dismissible(
                          key: ValueKey('swipe-${message.id}'),
                          direction: message.deleted
                              ? DismissDirection.none
                              : DismissDirection.horizontal,
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              _replyTo(message);
                            } else {
                              await _forward(message);
                            }
                            return false;
                          },
                          background: _SwipeActionBackground(
                            alignment: Alignment.centerLeft,
                            icon: Icons.reply_rounded,
                            label: widget.ru ? 'Ответить' : 'Reply',
                          ),
                          secondaryBackground: _SwipeActionBackground(
                            alignment: Alignment.centerRight,
                            icon: Icons.forward_rounded,
                            label: widget.ru ? 'Переслать' : 'Forward',
                          ),
                          child: Row(
                            mainAxisAlignment: mine
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!mine) ...[
                                _MessageAuthorAvatar(
                                  message: message,
                                  mine: false,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: _MessageBubble(
                                  message: message,
                                  mine: mine,
                                  privacyLens: widget.privacyLens,
                                  ru: widget.ru,
                                  onLongPress: () =>
                                      _showMessageActions(message),
                                  onEnsureAttachment: _ensureAttachment,
                                  onPlayAudio: _playAttachment,
                                  onDelete: _deleteMessage,
                                  canDownload: _canDownload,
                                ),
                              ),
                              if (mine) ...[
                                const SizedBox(width: 6),
                                _MessageAuthorAvatar(
                                  message: message,
                                  mine: true,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyingTo != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: .92,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.reply_rounded, color: scheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _replyingTo!.authorName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    _replyingTo!.text.isNotEmpty
                                        ? _replyingTo!.text
                                        : (_replyingTo!.attachment?.name ?? ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _replyingTo = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                    GlassPanel(
                      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                      borderRadius: BorderRadius.circular(22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: widget.ru ? 'Добавить' : 'Add',
                            onPressed: _sendingFile
                                ? null
                                : _showAttachmentMenu,
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _composerFocus,
                              autofocus: false,
                              onTapOutside: (_) => _composerFocus.unfocus(),
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: Platform.isWindows
                                  ? TextInputAction.send
                                  : TextInputAction.newline,
                              enabled: _canWrite,
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
                          const SizedBox(width: 10),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _hasText
                                ? IconButton.filled(
                                    key: const ValueKey('send'),
                                    onPressed: _sendText,
                                    icon: const Icon(
                                      Icons.arrow_upward_rounded,
                                    ),
                                  )
                                : CgVoiceRecordButton(
                                    key: const ValueKey('voice'),
                                    ru: widget.ru,
                                    enabled: _canSendMedia,
                                    onRecorded: _sendVoice,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;

  const _SwipeActionBackground({
    required this.alignment,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
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

class _MessageAuthorAvatar extends StatelessWidget {
  final CgMessage message;
  final bool mine;

  const _MessageAuthorAvatar({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final raw = message.meta['avatarBase64']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 15,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {}
    }
    final name = message.authorName.trim();
    return CircleAvatar(
      radius: 15,
      backgroundColor: mine
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: mine
              ? Colors.white
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
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

class _LinkifiedMessageText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;

  const _LinkifiedMessageText({
    required this.text,
    required this.style,
    required this.linkColor,
  });

  @override
  State<_LinkifiedMessageText> createState() => _LinkifiedMessageTextState();
}

class _LinkifiedMessageTextState extends State<_LinkifiedMessageText> {
  static final RegExp _urlPattern = RegExp(
    r'((?:https?|chernogram)://[^\s]+|www\.[^\s]+)',
    caseSensitive: false,
  );
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _spans() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      var visible = match.group(0)!;
      var trailing = '';
      while (visible.isNotEmpty &&
          '.,!?;:)]}'.contains(visible[visible.length - 1])) {
        trailing = visible[visible.length - 1] + trailing;
        visible = visible.substring(0, visible.length - 1);
      }
      final normalized = visible.toLowerCase().startsWith('www.')
          ? 'https://$visible'
          : visible;
      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          final uri = Uri.tryParse(normalized);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: visible,
          style: widget.style.copyWith(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
            fontWeight: FontWeight.w700,
          ),
          recognizer: recognizer,
        ),
      );
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Text.rich(TextSpan(style: widget.style, children: _spans())),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final CgMessage message;
  final bool mine;
  final bool privacyLens;
  final bool ru;
  final VoidCallback onLongPress;
  final Future<File?> Function(CgMessage message) onEnsureAttachment;
  final Future<void> Function(CgAttachment attachment, File file) onPlayAudio;
  final Future<void> Function(CgMessage message) onDelete;
  final bool canDownload;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.privacyLens,
    required this.ru,
    required this.onLongPress,
    required this.onEnsureAttachment,
    required this.onPlayAudio,
    required this.onDelete,
    required this.canDownload,
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
    if (message.meta['localHidden'] == true) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final attachment = message.attachment;
    final mediaOnly = attachment != null && message.text.isEmpty;
    final bubbleColor = mediaOnly
        ? Colors.transparent
        : mine
        ? scheme.primary.withValues(alpha: .92)
        : scheme.surfaceContainerHighest.withValues(alpha: .74);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 370),
          margin: const EdgeInsets.only(bottom: 7),
          padding: mediaOnly ? EdgeInsets.zero : const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 5),
              bottomRight: Radius.circular(mine ? 5 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.deleted)
                Padding(
                  padding: mediaOnly
                      ? const EdgeInsets.all(8)
                      : EdgeInsets.zero,
                  child: Text(
                    ru ? 'Сообщение удалено' : 'Message deleted',
                    style: TextStyle(
                      color: mediaOnly
                          ? scheme.onSurfaceVariant
                          : mine
                          ? Colors.white60
                          : scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else ...[
                if (message.meta['forwardedFrom'] != null) ...[
                  Text(
                    '${ru ? 'Переслано от' : 'Forwarded from'} ${message.meta['forwardedFrom']}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: mine && !mediaOnly
                          ? Colors.white70
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                if (message.meta['replyToId'] != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${message.meta['replyAuthor'] ?? ''}: ${message.meta['replyText']?.toString().isNotEmpty == true ? message.meta['replyText'] : message.meta['replyAttachmentName'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (attachment != null)
                  CgInlineAttachment(
                    attachment: attachment,
                    hidden: privacyLens,
                    ru: ru,
                    onEnsure: (_) => onEnsureAttachment(message),
                    onPlayAudio: onPlayAudio,
                    onDelete: message.authorId.isEmpty || message.deleted
                        ? null
                        : () => onDelete(message),
                    canDownload: canDownload,
                  ),
                if (message.text.isNotEmpty) ...[
                  if (attachment != null) const SizedBox(height: 6),
                  _LinkifiedMessageText(
                    text: privacyLens ? '••••••••••' : message.text,
                    style: TextStyle(
                      color: mine ? Colors.white : scheme.onSurface,
                      fontSize: 15,
                    ),
                    linkColor: mine ? Colors.white : scheme.primary,
                  ),
                ],
              ],
              if (!message.deleted && message.reactions.isNotEmpty) ...[
                const SizedBox(height: 5),
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
                            color: scheme.surface.withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${entry.key} ${entry.value.length}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              Padding(
                padding: mediaOnly
                    ? const EdgeInsets.only(left: 6, top: 3)
                    : const EdgeInsets.only(top: 4),
                child: Text(
                  '${privacyLens ? '••••' : message.authorName} • ${_formatTime(message.sentAt)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: mediaOnly
                        ? scheme.onSurface.withValues(alpha: .46)
                        : mine
                        ? Colors.white60
                        : scheme.onSurface.withValues(alpha: .42),
                  ),
                ),
              ),
            ],
          ),
        ),
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
      subtitle = mine
          ? (ru ? 'Звонок отменён' : 'Call cancelled')
          : (ru ? 'Пропущенный звонок' : 'Missed call');
    } else {
      subtitle = mine
          ? (ru ? 'Нет ответа' : 'No answer')
          : (ru ? 'Пропущенный звонок' : 'Missed call');
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: successful
                ? scheme.primaryContainer.withValues(alpha: .78)
                : scheme.errorContainer.withValues(alpha: .68),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: successful
                    ? ChernogramColors.success.withValues(alpha: .18)
                    : ChernogramColors.danger.withValues(alpha: .16),
                child: Icon(
                  group
                      ? Icons.groups_2_rounded
                      : video
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  color: successful
                      ? ChernogramColors.success
                      : ChernogramColors.danger,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      privacyLens ? '••••••••' : title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      privacyLens ? '••••••••' : subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .64),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _MessageBubble._formatTime(message.sentAt),
                style: TextStyle(
                  fontSize: 9,
                  color: scheme.onSurface.withValues(alpha: .42),
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
