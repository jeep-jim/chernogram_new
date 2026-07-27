from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    Path(path).write_text(source, encoding='utf-8')


def patch_main() -> bool:
    path = Path('lib/main.dart')
    source = read(str(path))
    original = source
    if "import 'background_realtime_service.dart';" not in source:
        source = source.replace(
            "import 'brand.dart';\n",
            "import 'background_realtime_service.dart';\nimport 'brand.dart';\n",
            1,
        )
    if 'await initializeChernogramRealtimeService();' not in source:
        source = source.replace(
            '  await CgNotificationService.initialize();\n',
            '  await CgNotificationService.initialize();\n'
            '  await initializeChernogramRealtimeService();\n',
            1,
        )
    if source != original:
        write(str(path), source)
        return True
    return False


def patch_v12() -> bool:
    path = Path('lib/v12.dart')
    source = read(str(path))
    original = source

    imports = {
        "import 'call_service.dart';": "import 'brand.dart';\n",
        "import 'group_call_service.dart';": "import 'core_models.dart';\n",
        "import 'pending_call.dart';": "import 'notification_service.dart';\n",
    }
    for statement, marker in imports.items():
        if statement not in source and marker in source:
            source = source.replace(marker, marker + statement + '\n', 1)

    if '_callClickSubscription' not in source:
        source = source.replace(
            '  StreamSubscription<String>? _notificationClickSubscription;\n',
            '  StreamSubscription<String>? _notificationClickSubscription;\n'
            '  StreamSubscription<String>? _callClickSubscription;\n',
            1,
        )

    listener = """    _notificationClickSubscription =
        CgNotificationService.tunnelClicks.listen(_openNotificationTunnel);
"""
    if '_callClickSubscription =' not in source and listener in source:
        source = source.replace(
            listener,
            listener
            + """    _callClickSubscription =
        CgNotificationService.callClicks.listen(_openPendingCall);
""",
            1,
        )

    permission_marker = """    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(CgPermissionCenter.maybePrompt(context, ru: widget.ru));
    });
"""
    if 'consumePendingCallId()' not in source and permission_marker in source:
        source = source.replace(
            permission_marker,
            """    final pendingCallId = CgNotificationService.consumePendingCallId();
    if (pendingCallId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openPendingCall(pendingCallId));
      });
    }
"""
            + permission_marker,
            1,
        )

    method_marker = """  Future<void> _openNotificationTunnel(String tunnelId) async {
    final index = _tunnels.indexWhere((item) => item.id == tunnelId);
    if (index < 0 || !mounted) return;
    await _openTunnel(_tunnels[index]);
  }
"""
    if 'Future<void> _openPendingCall(String callId)' not in source and method_marker in source:
        source = source.replace(
            method_marker,
            method_marker
            + """
  Future<void> _openPendingCall(String callId) async {
    final pending = await CgPendingCallStore.take(callId);
    final profile = _profile;
    if (pending == null || profile == null || !mounted) return;
    final index = _tunnels.indexWhere((item) => item.id == pending.tunnelId);
    if (index < 0) return;
    final tunnel = _tunnels[index];
    await CgNotificationService.cancelCall(callId);
    if (!mounted) return;
    if (pending.group) {
      await Navigator.push<CgCallOutcome>(
        context,
        MaterialPageRoute(
          builder: (_) => ChernogramGroupCallScreen(
            tunnelName: tunnel.displayName,
            tunnelId: tunnel.id,
            secret: tunnel.secret,
            profileId: profile.id,
            nickname: profile.nickname,
            callId: pending.callId,
            isHost: false,
            video: pending.video,
            ru: widget.ru,
            myAvatarBase64: profile.avatarBase64,
          ),
        ),
      );
      return;
    }
    await Navigator.push<CgCallOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ChernogramCallScreen(
          tunnelName: tunnel.displayName,
          tunnelId: tunnel.id,
          secret: tunnel.secret,
          profileId: profile.id,
          nickname: profile.nickname,
          peerId: pending.fromId,
          peerName: pending.fromName,
          peerAvatarBase64: pending.avatarBase64,
          myAvatarBase64: profile.avatarBase64,
          callId: pending.callId,
          isCaller: false,
          video: pending.video,
          ru: widget.ru,
        ),
      ),
    );
  }
""",
            1,
        )

    if '_callClickSubscription?.cancel()' not in source:
        source = source.replace(
            '    unawaited(_notificationClickSubscription?.cancel());\n',
            '    unawaited(_notificationClickSubscription?.cancel());\n'
            '    unawaited(_callClickSubscription?.cancel());\n',
            1,
        )

    contacts_at = source.find('class _V12ContactsScreen')
    profile_at = source.find('class _V12ProfileScreen', contacts_at)
    if contacts_at >= 0 and profile_at > contacts_at:
        before = source[:contacts_at]
        contacts = source[contacts_at:profile_at]
        after = source[profile_at:]
        if 'margin: const EdgeInsets.only(bottom: 2)' not in contacts:
            contacts = contacts.replace(
                '            Card(\n',
                '            Card(\n              margin: const EdgeInsets.only(bottom: 2),\n',
            )
        source = before + contacts + after

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_notification_permissions() -> bool:
    path = Path('lib/permission_center.dart')
    source = read(str(path))
    original = source
    if "import 'notification_service.dart';" not in source:
        source = source.replace(
            "import 'package:shared_preferences/shared_preferences.dart';\n",
            "import 'package:shared_preferences/shared_preferences.dart';\n\n"
            "import 'notification_service.dart';\n",
            1,
        )
    if 'requestCallPermissions' not in source:
        source = source.replace(
            "    final permissions = <Permission>[\n",
            "    await CgNotificationService.requestCallPermissions();\n"
            "    final permissions = <Permission>[\n",
            1,
        )
    if source != original:
        write(str(path), source)
        return True
    return False


