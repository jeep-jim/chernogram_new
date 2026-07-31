from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_REF = "feature/files-first-0233"
CLIENT_REF = "feature/realtime-client-v1"
GATEWAY_REF = "feature/realtime-gateway-v1"


def git_show(ref: str, path: str, *, binary: bool = False):
    result = subprocess.check_output(
        ["git", "show", f"{ref}:{path}"],
        cwd=ROOT,
    )
    return result if binary else result.decode("utf-8")


def write_text(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def write_bytes(path: str, content: bytes) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count == 0 and new in source:
        return source
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return source.replace(old, new, 1)


def copy_tree(ref: str, directory: str) -> None:
    names = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", ref, directory],
        cwd=ROOT,
        text=True,
    ).splitlines()
    for name in names:
        if not name:
            continue
        write_bytes(name, git_show(ref, name, binary=True))


def materialize_transport() -> None:
    original = git_show(BASE_REF, "lib/internet_core.dart")
    legacy = original
    for old, new in (
        ("InternetRelay", "LegacyInternetRelay"),
        ("InternetTunnelSession", "LegacyInternetTunnelSession"),
        ("InternetEvent", "LegacyInternetEvent"),
    ):
        legacy = re.sub(rf"\b{old}\b", new, legacy)
    write_text("lib/legacy_ntfy_transport.dart", legacy)
    stable = (ROOT / "tooling/templates/internet_core_stable.dart").read_text(
        encoding="utf-8"
    )
    write_text("lib/internet_core.dart", stable)

    for name in (
        "lib/realtime_gateway_client.dart",
        "lib/realtime_gateway_config.dart",
        "lib/realtime_gateway_models.dart",
        "lib/realtime_gateway_outbox.dart",
    ):
        write_text(name, git_show(CLIENT_REF, name))

    config_path = ROOT / "lib/realtime_gateway_config.dart"
    config = config_path.read_text(encoding="utf-8")
    config = config.replace("defaultValue: false,", "defaultValue: true,", 1)
    config_path.write_text(config, encoding="utf-8")

    copy_tree(CLIENT_REF, "server/realtime_gateway")
    server_path = ROOT / "server/realtime_gateway/bin/server.dart"
    server = server_path.read_text(encoding="utf-8")
    ice_endpoint = r'''    if (request.uri.path == '/v1/ice') {
      final env = Platform.environment;
      final turnUrls = (env['CG_TURN_URLS'] ?? '')
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final username = env['CG_TURN_USERNAME']?.trim() ?? '';
      final credential = env['CG_TURN_CREDENTIAL']?.trim() ?? '';
      final servers = <Map<String, dynamic>>[
        <String, dynamic>{
          'urls': <String>[
            'stun:stun.cloudflare.com:3478',
            'stun:stun.l.google.com:19302',
          ],
        },
        if (turnUrls.isNotEmpty && username.isNotEmpty && credential.isNotEmpty)
          <String, dynamic>{
            'urls': turnUrls,
            'username': username,
            'credential': credential,
          },
      ];
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, dynamic>{'iceServers': servers}));
      await request.response.close();
      return;
    }
'''
    server = replace_once(
        server,
        "    if (request.uri.path != '/v1/realtime' ||\n",
        ice_endpoint + "    if (request.uri.path != '/v1/realtime' ||\n",
        "gateway ICE endpoint",
    )
    server = server.replace(
        "    final maxTtl = kind == 'signal'\n"
        "        ? const Duration(minutes: 2)\n"
        "        : kind == 'presence'\n"
        "            ? const Duration(seconds: 45)\n"
        "            : const Duration(days: 7);",
        "    final maxTtl = kind == 'signal'\n"
        "        ? const Duration(minutes: 2)\n"
        "        : kind == 'presence'\n"
        "            ? const Duration(seconds: 45)\n"
        "            : kind == 'public_index'\n"
        "                ? const Duration(days: 365)\n"
        "                : const Duration(days: 30);",
        1,
    )
    server = server.replace(
        "        'receipt',\n      }.contains(value);",
        "        'receipt',\n        'file_chunk',\n        'public_index',\n      }.contains(value);",
        1,
    )
    server_path.write_text(server, encoding="utf-8")


