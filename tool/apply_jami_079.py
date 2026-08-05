#!/usr/bin/env python3
"""Wire the hidden Jami core into the existing Chernogram UI."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace(path: str, old: str, new: str, *, count: int = 1) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    found = text.count(old)
    if found < count:
        raise SystemExit(f"{path}: expected at least {count} occurrence(s), found {found}: {old!r}")
    target.write_text(text.replace(old, new, count), encoding="utf-8")


def replace_once_if_missing(path: str, marker: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f"{path}: patch anchor not found: {old!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once_if_missing(
    "lib/internet_core.dart",
    "typedef InternetSessionFactory",
    "class InternetRelay {",
    """typedef InternetSessionFactory = Future<InternetTunnelSession> Function({
  required String tunnelId,
  required String secret,
  required String profileId,
  required String nickname,
  required List<Map<String, dynamic>> history,
});

class InternetRelay {
  static InternetSessionFactory? preferredFactory;""",
)

replace_once_if_missing(
    "lib/internet_core.dart",
    "final factory = preferredFactory;",
    """  }) async {
    unawaited(_ensurePushListener());""",
    """  }) async {
    final factory = preferredFactory;
    if (factory != null) {
      final existing = _sessions[tunnelId];
      if (existing != null &&
          existing.secret == secret &&
          existing.profileId == profileId) {
        existing.replaceHistory(history);
        unawaited(existing.connect());
        return existing;
      }
      if (existing != null) await existing.close();
      final session = await factory(
        tunnelId: tunnelId,
        secret: secret,
        profileId: profileId,
        nickname: nickname,
        history: history,
      );
      _sessions[tunnelId] = session;
      return session;
    }
    unawaited(_ensurePushListener());""",
)

replace_once_if_missing(
    "lib/main.dart",
    "import 'jami_core.dart';",
    "import 'light/light_theme.dart';",
    "import 'jami_core.dart';\nimport 'light/light_theme.dart';",
)
replace_once_if_missing(
    "lib/main.dart",
    "CgJamiRelay.install();",
    "  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);\n  runApp",
    "  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);\n  CgJamiRelay.install();\n  runApp",
)

replace_once_if_missing(
    "lib/core_models.dart",
    "final String? jamiOwner;",
    "  final String ownerId;\n  final String secret;",
    "  final String ownerId;\n  final String? jamiOwner;\n  final String secret;",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "this.jamiOwner,",
    "    required this.ownerId,\n    required this.secret,",
    "    required this.ownerId,\n    this.jamiOwner,\n    required this.secret,",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "String? jamiOwner,",
    "    String? secret,\n    String? avatarBase64,",
    "    String? secret,\n    String? jamiOwner,\n    String? avatarBase64,",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "jamiOwner: jamiOwner ?? this.jamiOwner,",
    "    ownerId: ownerId,\n    secret: secret ?? this.secret,",
    "    ownerId: ownerId,\n    jamiOwner: jamiOwner ?? this.jamiOwner,\n    secret: secret ?? this.secret,",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "if (jamiOwner != null) 'jamiOwner': jamiOwner,",
    "    'ownerId': ownerId,\n    'secret': secret,",
    "    'ownerId': ownerId,\n    if (jamiOwner != null) 'jamiOwner': jamiOwner,\n    'secret': secret,",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "'jamiOwner': jamiOwner,",
    "      'owner': ownerId,\n      'secret': secret,",
    "      'owner': ownerId,\n      'jamiOwner': jamiOwner,\n      'secret': secret,",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "jamiOwner: map['jamiOwner']?.toString(),",
    "        ownerId: map['owner']?.toString() ?? '',\n        secret: secret,",
    "        ownerId: map['owner']?.toString() ?? '',\n        jamiOwner: map['jamiOwner']?.toString(),\n        secret: secret,",
)
replace_once_if_missing(
    "lib/core_models.dart",
    "jamiOwner: json['jamiOwner']?.toString(),",
    "      ownerId: json['ownerId']?.toString() ?? '',\n      secret:",
    "      ownerId: json['ownerId']?.toString() ?? '',\n      jamiOwner: json['jamiOwner']?.toString(),\n      secret:",
)

replace_once_if_missing(
    "lib/light/light_chat_app.dart",
    "import '../jami_core.dart';",
    "import '../core_models.dart';",
    "import '../core_models.dart';\nimport '../jami_core.dart';",
)
replace_once_if_missing(
    "lib/light/light_chat_app.dart",
    "final identity = await CgJamiBridge.initialize(profile.nickname);",
    """      PackageInfo.fromPlatform(),
    ]);
    if (!mounted) return;""",
    """      PackageInfo.fromPlatform(),
    ]);
    final profile = values[0] as CgProfile;
    var tunnels = values[1] as List<CgTunnel>;
    final identity = await CgJamiBridge.initialize(profile.nickname);
    if (identity != null && identity.address.isNotEmpty) {
      var changed = false;
      tunnels = tunnels.map((tunnel) {
        if (tunnel.ownerId != profile.id ||
            tunnel.jamiOwner?.trim().isNotEmpty == true) {
          return tunnel;
        }
        changed = true;
        return tunnel.copyWith(jamiOwner: identity.address);
      }).toList(growable: false);
      if (changed) await CgStore.saveTunnels(tunnels);
    }
    if (!mounted) return;""",
)
replace_once_if_missing(
    "lib/light/light_chat_app.dart",
    "_profile = profile;",
    "      _profile = values[0] as CgProfile;\n      _chats = values[1] as List<CgTunnel>;",
    "      _profile = profile;\n      _chats = tunnels;",
)
replace_once_if_missing(
    "lib/light/light_chat_app.dart",
    "jamiOwner: CgJamiBridge.address,",
    "      ownerId: profile.id,\n      secret: CgIds.random(42),",
    "      ownerId: profile.id,\n      jamiOwner: CgJamiBridge.address,\n      secret: CgIds.random(42),",
)

replace_once_if_missing(
    "lib/app_monitor.dart",
    "import 'jami_core.dart';",
    "import 'internet_core.dart';",
    "import 'internet_core.dart';\nimport 'jami_core.dart';",
)
replace_once_if_missing(
    "lib/app_monitor.dart",
    "CgJamiRelay.seed(tunnel.id,",
    """    final session = await InternetRelay.open(
      tunnelId: tunnel.id,""",
    """    CgJamiRelay.seed(
      tunnel.id,
      tunnel.ownerId == profile.id ? null : tunnel.jamiOwner,
    );
    final session = await InternetRelay.open(
      tunnelId: tunnel.id,""",
)

replace_once_if_missing(
    "lib/chat_screen.dart",
    "import 'jami_core.dart';",
    "import 'internet_core.dart';",
    "import 'internet_core.dart';\nimport 'jami_core.dart';",
)
replace_once_if_missing(
    "lib/chat_screen.dart",
    "CgJamiRelay.seed(_tunnel.id,",
    """      final session = await InternetRelay.open(
        tunnelId: _tunnel.id,""",
    """      CgJamiRelay.seed(
        _tunnel.id,
        _tunnel.ownerId == widget.profile.id ? null : _tunnel.jamiOwner,
      );
      final session = await InternetRelay.open(
        tunnelId: _tunnel.id,""",
)

replace_once_if_missing(
    "pubspec.yaml",
    "version: 0.79.0+79",
    "version: 0.51.0+74",
    "version: 0.79.0+79",
)

print("Jami 0.79 integration patch applied")
