from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


def patch_function(path: str, start_marker: str, end_marker: str, transform) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"Start marker not found in {path}: {start_marker}")
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"End marker not found in {path}: {end_marker}")
    block = text[start:end]
    updated = transform(block)
    if updated == block:
        raise SystemExit(f"Transform made no changes in {path}: {start_marker}")
    file.write_text(text[:start] + updated + text[end:], encoding="utf-8")


# Version and foreground-service dependency.
replace_once("pubspec.yaml", "version: 0.51.0+74", "version: 0.52.0+75")
replace_once(
    "pubspec.yaml",
    "  flutter_local_notifications: ^22.2.0\n",
    "  flutter_local_notifications: ^22.2.0\n"
    "  flutter_foreground_task: ^10.0.0\n",
)

# The build starts from the proven relay transport from build 73, then hardens it.
replace_once(
    "lib/internet_core.dart",
    "  final String nickname;\n\n",
    "  final String nickname;\n"
    "  final bool listenOnly;\n\n",
)
replace_once(
    "lib/internet_core.dart",
    "  final Set<String> _connectingHosts = <String>{};\n",
    "  final Set<String> _connectingHosts = <String>{};\n"
    "  final Set<String> _pollingHosts = <String>{};\n"
    "  final Map<String, String> _lastRelayIds = <String, String>{};\n",
)
replace_once(
    "lib/internet_core.dart",
    "  Timer? _outboxTimer;\n",
    "  Timer? _outboxTimer;\n  Timer? _pollTimer;\n",
)
replace_once(
    "lib/internet_core.dart",
    "    required this.nickname,\n  });",
    "    required this.nickname,\n    this.listenOnly = false,\n  });",
)
replace_once(
    "lib/internet_core.dart",
    "      await _prepareCryptoAndTopic();\n      await _loadOutbox();\n",
    "      await _prepareCryptoAndTopic();\n"
    "      if (!listenOnly) await _loadOutbox();\n",
)
replace_once(
    "lib/internet_core.dart",
    "        _startTimers();\n        unawaited(_publishPresence());\n        unawaited(_flushOutbox());\n",
    "        _startTimers();\n"
    "        if (!listenOnly) {\n"
    "          unawaited(_publishPresence());\n"
    "          unawaited(_flushOutbox());\n"
    "        }\n",
)
replace_once(
    "lib/internet_core.dart",
    "          queryParameters: const <String, String>{'since': '30m'},\n",
    "          queryParameters: const <String, String>{'since': '12h'},\n",
)
replace_once(
    "lib/internet_core.dart",
    "      final message = Map<String, dynamic>.from(decoded);\n      if (message['event']?.toString() != 'message') return;\n",
    "      final message = Map<String, dynamic>.from(decoded);\n"
    "      final relayId = message['id']?.toString() ?? '';\n"
    "      if (relayId.isNotEmpty) _lastRelayIds[host] = relayId;\n"
    "      if (message['event']?.toString() != 'message') return;\n",
)
replace_once(
    "lib/internet_core.dart",
    "  void _onHostDisconnected(String host) {\n",
    "  Future<void> _pollRelays() async {\n"
    "    if (_closed) return;\n"
    "    await Future.wait<void>(\n"
    "      relayHosts.map(_pollHost),\n"
    "      eagerError: false,\n"
    "    );\n"
    "  }\n\n"
    "  Future<void> _pollHost(String host) async {\n"
    "    if (_closed || !_pollingHosts.add(host)) return;\n"
    "    try {\n"
    "      await _prepareCryptoAndTopic();\n"
    "      final since = _lastRelayIds[host] ?? '12h';\n"
    "      final response = await _http\n"
    "          .get(\n"
    "            Uri(\n"
    "              scheme: 'https',\n"
    "              host: host,\n"
    "              path: '/${_topic!}/json',\n"
    "              queryParameters: <String, String>{\n"
    "                'poll': '1',\n"
    "                'since': since,\n"
    "              },\n"
    "            ),\n"
    "          )\n"
    "          .timeout(const Duration(seconds: 8));\n"
    "      if (response.statusCode < 200 || response.statusCode >= 300) return;\n"
    "      final text = utf8.decode(response.bodyBytes, allowMalformed: true);\n"
    "      for (final line in const LineSplitter().convert(text)) {\n"
    "        if (line.trim().isEmpty) continue;\n"
    "        await _handleSocketMessage(host, line);\n"
    "      }\n"
    "    } catch (_) {\n"
    "      _scheduleHostReconnect(host);\n"
    "    } finally {\n"
    "      _pollingHosts.remove(host);\n"
    "    }\n"
    "  }\n\n"
    "  void _onHostDisconnected(String host) {\n",
)
replace_once(
    "lib/internet_core.dart",
    "  Future<void> sendSignal(Map<String, dynamic> signal) async {\n"
    "    await _sendEnvelope('signal', signal, queueOnFailure: false);\n"
    "  }\n",
    "  Future<void> sendSignal(Map<String, dynamic> signal) async {\n"
    "    await _sendEnvelope('signal', signal);\n"
    "  }\n",
)
replace_once(
    "lib/internet_core.dart",
    "    if (_closed) return;\n    final queued = _QueuedEnvelope(\n",
    "    if (_closed) return;\n"
    "    if (listenOnly && kind != 'ack') return;\n"
    "    final queued = _QueuedEnvelope(\n",
)
replace_once(
    "lib/internet_core.dart",
    "    final reliable = queueOnFailure &&\n"
    "        (kind == 'message' || kind == 'control' || kind == 'file_chunk');\n",
    "    final reliable = queueOnFailure &&\n"
    "        (kind == 'message' ||\n"
    "            kind == 'control' ||\n"
    "            kind == 'file_chunk' ||\n"
    "            kind == 'signal');\n",
)
replace_once(
    "lib/internet_core.dart",
    "      _outbox.removeWhere(\n"
    "        (_, item) => now.difference(item.createdAt) > _packetLifetime,\n"
    "      );\n",
    "      _outbox.removeWhere((_, item) {\n"
    "        final lifetime = item.kind == 'signal'\n"
    "            ? const Duration(minutes: 3)\n"
    "            : _packetLifetime;\n"
    "        return now.difference(item.createdAt) > lifetime;\n"
    "      });\n",
)
replace_once(
    "lib/internet_core.dart",
    "                now.difference(item.createdAt) <= _packetLifetime,\n",
    "                now.difference(item.createdAt) <=\n"
    "                    (item.kind == 'signal'\n"
    "                        ? const Duration(minutes: 3)\n"
    "                        : _packetLifetime),\n",
)
replace_once(
    "lib/internet_core.dart",
    "    _outboxTimer?.cancel();\n"
    "    _presenceTimer = Timer.periodic(const Duration(seconds: 18), (_) {\n"
    "      unawaited(_publishPresence());\n"
    "    });\n",
    "    _outboxTimer?.cancel();\n"
    "    _pollTimer?.cancel();\n"
    "    if (!listenOnly) {\n"
    "      _presenceTimer = Timer.periodic(const Duration(seconds: 18), (_) {\n"
    "        unawaited(_publishPresence());\n"
    "      });\n"
    "    }\n",
)
replace_once(
    "lib/internet_core.dart",
    "    _outboxTimer = Timer.periodic(const Duration(seconds: 3), (_) {\n"
    "      unawaited(_flushOutbox());\n"
    "    });\n",
    "    if (!listenOnly) {\n"
    "      _outboxTimer = Timer.periodic(const Duration(seconds: 3), (_) {\n"
    "        unawaited(_flushOutbox());\n"
    "      });\n"
    "    }\n"
    "    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {\n"
    "      unawaited(_pollRelays());\n"
    "    });\n"
    "    unawaited(_pollRelays());\n",
)
replace_once(
    "lib/internet_core.dart",
    "    _outboxTimer?.cancel();\n    for (final timer in _relayRetryTimers.values) {\n",
    "    _outboxTimer?.cancel();\n"
    "    _pollTimer?.cancel();\n"
    "    for (final timer in _relayRetryTimers.values) {\n",
)
replace_once(
    "lib/internet_core.dart",
    "    required List<Map<String, dynamic>> history,\n  }) async {\n",
    "    required List<Map<String, dynamic>> history,\n"
    "    bool listenOnly = false,\n"
    "  }) async {\n",
)
replace_once(
    "lib/internet_core.dart",
    "        existing.secret == secret &&\n        existing.profileId == profileId) {\n",
    "        existing.secret == secret &&\n"
    "        existing.profileId == profileId &&\n"
    "        existing.listenOnly == listenOnly) {\n",
)
replace_once(
    "lib/internet_core.dart",
    "      nickname: nickname,\n    )..replaceHistory(history);\n",
    "      nickname: nickname,\n"
    "      listenOnly: listenOnly,\n"
    "    )..replaceHistory(history);\n",
)
replace_once(
    "lib/internet_core.dart",
    "  static Future<void> close(String tunnelId) async {\n",
    "  static void reconnectAll() {\n"
    "    for (final session in _sessions.values) {\n"
    "      unawaited(session.connect());\n"
    "    }\n"
    "  }\n\n"
    "  static Future<void> close(String tunnelId) async {\n",
)