def materialize_background_and_sound() -> None:
    for name in (
        "lib/background_realtime_service.dart",
        "lib/pending_call.dart",
        "lib/sound_service.dart",
        "android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt",
        "android/app/src/main/res/drawable/chernogram_notification_icon.xml",
        "android/app/src/main/res/values/chernogram_keep.xml",
    ):
        write_text(name, git_show(GATEWAY_REF, name))
    for name in (
        "android/app/src/main/res/raw/chernogram_incoming.mp3",
        "assets/audio/chernogram_incoming.mp3",
    ):
        write_bytes(name, git_show(GATEWAY_REF, name, binary=True))

    bg_path = ROOT / "lib/background_realtime_service.dart"
    bg = bg_path.read_text(encoding="utf-8")
    bg = bg.replace("autoStart: false,", "autoStart: true,", 1)
    bg = bg.replace("autoStartOnBoot: false,", "autoStartOnBoot: true,", 1)
    recovery = """  // Recovery build: do not start a second Flutter isolate automatically.
  // Foreground chat/calls use the main process only while the new push/Telecom
  // background path is being built.
"""
    bg = bg.replace(recovery, "  await service.startService();\n")
    bg_path.write_text(bg, encoding="utf-8")

    sound_path = ROOT / "lib/sound_service.dart"
    sound = sound_path.read_text(encoding="utf-8")
    sound = sound.replace(
        "  static AudioPlayer? _incomingPlayer;\n",
        "  static AudioPlayer? _incomingPlayer;\n"
        "  static AudioPlayer? _outgoingPlayer;\n",
        1,
    )
    outgoing = r'''  static Future<void> startOutgoingCall() async {
    await stopOutgoingCall();
    try {
      final player = AudioPlayer();
      _outgoingPlayer = player;
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(.28);
      await player.setAsset('assets/audio/chernogram_incoming.mp3');
      unawaited(player.play());
    } catch (_) {
      await _outgoingPlayer?.dispose();
      _outgoingPlayer = null;
    }
  }

  static Future<void> stopOutgoingCall() async {
    final player = _outgoingPlayer;
    _outgoingPlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    await player.dispose();
  }

'''
    sound = replace_once(
        sound,
        "  static Future<void> stopIncomingCall() async {\n",
        outgoing + "  static Future<void> stopIncomingCall() async {\n",
        "outgoing ringback methods",
    )
    sound_path.write_text(sound, encoding="utf-8")


def patch_pubspec() -> None:
    path = ROOT / "pubspec.yaml"
    source = path.read_text(encoding="utf-8")
    source = re.sub(
        r"^version:\s*[^\n]+$",
        "version: 0.23.4+59",
        source,
        count=1,
        flags=re.M,
    )
    additions = {
        "flutter_background_service": "^5.1.0",
        "flutter_local_notifications": "^22.2.0",
    }
    for package, version in additions.items():
        if re.search(rf"^\s*{re.escape(package)}:", source, flags=re.M):
            continue
        source = replace_once(
            source,
            "  flutter_contacts: ^1.1.9+2\n",
            "  flutter_contacts: ^1.1.9+2\n"
            f"  {package}: {version}\n",
            f"pubspec {package}",
        )
    if "assets/audio/chernogram_incoming.mp3" not in source:
        source = source.rstrip() + "\n\nflutter:\n  uses-material-design: true\n  assets:\n    - assets/audio/chernogram_incoming.mp3\n"
        # Remove a previous minimal flutter block if one was already present.
        source = source.replace(
            "\nflutter:\n  uses-material-design: true\n\nflutter:\n",
            "\nflutter:\n",
            1,
        )
    path.write_text(source, encoding="utf-8")


def patch_manifest() -> None:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    source = path.read_text(encoding="utf-8")
    source = source.replace(
        "android:icon=\"@drawable/chernogram_launcher_icon\"",
        "android:icon=\"@mipmap/ic_launcher\"",
    )
    source = source.replace(
        "android:roundIcon=\"@drawable/chernogram_launcher_icon\"",
        "android:roundIcon=\"@mipmap/ic_launcher_round\"",
    )
    permissions = [
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
        "android.permission.FOREGROUND_SERVICE_MICROPHONE",
        "android.permission.FOREGROUND_SERVICE_CAMERA",
        "android.permission.RECEIVE_BOOT_COMPLETED",
        "android.permission.USE_FULL_SCREEN_INTENT",
        "android.permission.TURN_SCREEN_ON",
        "android.permission.SHOW_WHEN_LOCKED",
    ]
    marker = "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
    for permission in permissions:
        item = f"    <uses-permission android:name=\"{permission}\" />\n"
        if permission not in source:
            source = source.replace(marker, marker + item, 1)
    if "android:showWhenLocked" not in source:
        source = source.replace(
            "            android:windowSoftInputMode=\"adjustResize\">",
            "            android:windowSoftInputMode=\"adjustResize\"\n"
            "            android:showWhenLocked=\"true\"\n"
            "            android:turnScreenOn=\"true\">",
            1,
        )
    path.write_text(source, encoding="utf-8")


