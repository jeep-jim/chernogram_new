from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:260]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


# ---------------------------------------------------------------------------
# UI foreground + active room state.
# ---------------------------------------------------------------------------
replace_once(
    'lib/main.dart',
    "import 'desktop_runtime.dart';\n",
    "import 'desktop_runtime.dart';\nimport 'ui_presence.dart';\n",
)
replace_once(
    'lib/main.dart',
    '''  runApp(const ChernogramApp());
  CgBackgroundRuntime.setAppVisible(true);
  unawaited(CgPushService.initialize());
''',
    '''  runApp(const ChernogramApp());
  CgUiPresence.setForeground(true);
  CgBackgroundRuntime.setAppVisible(true);
  unawaited(CgPushService.initialize());
''',
)
replace_once(
    'lib/main.dart',
    '''    CgBackgroundRuntime.setAppVisible(visible);
  }
''',
    '''    CgUiPresence.setForeground(visible);
    CgBackgroundRuntime.setAppVisible(visible);
  }
''',
)

# ---------------------------------------------------------------------------
# Chat tells the app/background service exactly which room is on screen.
# ---------------------------------------------------------------------------
replace_once(
    'lib/chat_screen.dart',
    "import 'app_monitor.dart';\n",
    "import 'app_monitor.dart';\nimport 'background_runtime.dart';\n",
)
replace_once(
    'lib/chat_screen.dart',
    "import 'sound_service.dart';\n",
    "import 'sound_service.dart';\nimport 'ui_presence.dart';\n",
)
replace_once(
    'lib/chat_screen.dart',
    '''    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
''',
    '''    _tunnel = widget.tunnel;
    CgUiPresence.enterTunnel(_tunnel.id);
    CgBackgroundRuntime.setActiveTunnel(_tunnel.id);
    _text.addListener(_onComposerChanged);
''',
)
replace_once(
    'lib/chat_screen.dart',
    '''    _text.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
''',
    '''    _text.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    CgUiPresence.leaveTunnel(_tunnel.id);
    CgBackgroundRuntime.setActiveTunnel(null);
    super.dispose();
''',
)

# ---------------------------------------------------------------------------
# Android foreground service receives visibility AND active-room state.
# It suppresses only the notification for the room already visible onscreen.
# If the app is minimized/closed, notifications are shown even if that room was
# the last opened one.
# ---------------------------------------------------------------------------
replace_once(
    'lib/background_runtime.dart',
    '''  static void setAppVisible(bool visible) {
    if (!Platform.isAndroid) return;
    _service.invoke('appState', <String, dynamic>{'visible': visible});
  }
''',
    '''  static void setAppVisible(bool visible) {
    if (!Platform.isAndroid) return;
    _service.invoke('appState', <String, dynamic>{'visible': visible});
  }

  static void setActiveTunnel(String? tunnelId) {
    if (!Platform.isAndroid) return;
    _service.invoke('activeTunnel', <String, dynamic>{
      'tunnelId': tunnelId ?? '',
    });
  }
''',
)
replace_once(
    'lib/background_runtime.dart',
    '''  var appVisible = false;
  final sessions = <InternetTunnelSession>[];
''',
    '''  var appVisible = false;
  String? activeTunnelId;
  final sessions = <InternetTunnelSession>[];
''',
)
replace_once(
    'lib/background_runtime.dart',
    '''  service.on('appState').listen((event) {
    appVisible = event?['visible'] == true;
  });
''',
    '''  service.on('appState').listen((event) {
    appVisible = event?['visible'] == true;
  });
  service.on('activeTunnel').listen((event) {
    final value = event?['tunnelId']?.toString() ?? '';
    activeTunnelId = value.isEmpty ? null : value;
  });
''',
)
replace_once(
    'lib/background_runtime.dart',
    '''    if (appVisible || message.authorId == profile.id || !shownIds.add(message.id)) {
      return;
    }
''',
    '''    if ((appVisible && activeTunnelId == tunnel.id) ||
        message.authorId == profile.id ||
        !shownIds.add(message.id)) {
      return;
    }
''',
)
replace_once(
    'lib/background_runtime.dart',
    '''    if (callId.isEmpty || from == profile.id || !shownIds.add('call:$callId')) {
      return;
    }
''',
    '''    if ((appVisible && activeTunnelId == tunnel.id) ||
        callId.isEmpty ||
        from == profile.id ||
        !shownIds.add('call:$callId')) {
      return;
    }
''',
)