def patch_chat_screen() -> bool:
    path = Path('lib/chat_screen.dart')
    source = read(str(path))
    original = source

    if 'String? get _preferredPeerId' not in source:
        marker = "  bool get _canCall => _isOwner || _tunnel.permissions.canCall;\n"
        helper = marker + """
  String? get _preferredPeerId {
    for (final message in _tunnel.messages.reversed) {
      final id = message.authorId.trim();
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
"""
        source = source.replace(marker, helper, 1)

    old_start = """  Future<void> _startCall(bool video) async {
    if (!_canCall || await _session?.waitUntilConnected() != true) {
      _showNotConnected();
      return;
    }
"""
    new_start = """  Future<void> _startCall(bool video) async {
    if (!_canCall) return;
    unawaited(_session?.connect());
"""
    if old_start in source:
        source = source.replace(old_start, new_start, 1)

    caller_marker = """          nickname: widget.profile.nickname,
          peerAvatarBase64: _tunnel.avatarBase64,
"""
    if 'peerId: _preferredPeerId' not in source and caller_marker in source:
        source = source.replace(
            caller_marker,
            """          nickname: widget.profile.nickname,
          peerId: _preferredPeerId,
          peerName: _preferredPeerName,
          peerAvatarBase64: _tunnel.avatarBase64,
""",
            1,
        )

    decline_old = """    if (accepted != true) {
      await _session?.sendSignal({
        'action': 'call_decline',
        'callId': callId,
        'from': widget.profile.id,
        'target': fromId,
      });
      return;
    }
"""
    decline_new = """    if (accepted != true) {
      unawaited(_session?.sendSignal({
        'action': 'call_decline',
        'callId': callId,
        'from': widget.profile.id,
        'target': fromId,
      }));
      return;
    }
"""
    if decline_old in source:
        source = source.replace(decline_old, decline_new, 1)

    source = source.replace(
        """            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.danger,
            ),
""",
        """            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.danger,
              shape: const CircleBorder(),
              fixedSize: const Size.square(54),
            ),
""",
    )
    source = source.replace(
        """            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.success,
            ),
""",
        """            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.success,
              shape: const CircleBorder(),
              fixedSize: const Size.square(54),
            ),
""",
    )

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_call_service() -> bool:
    path = Path('lib/call_service.dart')
    source = read(str(path))
    original = source

    early_marker = """      _session = session;
      _signalSubscription = session.events.listen(_onRelayEvent);

      final stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
"""
    early_block = """      _session = session;
      _signalSubscription = session.events.listen(_onRelayEvent);

      if (widget.isCaller) {
        unawaited(_sendInvite());
        _inviteTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
          if (_connectedAt == null && !_ended) unawaited(_sendInvite());
        });
        if (mounted) setState(() => _status = widget.ru ? 'Звоним…' : 'Calling…');
      } else {
        unawaited(_sendReady());
        _readyTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
          if (!_remoteDescriptionSet && !_ended) unawaited(_sendReady());
        });
        if (mounted) {
          setState(() => _status = widget.ru ? 'Принимаем звонок…' : 'Answering…');
        }
      }

      final stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
"""
    if early_marker in source and 'Timer.periodic(const Duration(milliseconds: 700)' not in source:
        source = source.replace(early_marker, early_block, 1)

    late_block = """      if (widget.isCaller) {
        await _sendInvite();
        _inviteTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (_connectedAt == null && _peerId == null && !_ended) {
            unawaited(_sendInvite());
          }
        });
        if (mounted) setState(() => _status = widget.ru ? 'Звоним…' : 'Calling…');
      } else {
        await _sendReady();
        _readyTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (!_remoteDescriptionSet && !_ended) unawaited(_sendReady());
        });
        if (mounted) {
          setState(() => _status = widget.ru ? 'Принимаем звонок…' : 'Answering…');
        }
      }

"""
    if late_block in source:
        source = source.replace(late_block, '', 1)

    source = source.replace(
        'Timer.periodic(const Duration(milliseconds: 2500)',
        'Timer.periodic(const Duration(milliseconds: 850)',
    )
    source = source.replace(
        """      case 'call_decline':
        if (mounted) {
          setState(() => _status = widget.ru ? 'Звонок отклонён' : 'Call declined');
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _finish('declined');
          });
        }
        break;
""",
        """      case 'call_decline':
        if (mounted) _finish('declined');
        break;
""",
    )
    source = source.replace(
        """      case 'call_end':
        if (mounted) {
          setState(() => _status = widget.ru ? 'Звонок завершён' : 'Call ended');
          Future<void>.delayed(const Duration(milliseconds: 250), () {
            if (mounted) _finish(_connectedAt == null ? 'missed' : 'completed');
          });
        }
        break;
""",
        """      case 'call_end':
        if (mounted) _finish(_connectedAt == null ? 'missed' : 'completed');
        break;
""",
    )

    style_old = """        style: IconButton.styleFrom(
          backgroundColor: danger
"""
    style_new = """        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          fixedSize: const Size.square(58),
          padding: EdgeInsets.zero,
          backgroundColor: danger
"""
    if style_old in source:
        source = source.replace(style_old, style_new, 1)

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_group_call() -> bool:
    path = Path('lib/group_call_service.dart')
    source = read(str(path))
    original = source
    old = """  Future<void> _hangUp() async {
    if (_ended) return;
    await _send({'action': 'group_leave'});
    _finish();
  }
"""
    new = """  Future<void> _hangUp() async {
    if (_ended) return;
    unawaited(
      _send({'action': 'group_leave'})
          .timeout(const Duration(milliseconds: 700))
          .catchError((_) {}),
    );
    _finish();
  }
"""
    if old in source:
        source = source.replace(old, new, 1)
    if source != original:
        write(str(path), source)
        return True
    return False