def patch_main() -> None:
    path = ROOT / "lib/main.dart"
    source = path.read_text(encoding="utf-8")
    if "background_realtime_service.dart" not in source:
        source = replace_once(
            source,
            "import 'brand.dart';\n",
            "import 'background_realtime_service.dart';\nimport 'brand.dart';\n",
            "main background import",
        )
    source = source.replace(
        "void main() {\n  WidgetsFlutterBinding.ensureInitialized();\n  runApp(const ChernogramApp());\n}",
        "Future<void> main() async {\n"
        "  WidgetsFlutterBinding.ensureInitialized();\n"
        "  await initializeChernogramRealtimeService();\n"
        "  runApp(const ChernogramApp());\n"
        "}",
        1,
    )
    source = source.replace(
        "class _ChernogramAppState extends State<ChernogramApp> {",
        "class _ChernogramAppState extends State<ChernogramApp>\n"
        "    with WidgetsBindingObserver {",
        1,
    )
    source = replace_once(
        source,
        "  void initState() {\n    super.initState();\n    unawaited(_loadSettings());\n  }",
        "  void initState() {\n"
        "    super.initState();\n"
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    unawaited(setChernogramAppForeground(true));\n"
        "    unawaited(_loadSettings());\n"
        "  }\n\n"
        "  @override\n"
        "  void didChangeAppLifecycleState(AppLifecycleState state) {\n"
        "    unawaited(\n"
        "      setChernogramAppForeground(state == AppLifecycleState.resumed),\n"
        "    );\n"
        "  }",
        "main lifecycle",
    )
    if "WidgetsBinding.instance.removeObserver(this);" not in source:
        source = replace_once(
            source,
            "  @override\n  Widget build(BuildContext context) {",
            "  @override\n"
            "  void dispose() {\n"
            "    WidgetsBinding.instance.removeObserver(this);\n"
            "    unawaited(setChernogramAppForeground(false));\n"
            "    super.dispose();\n"
            "  }\n\n"
            "  @override\n  Widget build(BuildContext context) {",
            "main dispose",
        )
    path.write_text(source, encoding="utf-8")


def patch_app_monitor() -> None:
    path = ROOT / "lib/app_monitor.dart"
    source = path.read_text(encoding="utf-8")
    start = source.index("    final recent = tunnels.toList()")
    end = source.index("    await Future.wait(monitored.map(_ensureTunnel));", start)
    end += len("    await Future.wait(monitored.map(_ensureTunnel));")
    replacement = """    final activeIds = tunnels.map((tunnel) => tunnel.id).toSet();
    final obsolete = _subscriptions.keys
        .where((tunnelId) => !activeIds.contains(tunnelId))
        .toList();
    for (final tunnelId in obsolete) {
      await _subscriptions.remove(tunnelId)?.cancel();
      _sessions.remove(tunnelId);
    }

    await Future.wait(tunnels.map(_ensureTunnel));"""
    source = source[:start] + replacement + source[end:]

    source = source.replace(
        "  static void _handleMessage(\n",
        "  static Future<void> _handleMessage(\n",
        1,
    )
    source = source.replace(
        "          _handleMessage(\n",
        "          unawaited(_handleMessage(\n",
        1,
    )
    source = source.replace(
        "            playSound: true,\n          );",
        "            playSound: true,\n          ));",
        1,
    )
    history_old = """          _handleMessage(
            tunnelId,
            Map<String, dynamic>.from(raw),
            playSound: false,
          );"""
    history_new = """          unawaited(_handleMessage(
            tunnelId,
            Map<String, dynamic>.from(raw),
            playSound: false,
          ));"""
    source = source.replace(history_old, history_new, 1)
    source = replace_once(
        source,
        "    var message = CgMessage.fromJson(raw);\n    if (message.id.isEmpty) return;",
        "    var message = CgMessage.fromJson(raw);\n"
        "    if (message.id.isEmpty) return;\n"
        "    message = await CgMediaStore.persistIncoming(message);",
        "persist received media",
    )
    path.write_text(source, encoding="utf-8")