# ---------------------------------------------------------------------------
# UI monitor: Windows and foreground Android don't raise a toast over the room
# the user is currently reading. Other rooms still notify. Minimized/hidden app
# still notifies normally.
# ---------------------------------------------------------------------------
replace_once(
    'lib/app_monitor.dart',
    "import 'push_service.dart';\n",
    "import 'push_service.dart';\nimport 'ui_presence.dart';\n",
)
replace_once(
    'lib/app_monitor.dart',
    '''        if (!CgPushService.configured || Platform.isWindows) {
          final attachment = message.attachment;
''',
    '''        if ((!CgPushService.configured || Platform.isWindows) &&
            !CgUiPresence.isTunnelOpen(tunnelId)) {
          final attachment = message.attachment;
''',
)
replace_once(
    'lib/app_monitor.dart',
    '''    if (!CgPushService.configured || Platform.isWindows) {
      unawaited(
        CgPushService.showIncomingCallNotification(<String, dynamic>{
''',
    '''    if ((!CgPushService.configured || Platform.isWindows) &&
        !CgUiPresence.isTunnelOpen(tunnelId)) {
      unawaited(
        CgPushService.showIncomingCallNotification(<String, dynamic>{
''',
)
replace_once(
    'lib/app_monitor.dart',
    '''  static void _rememberContact(String tunnelId, String id, String name) {
    final profile = _profile;
    if (profile == null || id.isEmpty || id == profile.id) return;
    _onContactSeen?.call(
''',
    '''  static void _rememberContact(String tunnelId, String id, String name) {
    final profile = _profile;
    if (profile == null || id.isEmpty || id == profile.id) return;
    CgUiPresence.markPeer(tunnelId, id, name);
    _onContactSeen?.call(
''',
)

# Optional FCM foreground callbacks follow the same rule if Firebase is enabled
# in a later build.
replace_once(
    'lib/push_service.dart',
    "import 'package:flutter_local_notifications/flutter_local_notifications.dart';\n",
    "import 'package:flutter_local_notifications/flutter_local_notifications.dart';\n\nimport 'ui_presence.dart';\n",
)
replace_once(
    'lib/push_service.dart',
    '''      if (event.wake == 'call') {
        await showIncomingCallNotification(message.data);
      } else {
        await showMessageNotification(
''',
    '''      if (event.wake == 'call') {
        if (!CgUiPresence.isTunnelOpen(event.roomKey)) {
          await showIncomingCallNotification(message.data);
        }
      } else if (!CgUiPresence.isTunnelOpen(event.roomKey)) {
        await showMessageNotification(
''',
)

