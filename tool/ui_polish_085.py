from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:240]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_block(path: str, start: str, end: str, new: str, anchor: str = '') -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    base = text.find(anchor) if anchor else 0
    if base < 0:
        raise SystemExit(f'Anchor not found in {path}: {anchor!r}')
    start_at = text.find(start, base)
    if start_at < 0:
        raise SystemExit(f'Start not found in {path}: {start!r}')
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f'End not found in {path}: {end!r}')
    file.write_text(text[:start_at] + new + text[end_at:], encoding='utf-8')


# 0.85 remains a UI/lifecycle release. Transport routing stays exactly as in 0.83.
replace_once('pubspec.yaml', 'version: 0.84.0+84', 'version: 0.85.0+85')
replace_once(
    'pubspec.yaml',
    '  flutter_background_service: ^5.1.0\n',
    '  flutter_background_service: ^5.1.0\n'
    '  tray_manager: ^0.5.3\n'
    '  window_manager: ^0.5.2\n',
)
replace_once(
    'pubspec.yaml',
    'flutter:\n  uses-material-design: true',
    'flutter:\n'
    '  uses-material-design: true\n'
    '  assets:\n'
    '    - assets/audio/incoming_call.mp3\n'
    '    - assets/icons/chernogram_tray.ico',
)

# ---------------------------------------------------------------------------
# App lifecycle: Android foreground receiver + Windows close-to-tray.
# ---------------------------------------------------------------------------
replace_once(
    'lib/main.dart',
    "import 'dart:async';\n",
    "import 'dart:async';\nimport 'dart:io';\n",
)
replace_once(
    'lib/main.dart',
    "import 'app_navigation.dart';\n",
    "import 'app_navigation.dart';\n"
    "import 'background_runtime.dart';\n"
    "import 'desktop_runtime.dart';\n",
)
replace_once(
    'lib/main.dart',
    '''  FirebaseMessaging.onBackgroundMessage(chernogramFirebaseBackgroundHandler);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ChernogramApp());
  unawaited(CgPushService.initialize());
''',
    '''  FirebaseMessaging.onBackgroundMessage(chernogramFirebaseBackgroundHandler);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (Platform.isWindows) await CgDesktopRuntime.initialize();
  if (Platform.isAndroid) await CgBackgroundRuntime.initialize();
  runApp(const ChernogramApp());
  CgBackgroundRuntime.setAppVisible(true);
  unawaited(CgPushService.initialize());
''',
)
replace_once(
    'lib/main.dart',
    'class _ChernogramAppState extends State<ChernogramApp> {\n',
    'class _ChernogramAppState extends State<ChernogramApp> '
    'with WidgetsBindingObserver {\n',
)
replace_once(
    'lib/main.dart',
    '''  void initState() {
    super.initState();
    _applySystemUi(true);
    unawaited(_loadSettings());
  }
''',
    '''  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemUi(true);
    unawaited(_loadSettings());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    CgBackgroundRuntime.setAppVisible(visible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
''',
)

# ---------------------------------------------------------------------------
# Main screen: no bottom navigation. Profile avatar lives where the logo was.
# Wide Windows keeps the desktop sidebar; narrow Windows/Android use avatar.
# ---------------------------------------------------------------------------
replace_once(
    'lib/light/light_chat_app.dart',
    '''      _ChatsPage(
        profile: _profile!,
        chats: _chats,
        contacts: _knownContacts,
        onOpen: _openChat,
        onCreate: _newChat,
        onScan: _scanInviteQr,
        onDelete: _deleteChat,
      ),
''',
    '''      _ChatsPage(
        profile: _profile!,
        chats: _chats,
        contacts: _knownContacts,
        onOpen: _openChat,
        onCreate: _newChat,
        onScan: _scanInviteQr,
        onDelete: _deleteChat,
        onProfile: () => setState(() => _tab = 1),
      ),
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''        onTheme: widget.onToggleTheme,
        onShareInstall: () => showChernogramInstallShare(context, ru: true),
        onUpdate: widget.onCheckUpdates,
      ),
''',
    '''        onTheme: widget.onToggleTheme,
        onShareInstall: () => showChernogramInstallShare(context, ru: true),
        onUpdate: widget.onCheckUpdates,
        onBack: () => setState(() => _tab = 0),
      ),
''',
)