def patch_media() -> None:
    path = ROOT / "lib/chat_media.dart"
    source = path.read_text(encoding="utf-8")
    persist = r'''  static Future<CgMessage> persistIncoming(CgMessage message) async {
    final attachment = message.attachment;
    final raw = attachment?.dataBase64;
    if (attachment == null || raw == null || raw.isEmpty) return message;
    try {
      final file = await persistBytes(
        attachmentId: attachment.id,
        name: attachment.name,
        bytes: base64Decode(raw),
      );
      return message.copyWith(
        attachment: CgAttachment(
          id: attachment.id,
          name: attachment.name,
          size: attachment.size,
          kind: attachment.kind,
          localPath: file.path,
        ),
      );
    } catch (_) {
      return message;
    }
  }

'''
    if "persistIncoming(CgMessage message)" not in source:
        source = replace_once(
            source,
            "  static Future<File?> ensureFile(CgAttachment attachment) async {\n",
            persist + "  static Future<File?> ensureFile(CgAttachment attachment) async {\n",
            "incoming media externalization",
        )
    source = replace_once(
        source,
        "    final attachment = widget.attachment;\n    final bytes = _bytes;",
        "    final attachment = widget.attachment;\n"
        "    if (attachment.kind == 'circle') {\n"
        "      return CgCircleAttachment(attachment: attachment);\n"
        "    }\n"
        "    final bytes = _bytes;",
        "circle inline media",
    )
    circle_widget = r'''
class CgCircleAttachment extends StatefulWidget {
  final CgAttachment attachment;

  const CgCircleAttachment({super.key, required this.attachment});

  @override
  State<CgCircleAttachment> createState() => _CgCircleAttachmentState();
}

class _CgCircleAttachmentState extends State<CgCircleAttachment> {
  VideoPlayerController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (file == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(0);
    unawaited(controller.play());
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _loading = false;
    });
  }

  Future<void> _open() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CgVideoPlayerScreen(
          file: file,
          circle: true,
          title: widget.attachment.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return GestureDetector(
      onTap: _open,
      child: SizedBox.square(
        dimension: 220,
        child: ClipOval(
          child: ColoredBox(
            color: Colors.black,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : controller == null
                ? const Center(
                    child: Icon(Icons.play_circle_outline_rounded, size: 54),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white70,
                          size: 46,
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
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }
}
'''
    if "class CgCircleAttachment" not in source:
        source = source.rstrip() + "\n" + circle_widget + "\n"
    path.write_text(source, encoding="utf-8")


def patch_core_storage() -> None:
    path = ROOT / "lib/core_models.dart"
    source = path.read_text(encoding="utf-8")
    if "import 'dart:io';" not in source:
        source = source.replace("import 'dart:convert';\n", "import 'dart:convert';\nimport 'dart:io';\n", 1)
    if "package:path_provider/path_provider.dart" not in source:
        source = source.replace(
            "import 'package:shared_preferences/shared_preferences.dart';\n",
            "import 'package:path_provider/path_provider.dart';\n"
            "import 'package:shared_preferences/shared_preferences.dart';\n",
            1,
        )
    old = """  static Future<void> saveTunnels(List<CgTunnel> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      tunnelsKey,
      jsonEncode(tunnels.map((tunnel) => tunnel.toJson()).toList()),
    );
  }
"""
    new = r'''  static Future<void> saveTunnels(List<CgTunnel> tunnels) async {
    final prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    final media = Directory('${support.path}/chernogram_media');
    await media.create(recursive: true);
    final encoded = <Map<String, dynamic>>[];
    for (final tunnel in tunnels) {
      final tunnelJson = tunnel.toJson();
      final rawMessages = tunnelJson['messages'];
      if (rawMessages is List) {
        for (final rawMessage in rawMessages.whereType<Map>()) {
          final attachment = rawMessage['attachment'];
          if (attachment is! Map) continue;
          final map = Map<String, dynamic>.from(attachment);
          final payload = map['dataBase64']?.toString();
          if (payload != null && payload.isNotEmpty) {
            try {
              final id = map['id']?.toString() ?? CgIds.random(16);
              final name = (map['name']?.toString() ?? 'file')
                  .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
              final file = File('${media.path}/${id}_$name');
              if (!await file.exists()) {
                await file.writeAsBytes(base64Decode(payload), flush: true);
              }
              map['localPath'] = file.path;
              map.remove('dataBase64');
              rawMessage['attachment'] = map;
            } catch (_) {}
          }
        }
      }
      encoded.add(Map<String, dynamic>.from(tunnelJson));
    }
    await prefs.setString(tunnelsKey, jsonEncode(encoded));
  }
'''
    source = replace_once(source, old, new, "externalized tunnel storage")
    path.write_text(source, encoding="utf-8")