# Do not permanently consume an incoming call before navigation exists.
replace_once(
    "lib/app_monitor.dart",
    "    if (profile == null ||\n"
    "        tunnel == null ||\n"
    "        from.isEmpty ||\n"
    "        from == profile.id ||\n"
    "        !CgSignalRegistry.claim(callId) ||\n"
    "        _dialogOpen) {\n"
    "      return;\n"
    "    }\n",
    "    if (profile == null ||\n"
    "        tunnel == null ||\n"
    "        from.isEmpty ||\n"
    "        from == profile.id ||\n"
    "        _dialogOpen) {\n"
    "      return;\n"
    "    }\n",
)
replace_once(
    "lib/app_monitor.dart",
    "    final context = chernogramNavigatorKey.currentContext;\n"
    "    if (context == null) return;\n"
    "    _dialogOpen = true;\n",
    "    final context = chernogramNavigatorKey.currentContext;\n"
    "    if (context == null ||\n"
    "        !CgSignalRegistry.claim('$tunnelId:$callId')) {\n"
    "      return;\n"
    "    }\n"
    "    _dialogOpen = true;\n",
)

# Serialize WebRTC negotiation and throttle ICE restarts.
replace_once(
    "lib/call_service.dart",
    "  bool _preparing = true;\n",
    "  bool _preparing = true;\n"
    "  bool _negotiating = false;\n"
    "  bool _handlingRemoteOffer = false;\n"
    "  DateTime? _lastRecoveryAt;\n",
)