def patch_internet_core() -> bool:
    path = Path('lib/internet_core.dart')
    source = read(str(path))
    original = source
    source = source.replace(
        "const Duration(seconds: 6),\n      );\n      if (_closed)",
        "const Duration(milliseconds: 3200),\n      );\n      if (_closed)",
        1,
    )

    old_loop = """    String? successfulHost;
    Object? lastError;
    for (final host in orderedHosts) {
      try {
        await _publishEncrypted(host, encrypted, cache: kind != 'presence');
        successfulHost = host;
        break;
      } catch (error) {
        lastError = error;
        _scheduleHostReconnect(host);
      }
    }
"""
    new_loop = """    String? successfulHost;
    Object? lastError;
    if (kind == 'signal') {
      successfulHost = await _publishSignalFast(orderedHosts, encrypted);
    } else {
      for (final host in orderedHosts) {
        try {
          await _publishEncrypted(
            host,
            encrypted,
            cache: kind != 'presence',
            priority: kind == 'presence' ? 'min' : 'default',
          );
          successfulHost = host;
          break;
        } catch (error) {
          lastError = error;
          _scheduleHostReconnect(host);
        }
      }
    }
"""
    if old_loop in source:
        source = source.replace(old_loop, new_loop, 1)

    backup_old = """          _publishEncrypted(backup, encrypted, cache: true).catchError((_) {}),
"""
    backup_new = """          _publishEncrypted(
            backup,
            encrypted,
            cache: true,
            priority: kind == 'signal' ? 'urgent' : 'default',
          ).catchError((_) {}),
"""
    if backup_old in source:
        source = source.replace(backup_old, backup_new, 1)

    method_marker = """  Future<void> _publishEncrypted(
    String host,
    String encrypted, {
    required bool cache,
  }) async {
"""
    if 'Future<String?> _publishSignalFast' not in source and method_marker in source:
        fast = """  Future<String?> _publishSignalFast(
    List<String> hosts,
    String encrypted,
  ) async {
    final selected = hosts.take(4).toList(growable: false);
    if (selected.isEmpty) return null;
    final completer = Completer<String?>();
    var completed = 0;
    for (final host in selected) {
      unawaited(
        _publishEncrypted(
          host,
          encrypted,
          cache: true,
          priority: 'urgent',
          timeout: const Duration(milliseconds: 2600),
        ).then((_) {
          if (!completer.isCompleted) completer.complete(host);
        }).catchError((Object error) {
          completed++;
          _scheduleHostReconnect(host);
          if (completed >= selected.length && !completer.isCompleted) {
            completer.complete(null);
          }
        }),
      );
    }
    return completer.future.timeout(
      const Duration(milliseconds: 2800),
      onTimeout: () => null,
    );
  }

"""
        source = source.replace(method_marker, fast + method_marker, 1)

    source = source.replace(
        """  Future<void> _publishEncrypted(
    String host,
    String encrypted, {
    required bool cache,
  }) async {
""",
        """  Future<void> _publishEncrypted(
    String host,
    String encrypted, {
    required bool cache,
    String priority = 'default',
    Duration timeout = const Duration(seconds: 8),
  }) async {
""",
        1,
    )
    source = source.replace("'Priority': 'min',", "'Priority': priority,", 1)
    source = source.replace(
        ").timeout(const Duration(seconds: 15));",
        ").timeout(timeout);",
        1,
    )

    if source != original:
        write(str(path), source)
        return True
    return False