def patch_calls() -> None:
    path = ROOT / "lib/call_service.dart"
    source = path.read_text(encoding="utf-8")
    if "import 'ice_config.dart';" not in source:
        source = replace_once(
            source,
            "import 'internet_core.dart';\n",
            "import 'ice_config.dart';\n"
            "import 'internet_core.dart';\n"
            "import 'sound_service.dart';\n",
            "call ICE and sound imports",
        )
    pattern = re.compile(
        r"      final peer = await createPeerConnection\(<String, dynamic>\{\n"
        r"        'iceServers': <Map<String, dynamic>>\[[\s\S]*?\n"
        r"        \],\n"
        r"        'sdpSemantics': 'unified-plan',"
    )
    replacement = """      final iceServers = await CgIceConfig.load();
      final peer = await createPeerConnection(<String, dynamic>{
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',"""
    source, count = pattern.subn(replacement, source, count=1)
    if count != 1:
        raise RuntimeError(f"call ICE block: expected one match, found {count}")
    source = replace_once(
        source,
        "        await _sendInvite();\n",
        "        await _sendInvite();\n"
        "        unawaited(ChernogramSound.startOutgoingCall());\n",
        "outgoing ringback start",
    )
    source = replace_once(
        source,
        "  void _markConnected() {\n    _connectedAt ??= DateTime.now();",
        "  void _markConnected() {\n"
        "    unawaited(ChernogramSound.stopOutgoingCall());\n"
        "    _connectedAt ??= DateTime.now();",
        "ringback stop connected",
    )
    source = replace_once(
        source,
        "  void _finish(String status) {\n    if (_ended || !mounted) return;",
        "  void _finish(String status) {\n"
        "    unawaited(ChernogramSound.stopOutgoingCall());\n"
        "    if (_ended || !mounted) return;",
        "ringback stop finish",
    )
    source = replace_once(
        source,
        "  void dispose() {\n    _ended = true;",
        "  void dispose() {\n"
        "    unawaited(ChernogramSound.stopOutgoingCall());\n"
        "    _ended = true;",
        "ringback stop dispose",
    )
    path.write_text(source, encoding="utf-8")