# Remove the narrow/mobile bottom bar completely.
replace_block(
    'lib/light/light_chat_app.dart',
    '    return Scaffold(\n      extendBody: true,\n      backgroundColor: Colors.transparent,\n      body: IndexedStack(index: _tab, children: pages),\n      bottomNavigationBar:',
    '  @override\n  void dispose() {',
    '''    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(index: _tab, children: pages),
    );
  }

''',
    anchor='    final desktop =',
)

# Page header accepts a custom leading widget.
replace_once(
    'lib/light/light_chat_app.dart',
    '''class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });
''',
    '''class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;

  const _PageHeader({
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
  });
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''      children: [
        const ChernogramLogo(size: 46),
        const SizedBox(width: 12),
''',
    '''      children: [
        leading ?? const ChernogramLogo(size: 46),
        const SizedBox(width: 12),
''',
)

replace_once(
    'lib/light/light_chat_app.dart',
    '''  final Future<void> Function(CgTunnel chat) onDelete;

  const _ChatsPage({
''',
    '''  final Future<void> Function(CgTunnel chat) onDelete;
  final VoidCallback onProfile;

  const _ChatsPage({
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''    required this.onScan,
    required this.onDelete,
  });
''',
    '''    required this.onScan,
    required this.onDelete,
    required this.onProfile,
  });
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''          _PageHeader(
            title: 'Чернограм',
            subtitle: 'Комнаты, звонки и файлы через интернет',
            trailing: Row(
''',
    '''          _PageHeader(
            title: 'Чернограм',
            subtitle: 'Комнаты, звонки и файлы через интернет',
            leading: Tooltip(
              message: 'Профиль',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onProfile,
                child: ChernogramAvatar(
                  size: 48,
                  seed: widget.profile.id,
                  avatarBase64: widget.profile.avatarBase64,
                ),
              ),
            ),
            trailing: Row(
''',
)

# Profile gets a clear way back now that the bottom bar is gone.
replace_once(
    'lib/light/light_chat_app.dart',
    '''  final VoidCallback onUpdate;

  const _ProfilePage({
''',
    '''  final VoidCallback onUpdate;
  final VoidCallback onBack;

  const _ProfilePage({
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''    required this.onShareInstall,
    required this.onUpdate,
  });
''',
    '''    required this.onShareInstall,
    required this.onUpdate,
    required this.onBack,
  });
''',
)
replace_once(
    'lib/light/light_chat_app.dart',
    '''          const _PageHeader(
            title: 'Профиль',
            subtitle: 'Файлы, устройство, приватность и обновления',
          ),
''',
    '''          _PageHeader(
            title: 'Профиль',
            subtitle: 'Файлы, устройство, приватность и обновления',
            leading: IconButton.filledTonal(
              tooltip: 'Назад к комнатам',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
''',
)

# ---------------------------------------------------------------------------
# Chat avatar setting: image is edited together with the room name/privacy.
# ---------------------------------------------------------------------------
replace_once(
    'lib/chat_screen.dart',
    '''    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    final result =
        await showModalBottomSheet<
          ({String name, bool isPrivate, bool revoke})
        >(
''',
    '''    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    var avatarBase64 = _tunnel.avatarBase64;
    final result =
        await showModalBottomSheet<
          ({String name, bool isPrivate, bool revoke, String? avatarBase64})
        >(
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
''',
    '''                  const SizedBox(height: 14),
                  Center(
                    child: Column(
                      children: [
                        ChernogramAvatar(
                          size: 92,
                          seed: _tunnel.id,
                          avatarBase64: avatarBase64,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (picked == null || picked.files.isEmpty) return;
                            final bytes = picked.files.first.bytes;
                            if (bytes == null) return;
                            if (bytes.length > 2 * 1024 * 1024) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Фото комнаты — до 2 МБ.'),
                                  ),
                                );
                              }
                              return;
                            }
                            setSheetState(() => avatarBase64 = base64Encode(bytes));
                          },
                          icon: const Icon(Icons.add_a_photo_rounded),
                          label: Text(
                            avatarBase64 == null
                                ? 'Поставить фото комнаты'
                                : 'Изменить фото комнаты',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: name,
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''                        revoke: revoke,
                      )),
''',
    '''                        revoke: revoke,
                        avatarBase64: avatarBase64,
                      )),
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''      secret: result.revoke ? CgIds.random(42) : _tunnel.secret,
      revision: _tunnel.revision + 1,
''',
    '''      secret: result.revoke ? CgIds.random(42) : _tunnel.secret,
      avatarBase64: result.avatarBase64,
      revision: _tunnel.revision + 1,
''',
)