def patch_make_offer(block: str) -> str:
    block = block.replace(
        "    if (peer == null || _peerId == null || _ended) return;\n"
        "    try {\n",
        "    if (peer == null || _peerId == null || _ended) return;\n"
        "    if (!iceRestart && _localOffer != null) {\n"
        "      await _sendOffer(_localOffer!);\n"
        "      return;\n"
        "    }\n"
        "    if (_negotiating) return;\n"
        "    _negotiating = true;\n"
        "    try {\n",
        1,
    )
    tail = "      }\n    }\n  }\n\n"
    if not block.endswith(tail):
        raise SystemExit("Unexpected _makeOffer tail")
    return block[: -len(tail)] + "      }\n    } finally {\n      _negotiating = false;\n    }\n  }\n\n"


patch_function(
    "lib/call_service.dart",
    "  Future<void> _makeOffer({bool iceRestart = false}) async {",
    "  Future<void> _sendOffer",
    patch_make_offer,
)


def patch_handle_offer(block: str) -> str:
    block = block.replace(
        "    if (peer == null || sdp == null || sdp.isEmpty || _ended) return;\n"
        "    try {\n",
        "    if (peer == null || sdp == null || sdp.isEmpty || _ended) return;\n"
        "    if (_handlingRemoteOffer) return;\n"
        "    _handlingRemoteOffer = true;\n"
        "    try {\n",
        1,
    )
    tail = "    } catch (_) {\n      await _sendReady();\n    }\n  }\n\n"
    if not block.endswith(tail):
        raise SystemExit("Unexpected _handleOffer tail")
    return block[: -len(tail)] + (
        "    } catch (_) {\n"
        "      await _sendReady();\n"
        "    } finally {\n"
        "      _handlingRemoteOffer = false;\n"
        "    }\n"
        "  }\n\n"
    )


patch_function(
    "lib/call_service.dart",
    "  Future<void> _handleOffer(Map<String, dynamic> data) async {",
    "  Future<void> _handleAnswer",
    patch_handle_offer,
)
replace_once(
    "lib/call_service.dart",
    "  Future<void> _recoverConnection() async {\n"
    "    if (_ended || _connectedAt == null && _peerId == null) return;\n"
    "    if (widget.isCaller) {\n",
    "  Future<void> _recoverConnection() async {\n"
    "    if (_ended || _connectedAt == null && _peerId == null) return;\n"
    "    final now = DateTime.now();\n"
    "    final last = _lastRecoveryAt;\n"
    "    if (last != null && now.difference(last) < const Duration(seconds: 4)) {\n"
    "      return;\n"
    "    }\n"
    "    _lastRecoveryAt = now;\n"
    "    if (widget.isCaller) {\n",
)