def patch_product_ui() -> None:
    path = ROOT / "lib/android_data_first.dart"
    source = path.read_text(encoding="utf-8")
    source = source.replace("import 'agent_screen.dart';\n", "")
    if "import 'install_share_sheet.dart';" not in source:
        source = replace_once(
            source,
            "import 'internet_core.dart';\n",
            "import 'install_share_sheet.dart';\n"
            "import 'internet_core.dart';\n"
            "import 'public_file_index.dart';\n",
            "product imports",
        )
    source = replace_once(
        source,
        "        onCreatePublicRoom: () async {\n",
        "        onJoinToken: _joinToken,\n"
        "        onCreatePublicRoom: () async {\n",
        "files join callback",
    )
    source = replace_once(
        source,
        "  final VoidCallback onCreatePublicRoom;\n",
        "  final VoidCallback onCreatePublicRoom;\n"
        "  final Future<void> Function(String token) onJoinToken;\n",
        "files callback field",
    )
    source = replace_once(
        source,
        "    required this.onCreatePublicRoom,\n",
        "    required this.onCreatePublicRoom,\n"
        "    required this.onJoinToken,\n",
        "files callback constructor",
    )
    source = replace_once(
        source,
        "  final Set<String> _selectedFileIds = <String>{};\n",
        "  final Set<String> _selectedFileIds = <String>{};\n"
        "  final CgPublicFileIndex _publicIndex = CgPublicFileIndex.instance;\n"
        "  StreamSubscription<List<CgPublicFileRecord>>? _publicSubscription;\n"
        "  List<CgPublicFileRecord> _globalFiles = const <CgPublicFileRecord>[];\n\n"
        "  @override\n"
        "  void initState() {\n"
        "    super.initState();\n"
        "    _globalFiles = _publicIndex.records;\n"
        "    _publicSubscription = _publicIndex.changes.listen((records) {\n"
        "      if (mounted) setState(() => _globalFiles = records);\n"
        "    });\n"
        "    unawaited(_publicIndex.initialize(widget.profile));\n"
        "  }\n",
        "global file state",
    )
    publish_anchor = """      await ChernogramAppMonitor.publishMessage(
        profile: widget.profile,
        tunnel: updated,
        message: message,
      );
"""
    source = replace_once(
        source,
        publish_anchor,
        publish_anchor
        + "      await _publicIndex.publish(\n"
        + "        profile: widget.profile,\n"
        + "        room: updated,\n"
        + "        message: message,\n"
        + "      );\n",
        "publish global file metadata",
    )
    source = replace_once(
        source,
        "    final entries = _entries.where((entry) {",
        "    final globalEntries = (_filter == 2\n"
        "            ? const <CgPublicFileRecord>[]\n"
        "            : _publicIndex.search(query))\n"
        "        .take(query.isEmpty ? 12 : 40)\n"
        "        .toList(growable: false);\n"
        "    final entries = _entries.where((entry) {",
        "global file search",
    )
    global_view = r'''        if (globalEntries.isNotEmpty)
          SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              scrollDirection: Axis.horizontal,
              itemCount: globalEntries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final record = globalEntries[index];
                return SizedBox(
                  width: 248,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => widget.onJoinToken(record.inviteToken),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.public_rounded, size: 32),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    record.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${record.roomName} · ${CgMediaStore.fileSize(record.size)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
'''
    source = replace_once(
        source,
        "        if (_selectedFileIds.isNotEmpty)\n",
        global_view + "        if (_selectedFileIds.isNotEmpty)\n",
        "global file results UI",
    )
    source = replace_once(
        source,
        "  void dispose() {\n    _search.dispose();\n    super.dispose();\n  }\n}\n\nclass _MusicEntry",
        "  void dispose() {\n"
        "    unawaited(_publicSubscription?.cancel());\n"
        "    _search.dispose();\n"
        "    super.dispose();\n"
        "  }\n"
        "}\n\n"
        "class _MusicEntry",
        "files dispose subscription",
    )
    agent_pattern = re.compile(
        r"      _ProfileAction\(\n"
        r"        icon: Icons\.auto_awesome_rounded,[\s\S]*?"
        r"      const SizedBox\(height: 8\),\n"
        r"      _ProfileAction\(\n"
        r"        icon: Icons\.install_mobile_rounded,"
    )
    source, count = agent_pattern.subn(
        "      _ProfileAction(\n        icon: Icons.install_mobile_rounded,",
        source,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"agent card removal: expected one match, found {count}")
    share_pattern = re.compile(
        r"        onTap: \(\) => Share\.share\(\n"
        r"          ru\n"
        r"              \? 'Установить Чернограм: \$_androidInstallUrl'\n"
        r"              : 'Install Chernogram: \$_androidInstallUrl',\n"
        r"        \),"
    )
    source, count = share_pattern.subn(
        "        onTap: () => showChernogramInstallShareSheet(\n"
        "          context,\n"
        "          ru: ru,\n"
        "        ),",
        source,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"install QR action: expected one match, found {count}")
    source = source.replace(
        "Агент и функции ИИ удалены из навигации и больше не участвуют в продукте.",
        "Фоновая связь, файлы и звонки работают отдельно от интерфейса и не блокируют его.",
    )
    source = source.replace(
        "Agent and AI features are removed from the product flow.",
        "Background connectivity, files, and calls are isolated from the interface and never block it.",
    )
    path.write_text(source, encoding="utf-8")


def main() -> None:
    materialize_transport()
    materialize_background_and_sound()
    patch_pubspec()
    patch_manifest()
    patch_main()
    patch_app_monitor()
    patch_media()
    patch_core_storage()
    patch_calls()
    patch_product_ui()
    print("Chernogram 0.23.4 stable core materialized")


if __name__ == "__main__":
    main()