# ---------------------------------------------------------------------------
# Typing status. Control packet only; no change to the proven transport path.
# ---------------------------------------------------------------------------
replace_once(
    'lib/chat_screen.dart',
    '''  bool _sendingFile = false;
  bool _hasText = false;
  CgMessage? _replyingTo;
''',
    '''  bool _sendingFile = false;
  bool _hasText = false;
  bool _typingSent = false;
  Timer? _typingStopTimer;
  Timer? _remoteTypingTimer;
  String? _remoteTypingName;
  CgMessage? _replyingTo;
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''  void _onComposerChanged() {
    final next = _text.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }
''',
    '''  void _onComposerChanged() {
    final next = _text.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);

    if (next && !_typingSent) {
      _typingSent = true;
      _sendControlBackground(<String, dynamic>{
        'operationId': CgIds.random(24),
        'action': 'typing',
        'typing': true,
      });
    }
    _typingStopTimer?.cancel();
    if (next) {
      _typingStopTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!_typingSent) return;
        _typingSent = false;
        _sendControlBackground(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'typing',
          'typing': false,
        });
      });
    } else if (_typingSent) {
      _typingSent = false;
      _sendControlBackground(<String, dynamic>{
        'operationId': CgIds.random(24),
        'action': 'typing',
        'typing': false,
      });
    }
  }
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''    switch (action) {
      case 'message_delete':
''',
    '''    switch (action) {
      case 'typing':
        if (sender.isEmpty || sender == widget.profile.id) return;
        final typing = data['typing'] == true;
        _remoteTypingTimer?.cancel();
        setState(() {
          _remoteTypingName = typing
              ? (data['relaySenderName']?.toString().trim().isNotEmpty == true
                    ? data['relaySenderName'].toString()
                    : (widget.ru ? 'Собеседник' : 'Peer'))
              : null;
        });
        if (typing) {
          _remoteTypingTimer = Timer(const Duration(milliseconds: 2400), () {
            if (mounted) setState(() => _remoteTypingName = null);
          });
        }
        break;
      case 'message_delete':
''',
)

# App-bar status shows pencil + who is typing.
replace_once(
    'lib/chat_screen.dart',
    '''            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _networkState == 'connected'
                        ? ChernogramColors.success
                        : scheme.onSurface.withValues(alpha: .28),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _networkState == 'connected' ? 'в сети' : 'подключение',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: .48),
                  ),
                ),
              ],
            ),
''',
    '''            if (_remoteTypingName != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_rounded,
                    size: 12,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_remoteTypingName!} печатает…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _networkState == 'connected'
                          ? ChernogramColors.success
                          : scheme.onSurface.withValues(alpha: .28),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _networkState == 'connected' ? 'в сети' : 'подключение',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurface.withValues(alpha: .48),
                    ),
                  ),
                ],
              ),
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''    unawaited(ChernogramSound.stopIncomingCall());
    unawaited(_subscription?.cancel());
''',
    '''    unawaited(ChernogramSound.stopIncomingCall());
    _typingStopTimer?.cancel();
    _remoteTypingTimer?.cancel();
    if (_typingSent) {
      _sendControlBackground(<String, dynamic>{
        'operationId': CgIds.random(24),
        'action': 'typing',
        'typing': false,
      });
    }
    unawaited(_subscription?.cancel());
''',
)

# ---------------------------------------------------------------------------
# Reaction smile icon disappears from every row. Long-press menu already owns
# the reaction chips, reply, forward, copy and delete actions.
# ---------------------------------------------------------------------------
replace_block(
    'lib/chat_screen.dart',
    '                          final bubble = Stack(\n',
    '                          return GestureDetector(\n',
    '''                          final bubble = _MessageBubble(
                            message: message,
                            mine: mine,
                            groupChat: _isGroupChat,
                            privacyLens: widget.privacyLens,
                            ru: widget.ru,
                            delivered: _networkState == 'connected',
                            read:
                                ((message.meta['readBy'] as List?) ??
                                        const <dynamic>[])
                                    .isNotEmpty,
                            onLongPress: () => _showMessageActions(message),
                          );
''',
    anchor='                        itemBuilder: (context, index) {',
)