# ---------------------------------------------------------------------------
# Invite QR becomes live: as soon as a remote peer actually joins this room,
# the page closes itself on the phone that was displaying the QR.
# ---------------------------------------------------------------------------
Path('lib/light/light_invite_qr.dart').write_text(r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../brand.dart';
import '../core_models.dart';
import '../ui_presence.dart';
import 'light_theme.dart';

String? _inviteTokenFromRaw(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  final direct = CgTunnel.fromInviteToken(value);
  if (direct != null) return value;

  try {
    final uri = Uri.parse(value);
    if (uri.scheme == 'chernogram' &&
        uri.host == 'join' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    final invite = uri.queryParameters['invite'];
    if (invite != null && invite.isNotEmpty) return invite;
  } catch (_) {}
  return null;
}

class LightInviteQrScreen extends StatefulWidget {
  final CgTunnel chat;
  final String inviteUrl;
  final Future<void> Function() onShare;

  const LightInviteQrScreen({
    super.key,
    required this.chat,
    required this.inviteUrl,
    required this.onShare,
  });

  @override
  State<LightInviteQrScreen> createState() => _LightInviteQrScreenState();
}

class _LightInviteQrScreenState extends State<LightInviteQrScreen> {
  StreamSubscription<CgPeerArrival>? _peerSubscription;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _peerSubscription = CgUiPresence.peerEvents.listen((arrival) {
      if (arrival.tunnelId == widget.chat.id) _closeAfterJoin(arrival.peerName);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (CgUiPresence.hasRemotePeer(widget.chat.id)) {
        _closeAfterJoin('');
      }
    });
  }

  void _closeAfterJoin(String peerName) {
    if (_closing || !mounted) return;
    _closing = true;
    final text = peerName.trim().isEmpty
        ? 'Участник подключён'
        : '$peerName подключён';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1100),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Подключить человека')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LightGlass(
                padding: const EdgeInsets.all(22),
                borderRadius: BorderRadius.circular(34),
                child: Column(
                  children: [
                    const ChernogramLogo(size: 78),
                    const SizedBox(height: 12),
                    Text(
                      widget.chat.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'На втором телефоне откройте Чернограм и нажмите «Сканировать QR». После подключения QR закроется сам.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.4,
                        color: scheme.onSurface.withValues(alpha: .62),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: QrImageView(
                        data: widget.inviteUrl,
                        version: QrVersions.auto,
                        size: 285,
                        gapless: true,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onShare,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Отправить ссылку'),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'QR и ссылка содержат один и тот же защищённый ключ диалога.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _peerSubscription?.cancel();
    super.dispose();
  }
}

class LightInviteScannerScreen extends StatefulWidget {
  const LightInviteScannerScreen({super.key});

  @override
  State<LightInviteScannerScreen> createState() =>
      _LightInviteScannerScreenState();
}

class _LightInviteScannerScreenState extends State<LightInviteScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoZoom: true,
  );

  bool _finished = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_finished) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final token = _inviteTokenFromRaw(raw);
      final chat = token == null ? null : CgTunnel.fromInviteToken(token);
      if (chat == null) {
        if (mounted) setState(() => _error = 'Это не QR-приглашение Чернограма');
        continue;
      }
      _finished = true;
      unawaited(_controller.stop());
      if (mounted) Navigator.pop(context, chat);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Сканировать QR'),
      actions: [
        IconButton(
          tooltip: 'Вспышка',
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_rounded),
        ),
        IconButton(
          tooltip: 'Сменить камеру',
          onPressed: _controller.switchCamera,
          icon: const Icon(Icons.cameraswitch_rounded),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 294,
              height: 294,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: const Color(0xFFA997FF), width: 3),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x668C7BFF),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 28,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xE6191D2A),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'Наведите камеру на QR другого телефона',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'После распознавания контакт и диалог сохранятся автоматически.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
''', encoding='utf-8')

# Make sure the monitor is actually listening to the fresh room before the QR
# appears, so the inviter can observe the second device joining in real time.
replace_once(
    'lib/light/light_chat_app.dart',
    '''  Future<void> _showInviteQr(CgTunnel chat, {String? contactName}) async {
    if (!mounted) return;
    await Navigator.push<void>(
''',
    '''  Future<void> _showInviteQr(CgTunnel chat, {String? contactName}) async {
    if (!mounted) return;
    await _syncMonitor();
    if (!mounted) return;
    await Navigator.push<void>(
''',
)

# Windows presence is tied to the actual window, not merely Flutter lifecycle.
replace_once(
    'lib/desktop_runtime.dart',
    "import 'package:window_manager/window_manager.dart';\n",
    "import 'package:window_manager/window_manager.dart';\n\nimport 'ui_presence.dart';\n",
)
replace_once(
    'lib/desktop_runtime.dart',
    '''  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
''',
    '''  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    CgUiPresence.setForeground(true);
    await windowManager.setSkipTaskbar(false);
''',
)
replace_once(
    'lib/desktop_runtime.dart',
    '''  Future<void> hideToTray() async {
    if (!Platform.isWindows || _quitting) return;
    await windowManager.hide();
''',
    '''  Future<void> hideToTray() async {
    if (!Platform.isWindows || _quitting) return;
    CgUiPresence.setForeground(false);
    await windowManager.hide();
''',
)
replace_once(
    'lib/desktop_runtime.dart',
    '''  @override
  void onWindowClose() {
    if (!_quitting) hideToTray();
  }
''',
    '''  @override
  void onWindowClose() {
    if (!_quitting) hideToTray();
  }

  @override
  void onWindowMinimize() {
    CgUiPresence.setForeground(false);
  }

  @override
  void onWindowRestore() {
    CgUiPresence.setForeground(true);
  }

  @override
  void onWindowFocus() {
    CgUiPresence.setForeground(true);
  }

  @override
  void onWindowBlur() {
    CgUiPresence.setForeground(false);
  }
''',
)

print('Invite auto-close and active-room notification suppression applied')