def patch_sound_service() -> bool:
    path = Path('lib/sound_service.dart')
    source = r'''import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class ChernogramSound {
  static const MethodChannel _channel = MethodChannel('chernogram/sound');
  static AudioPlayer? _incomingPlayer;

  static Future<void> playMessage() async {
    try {
      await _channel.invokeMethod<void>('playMessage');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> startIncomingCall({required bool video}) async {
    await stopIncomingCall();
    var customStarted = false;
    try {
      final player = AudioPlayer();
      _incomingPlayer = player;
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1.0);
      await player.setAsset('assets/audio/chernogram_incoming.mp3');
      unawaited(player.play());
      customStarted = true;
    } catch (_) {
      await _incomingPlayer?.dispose();
      _incomingPlayer = null;
    }
    try {
      await _channel.invokeMethod<void>(
        'startIncomingCall',
        <String, dynamic>{'video': video, 'customSound': customStarted},
      );
    } catch (_) {
      if (!customStarted) await SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> stopIncomingCall() async {
    final player = _incomingPlayer;
    _incomingPlayer = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      await player.dispose();
    }
    try {
      await _channel.invokeMethod<void>('stopIncomingCall');
    } catch (_) {}
  }
}
'''
    old = path.read_text(encoding='utf-8')
    if old == source:
        return False
    path.write_text(source, encoding='utf-8')
    return True


def patch_media_spacing() -> bool:
    path = Path('lib/chat_media.dart')
    source = read(str(path))
    original = source
    marker = """                           return Padding(
                             padding: const EdgeInsets.only(bottom: 2),
"""
    if marker not in source:
        source = source.replace(
            """                           return Card(
                             child: ListTile(
""",
            """                           return Padding(
                             padding: const EdgeInsets.only(bottom: 2),
                             child: Card(
                               margin: EdgeInsets.zero,
                               child: ListTile(
""",
            1,
        )
        start = source.find('return Padding(\n                             padding: const EdgeInsets.only(bottom: 2)')
        if start >= 0:
            end = source.find('                           );', start)
            if end >= 0:
                source = source[:end] + '                             ),\n                           );' + source[end + len('                           );'):]
    else:
        source = source.replace(
            '                             child: Card(\n',
            '                             child: Card(\n                               margin: EdgeInsets.zero,\n',
            1,
        )
    if source != original:
        write(str(path), source)
        return True
    return False


def patch_manifest() -> bool:
    path = Path('android/app/src/main/AndroidManifest.xml')
    source = read(str(path))
    original = source
    required = [
        '    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />',
        '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />',
    ]
    for permission in required:
        if permission not in source:
            source = source.replace(
                '    <uses-permission android:name="android.permission.INTERNET" />',
                '    <uses-permission android:name="android.permission.INTERNET" />\n' + permission,
                1,
            )
    service = """        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:exported="false"
            android:stopWithTask="false"
            android:foregroundServiceType="dataSync" />

"""
    if 'id.flutter.flutter_background_service.BackgroundService' not in source:
        source = source.replace('        <service\n            android:name="com.ryanheise.audioservice.AudioService"', service + '        <service\n            android:name="com.ryanheise.audioservice.AudioService"', 1)
    if source != original:
        write(str(path), source)
        return True
    return False


def main() -> None:
    changed = False
    changed |= patch_main()
    changed |= patch_v12()
    changed |= patch_notification_permissions()
    changed |= patch_chat_screen()
    changed |= patch_call_service()
    changed |= patch_group_call()
    changed |= patch_internet_core()
    changed |= patch_sound_service()
    changed |= patch_media_spacing()
    changed |= patch_manifest()
    print('Applied Chernogram 0.16.3 realtime call and background fixes' if changed else 'Chernogram 0.16.3 realtime fixes already applied')


if __name__ == '__main__':
    main()