# Main isolate lifecycle: keep Android service alive and reconnect immediately on resume.
Path("lib/main.dart").write_text(
    """import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigation.dart';
import 'background_service.dart';
import 'internet_core.dart';
import 'light/light_chat_app.dart';
import 'light/light_theme.dart';
import 'update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ChernogramApp());
}

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp>
    with WidgetsBindingObserver {
  bool _darkMode = true;
  bool _ready = false;
  bool _updateScheduled = false;
  Timer? _activeHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemUi(true);
    _setAppActive(true);
    unawaited(_loadSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ChernogramBackgroundService.start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _setAppActive(active);
    if (active) InternetRelay.reconnectAll();
  }

  void _setAppActive(bool active) {
    _activeHeartbeat?.cancel();
    unawaited(ChernogramBackgroundService.setAppActive(active));
    if (active) {
      _activeHeartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(ChernogramBackgroundService.setAppActive(true));
      });
    }
  }

  SystemUiOverlayStyle _overlay(bool dark) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  void _applySystemUi(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(_overlay(dark));
  }

  Future<void> _loadSettings() async {
    var dark = true;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
      dark = prefs.getBool('dark_mode') ?? true;
    } catch (_) {}
    _applySystemUi(dark);
    if (!mounted) return;
    setState(() {
      _darkMode = dark;
      _ready = true;
    });
    _scheduleUpdateCheck();
  }

  Future<void> _toggleTheme() async {
    final next = !_darkMode;
    _applySystemUi(next);
    if (mounted) setState(() => _darkMode = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dark_mode', next);
    } catch (_) {}
  }

  void _scheduleUpdateCheck() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final context = chernogramNavigatorKey.currentContext;
      if (context == null) {
        _updateScheduled = false;
        _scheduleUpdateCheck();
        return;
      }
      unawaited(
        ChernogramUpdater.checkAndPrompt(context, ru: true, manual: false),
      );
    });
  }

  Widget _home(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ChernogramLightHome(
      darkMode: _darkMode,
      onToggleTheme: _toggleTheme,
      onCheckUpdates: () {
        unawaited(
          ChernogramUpdater.checkAndPrompt(context, ru: true, manual: true),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeHeartbeat?.cancel();
    unawaited(ChernogramBackgroundService.setAppActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _overlay(_darkMode),
    child: MaterialApp(
      navigatorKey: chernogramNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Чернограм',
      theme: lightChatTheme(Brightness.light),
      darkTheme: lightChatTheme(Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 180),
      home: Builder(builder: _home),
      builder: (context, child) => LightBackdrop(
        dark: _darkMode,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
""",
    encoding="utf-8",
)

# Android remote-messaging foreground service declaration.
replace_once(
    "android/app/src/main/AndroidManifest.xml",
    "    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE\" />\n",
    "    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE\" />\n"
    "    <uses-permission android:name=\"android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING\" />\n",
)
replace_once(
    "android/app/src/main/AndroidManifest.xml",
    "        <provider\n",
    "        <service\n"
    "            android:name=\"com.pravera.flutter_foreground_task.service.ForegroundService\"\n"
    "            android:foregroundServiceType=\"remoteMessaging\"\n"
    "            android:exported=\"false\"\n"
    "            android:stopWithTask=\"false\" />\n\n"
    "        <provider\n",
)

# Fix the non-void future ignored by the background timer.
replace_once(
    "lib/background_service.dart",
    "      unawaited(\n"
    "        FlutterForegroundTask.updateService(\n"
    "          notificationTitle: 'Чернограм на связи',\n"
    "          notificationText: 'Сообщения и звонки работают в фоне',\n"
    "        ),\n"
    "      );\n",
    "      unawaited(\n"
    "        FlutterForegroundTask.updateService(\n"
    "          notificationTitle: 'Чернограм на связи',\n"
    "          notificationText: 'Сообщения и звонки работают в фоне',\n"
    "        ).then<void>((_) {}),\n"
    "      );\n",
)

print("Reliability build 75 patches applied")
