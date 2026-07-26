import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'brand.dart';
import 'call_service.dart';
import 'core_models.dart';
import 'internet_core.dart';

const String _landingBase =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';

class CgChatScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final CgTunnel tunnel;
  final bool privacyLens;
  final bool autoInvite;
  final ValueChanged<CgTunnel> onChanged;

  const CgChatScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnel,
    required this.privacyLens,
    required this.onChanged,
    this.autoInvite = false,
  });

  @override
  State<CgChatScreen> createState() => _CgChatScreenState();
}

class _CgChatScreenState extends State<CgChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Set<String> _handledCalls = <String>{};

  late CgTunnel _tunnel;
  InternetTunnelSession? _session;
  StreamSubscription<InternetEvent>? _subscription;
  String _networkState = 'connecting';
  String? _networkError;
  int _onlinePeers = 1;
  bool _sendingFile = false;

  @override
  void initState() {
    super.initState();
    _tunnel = widget.tunnel;
    unawaited(_connect());
    if (widget.autoInvite) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showInvite());
      });
    }
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
      _subscription?.cancel();
      _session = session;
      _subscription = session.events.listen(_onInternetEvent);
      setState(() {
        _networkState = session.connected ? 'connected' : 'connecting';
        _onlinePeers = session.onlinePeers;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _networkState = 'error';
        _networkError = error.toString();
      });
    }
  }

  void _onInternetEvent(InternetEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'message':
        if (event.data['message'] is Map) {
          _mergeMessages([
            Map<String, dynamic>.from(event.data['message'] as Map),
          ]);
        }
        break;
      case 'history':
        final messages = ((event.data['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _mergeMessages(messages);
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
          _networkError = event.data['error']?.toString();
        });
        break;
      case 'signal':
        _handleSignal(event.data);
        break;
    }
  }

  void _mergeMessages(List<Map<String, dynamic>> raw) {
    final byId = <String, CgMessage>{
      for (final message in _tunnel.messages) message.id: message,
    };
    var changed = false;
    for (final item in raw) {
      final message = CgMessage.fromJson(item);
      if (message.id.isEmpty || byId.containsKey(message.id)) continue;
      byId[message.id] = message;
      changed = true;
    }
    if (!changed) return;
    final messages = byId.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
    _persist();
    _scrollToBottom();
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
      _tunnel = _tunnel.copyWith(
        messages: [..._tunnel.messages, message],
      );
    });
    _persist();
    _scrollToBottom();
  }

  Future<void> _pickAttachment({required bool imagesOnly}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: imagesOnly ? FileType.image : FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    const maxBytes = 1200 * 1024;
    if (bytes.length > maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Для мгновенной передачи файл должен быть меньше 1,2 МБ. Передачу больших файлов добавим отдельным P2P-каналом.'
                : 'Instant files are limited to 1.2 MB. Large-file P2P transfer is the next transport layer.',
          ),
        ),
      );
      return;
    }
    setState(() => _sendingFile = true);
    final attachment = CgAttachment(
      id: CgIds.random(20),
      name: file.name,
      size: bytes.length,
      kind: _attachmentKind(file.name),
      dataBase64: base64Encode(bytes),
      localPath: file.path,
    );
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
    if (mounted) setState(() => _sendingFile = false);
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
    if (<String>{'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) return 'archive';
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
      '$_landingBase?invite=${Uri.encodeQueryComponent(_tunnel.inviteToken)}';

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
                    ? 'Код работает через интернет — участники могут находиться в разных городах и сетях.'
                    : 'The code works over the internet — participants can be in different cities and networks.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(data: _inviteUrl, size: 220),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Присоединяйся к моему туннелю Чернограма: $_inviteUrl'
                        : 'Join my Chernogram tunnel: $_inviteUrl',
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

  Future<void> _changeAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final encoded = base64Encode(bytes);
    setState(() => _tunnel = _tunnel.copyWith(avatarBase64: encoded));
    _persist();
  }

  Future<void> _showSettings() async {
    final name = TextEditingController(text: _tunnel.name);
    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    final result = await showModalBottomSheet<({String name, bool isPrivate, bool revoke})>(
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
                  labelText: widget.ru ? 'Название — необязательно' : 'Name — optional',
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
                onChanged: (value) => setSheetState(() => isPrivate = value),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: revoke,
                onChanged: (value) => setSheetState(() => revoke = value ?? false),
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
                  onPressed: () => Navigator.pop(
                    context,
                    (name: name.text.trim(), isPrivate: isPrivate, revoke: revoke),
                  ),
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
    final oldSecret = _tunnel.secret;
    setState(() {
      _tunnel = _tunnel.copyWith(
        name: result.name,
        isPrivate: result.isPrivate,
        secret: result.revoke ? CgIds.random(40) : oldSecret,
      );
    });
    _persist();
    if (result.revoke) {
      await InternetRelay.close(_tunnel.id);
      await _connect();
    }
  }

  Future<void> _startCall(bool video) async {
    final callId = CgIds.random(22);
    await Navigator.push<void>(
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
  }

  void _handleSignal(Map<String, dynamic> signal) {
    if (signal['action']?.toString() != 'call_invite') return;
    final callId = signal['callId']?.toString() ?? '';
    final from = signal['from']?.toString() ?? signal['relaySender']?.toString() ?? '';
    if (callId.isEmpty || from.isEmpty || from == widget.profile.id) return;
    if (!_handledCalls.add(callId)) return;
    final video = signal['video'] == true;
    final fromName = signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        (widget.ru ? 'Собеседник' : 'Peer');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showIncomingCall(callId, from, fromName, video));
    });
  }

  Future<void> _showIncomingCall(
    String callId,
    String fromId,
    String fromName,
    bool video,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(video ? Icons.videocam_rounded : Icons.call_rounded, size: 38),
        title: Text(video
            ? (widget.ru ? 'Видеозвонок' : 'Video call')
            : (widget.ru ? 'Аудиозвонок' : 'Audio call')),
        content: Text(
          widget.ru ? '$fromName звонит вам' : '$fromName is calling you',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: ChernogramColors.danger),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.call_end),
          ),
          const SizedBox(width: 20),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: ChernogramColors.success),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call),
          ),
        ],
      ),
    );
    if (accepted != true) {
      await _session?.sendSignal({
        'action': 'call_decline',
        'callId': callId,
        'from': widget.profile.id,
        'target': fromId,
      });
      return;
    }
    await _session?.sendSignal({
      'action': 'call_accept',
      'callId': callId,
      'from': widget.profile.id,
      'target': fromId,
    });
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChernogramCallScreen(
          tunnelName: _tunnel.displayName,
          tunnelId: _tunnel.id,
          secret: _tunnel.secret,
          profileId: widget.profile.id,
          nickname: widget.profile.nickname,
          peerName: fromName,
          callId: callId,
          isCaller: false,
          video: video,
          ru: widget.ru,
        ),
      ),
    );
  }

  String get _statusText {
    if (_networkState == 'connected') {
      return widget.ru
          ? 'Интернет • онлайн $_onlinePeers'
          : 'Internet • $_onlinePeers online';
    }
    if (_networkState == 'queued') {
      return widget.ru ? 'Сообщение в очереди' : 'Message queued';
    }
    if (_networkState == 'error' || _networkState == 'disconnected') {
      return widget.ru ? 'Переподключение…' : 'Reconnecting…';
    }
    return widget.ru ? 'Подключение…' : 'Connecting…';
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 58,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _TunnelAvatar(tunnel: _tunnel, size: 42),
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
            onPressed: () => _startCall(false),
          ),
          PopupMenuButton<String>(
            tooltip: widget.ru ? 'Действия' : 'Actions',
            onSelected: (value) {
              switch (value) {
                case 'video':
                  _startCall(true);
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
                value: 'invite',
                child: ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(widget.ru ? 'Пригласить' : 'Invite'),
                ),
              ),
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
                  title: Text(widget.ru ? 'Настройки' : 'Settings'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_networkState != 'connected')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Material(
                color: scheme.errorContainer.withValues(alpha: .52),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                          _networkError ?? _statusText,
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
                    onInvite: _showInvite,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                    itemCount: _tunnel.messages.length,
                    itemBuilder: (context, index) {
                      final message = _tunnel.messages[index];
                      final mine = message.authorId == widget.profile.id ||
                          (message.authorId.isEmpty &&
                              message.authorName == widget.profile.nickname);
                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        privacyLens: widget.privacyLens,
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
                    PopupMenuButton<String>(
                      tooltip: widget.ru ? 'Вложение' : 'Attachment',
                      icon: _sendingFile
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                      onSelected: (value) {
                        if (value == 'photo') _pickAttachment(imagesOnly: true);
                        if (value == 'file') _pickAttachment(imagesOnly: false);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'photo',
                          child: ListTile(
                            leading: const Icon(Icons.photo_outlined),
                            title: Text(widget.ru ? 'Фото' : 'Photo'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'file',
                          child: ListTile(
                            leading: const Icon(Icons.attach_file),
                            title: Text(widget.ru ? 'Файл до 1,2 МБ' : 'File up to 1.2 MB'),
                          ),
                        ),
                      ],
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
                    IconButton.filled(
                      onPressed: _sendText,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
  final VoidCallback onInvite;

  const _EmptyChat({required this.ru, required this.onInvite});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChernogramLogo(size: 82, withPlate: true),
              const SizedBox(height: 18),
              Text(
                ru ? 'Туннель готов' : 'Tunnel is ready',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                ru
                    ? 'Отправьте ссылку человеку — после подключения можно писать и звонить из любой сети.'
                    : 'Share the invite. Once connected, you can message and call from any network.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(ru ? 'Пригласить человека' : 'Invite someone'),
              ),
            ],
          ),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final CgMessage message;
  final bool mine;
  final bool privacyLens;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.privacyLens,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attachment = message.attachment;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 350),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primary.withValues(alpha: .88)
              : scheme.surfaceContainerHighest.withValues(alpha: .88),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(19),
            topRight: const Radius.circular(19),
            bottomLeft: Radius.circular(mine ? 19 : 5),
            bottomRight: Radius.circular(mine ? 5 : 19),
          ),
          border: Border.all(color: scheme.onSurface.withValues(alpha: .06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null)
              _AttachmentPreview(
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
                ),
              ),
            ],
            const SizedBox(height: 5),
            Text(
              '${privacyLens ? '••••' : message.authorName} • ${_formatTime(message.sentAt)}',
              style: TextStyle(
                fontSize: 9,
                color: mine
                    ? Colors.white60
                    : scheme.onSurface.withValues(alpha: .42),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