# Read state is explicit, not only a coloured double-check.
replace_once(
    'lib/chat_screen.dart',
    '''            const SizedBox(width: 4),
          ],
          Text(
            _formatTime(message.sentAt),
''',
    '''            const SizedBox(width: 4),
            Text(
              read ? (ru ? 'прочитано' : 'read') : (delivered ? (ru ? 'доставлено' : 'delivered') : ''),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: read
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: .42),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            _formatTime(message.sentAt),
''',
)

# ---------------------------------------------------------------------------
# The exact user-supplied melody is materialized as an asset in CI. In-app
# ringing uses just_audio on both Android and Windows.
# ---------------------------------------------------------------------------
Path('lib/sound_service.dart').write_text(r'''import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class ChernogramSound {
  static const MethodChannel _channel = MethodChannel('chernogram/sound');
  static final AudioPlayer _incomingPlayer = AudioPlayer();
  static bool _ringPrepared = false;

  static Future<void> playMessage() async {
    try {
      await _channel.invokeMethod<void>('playMessage');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> startIncomingCall({required bool video}) async {
    try {
      await _incomingPlayer.stop();
      if (!_ringPrepared) {
        await _incomingPlayer.setAsset('assets/audio/incoming_call.mp3');
        _ringPrepared = true;
      } else {
        await _incomingPlayer.seek(Duration.zero);
      }
      await _incomingPlayer.setLoopMode(LoopMode.one);
      await _incomingPlayer.setVolume(1.0);
      unawaited(_incomingPlayer.play());
      try {
        await _channel.invokeMethod<void>(
          'startIncomingCallVibration',
          <String, dynamic>{'video': video},
        );
      } catch (_) {}
    } catch (_) {
      try {
        await _channel.invokeMethod<void>(
          'startIncomingCall',
          <String, dynamic>{'video': video},
        );
      } catch (_) {
        await SystemSound.play(SystemSoundType.alert);
      }
    }
  }

  static Future<void> stopIncomingCall() async {
    try {
      await _incomingPlayer.stop();
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('stopIncomingCall');
    } catch (_) {}
  }
}
''', encoding='utf-8')

# Notification channel v2 has the custom melody too, including the Android
# foreground/background receiver when the UI window is not open.
replace_once(
    'lib/background_runtime.dart',
    "const String _callChannelId = 'chernogram_calls';",
    "const String _callChannelId = 'chernogram_calls_v2';",
)
replace_once(
    'lib/background_runtime.dart',
    '''        importance: Importance.max,
        playSound: true,
        enableVibration: true,
''',
    '''        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
        enableVibration: true,
''',
)
replace_once(
    'lib/background_runtime.dart',
    '''          icon: 'chernogram_launcher_icon',
          playSound: true,
          enableVibration: true,
''',
    '''          icon: 'chernogram_launcher_icon',
          playSound: true,
          sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
          enableVibration: true,
''',
)

# ui_full_084 has already rewritten push_service.dart to work without Firebase.
replace_once(
    'lib/push_service.dart',
    "        'chernogram_calls',\n        'Звонки Чернограма',",
    "        'chernogram_calls_v2',\n        'Звонки Чернограма',",
)
replace_once(
    'lib/push_service.dart',
    '''        importance: Importance.max,
        playSound: true,
        enableVibration: true,
''',
    '''        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
        enableVibration: true,
''',
)
replace_once(
    'lib/push_service.dart',
    "        'chernogram_calls',\n        'Звонки Чернограма',\n        channelDescription: 'Входящие аудио- и видеозвонки',",
    "        'chernogram_calls_v2',\n        'Звонки Чернограма',\n        channelDescription: 'Входящие аудио- и видеозвонки',",
)
replace_once(
    'lib/push_service.dart',
    '''        icon: '@drawable/chernogram_launcher_icon',
      ),
''',
    '''        icon: '@drawable/chernogram_launcher_icon',
        sound: RawResourceAndroidNotificationSound('chernogram_call_ring'),
      ),
''',
)

# Android native channel now vibrates without replacing our custom audio.
replace_once(
    'android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt',
    '''                "startIncomingCall" -> {
                    startIncomingCallSound()
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
''',
    '''                "startIncomingCall" -> {
                    startIncomingCallSound()
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
                "startIncomingCallVibration" -> {
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
''',
)

# Launcher adaptive background should match the user's mask tile rather than
# the old black placeholder/egg appearance.
replace_once(
    'android/app/src/main/res/values/launcher_colors.xml',
    '#090909',
    '#FFFFFF',
)

print('Chernogram UI/lifecycle polish 0.85 applied')
