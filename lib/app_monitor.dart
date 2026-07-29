import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'brand.dart';
import 'call_service.dart';
import 'chat_media.dart';
import 'core_models.dart';
import 'group_call_service.dart';
import 'internet_core.dart';
import 'sound_service.dart';

class CgSignalRegistry {
  static final Set<String> _handled = <String>{};

  static bool claim(String id) {
    if (id.isEmpty || !_handled.add(id)) return false;
    if (_handled.length > 500) _handled.remove(_handled.first);
    return true;
  }
}

class CgMessageSoundRegistry {
  static final Set<String> _played = <String>{};

  static bool claim(String id) {
    if (id.isEmpty || !_played.add(id)) return false;
    if (_played.length > 1000) _played.remove(_played.first);
    return true;
  }
}

class ChernogramAppMonitor {
  static final Map<String, StreamSubscription<InternetEvent>> _subscriptions =
      <String, StreamSubscription<InternetEvent>>{};
  static final Map<String, InternetTunnelSession> _sessions =
      <String, InternetTunnelSession>{};
  static final Map<String, CgTunnel> _tunnels = <String, CgTunnel>{};

  static CgProfile? _profile;
  static bool _ru = true;
  static ValueChanged<CgTunnel>? _onTunnelChanged;
  static ValueChanged<CgContact>? _onContactSeen;
  static bool _dialogOpen = false;

  static Future<void> sync({
    required CgProfile profile,
    required List<CgTunnel> tunnels,
    required bool ru,
    required ValueChanged<CgTunnel> onTunnelChanged,
    required ValueChanged<CgContact> onContactSeen,
  }) async {
    _profile = profile;
    _ru = ru;
    _onTunnelChanged = onTunnelChanged;
    _onContactSeen = onContactSeen;
    _tunnels
      ..clear()
      ..addEntries(tunnels.map((tunnel) => MapEntry(tunnel.id, tunnel)));

    final recent = tunnels.toList()
      ..sort((a, b) {
        final aTime = a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
        final bTime = b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
        return bTime.compareTo(aTime);
      });
    final monitored = recent.take(8).toList(growable: false);
    final activeIds = monitored.map((tunnel) => tunnel.id).toSet();
    final obsolete = _subscriptions.keys
        .where((tunnelId) => !activeIds.contains(tunnelId))
        .toList();
    for (final tunnelId in obsolete) {
      await _subscriptions.remove(tunnelId)?.cancel();
      _sessions.remove(tunnelId);
      // Shared 0.7.3 session may still be used by the visible chat/call.
    }

    await Future.wait(monitored.map(_ensureTunnel));
  }

  static Future<void> _ensureTunnel(CgTunnel tunnel) async {
    final profile = _profile;
    if (profile == null) return;
    final session = await InternetRelay.open(
      tunnelId: tunnel.id,
      secret: tunnel.secret,
      profileId: profile.id,
      nickname: profile.nickname,
      history: tunnel.messages.map((message) => message.toJson()).toList(),
    );
    if (identical(_sessions[tunnel.id], session) &&
        _subscriptions.containsKey(tunnel.id)) {
      return;
    }
    await _subscriptions.remove(tunnel.id)?.cancel();
    _sessions[tunnel.id] = session;
    _subscriptions[tunnel.id] = session.events.listen(
      (event) => _onEvent(tunnel.id, event),
    );
  }

  static void _onEvent(String tunnelId, InternetEvent event) {
    switch (event.type) {
      case 'message':
        final raw = event.data['message'];
        if (raw is Map) {
          _handleMessage(
            tunnelId,
            Map<String, dynamic>.from(raw),
            playSound: true,
          );
        }
        break;
      case 'history':
        final rawMessages = (event.data['messages'] as List?) ?? const [];
        for (final raw in rawMessages.whereType<Map>()) {
          _handleMessage(
            tunnelId,
            Map<String, dynamic>.from(raw),
            playSound: false,
          );
        }
        break;
      case 'peer':
        _rememberContact(
          tunnelId,
          event.data['id']?.toString() ?? '',
          event.data['name']?.toString() ?? 'user',
        );
        break;
      case 'signal':
        unawaited(_handleSignal(tunnelId, event.data));
        break;
      case 'control':
        _handleControl(tunnelId, event.data);
        break;
    }
  }

  static void _handleMessage(
    String tunnelId,
    Map<String, dynamic> raw, {
    required bool playSound,
  }) {
    final profile = _profile;
    final tunnel = _tunnels[tunnelId];
    if (profile == null || tunnel == null) return;
    var message = CgMessage.fromJson(raw);
    if (message.id.isEmpty) return;

    final messages = <CgMessage>[...tunnel.messages];
    final index = messages.indexWhere((item) => item.id == message.id);
    message = CgMediaStore.preserveLocalPurge(
      index < 0 ? null : messages[index],
      message,
    );
    var changed = false;
    if (index < 0) {
      messages.add(message);
      changed = true;
    } else if (jsonEncode(messages[index].toJson()) !=
        jsonEncode(message.toJson())) {
      messages[index] = message;
      changed = true;
    }
    if (changed) {
      final updated = tunnel.copyWith(messages: messages);
      _tunnels[tunnelId] = updated;
      _onTunnelChanged?.call(updated);
    }

    if (message.authorId != profile.id) {
      _rememberContact(tunnelId, message.authorId, message.authorName);
      final fresh =
          DateTime.now().difference(message.sentAt.toLocal()).inSeconds.abs() <=
          30;
      if (playSound && fresh && CgMessageSoundRegistry.claim(message.id)) {
        unawaited(ChernogramSound.playMessage());
      }
    }
  }

  static void _handleControl(String tunnelId, Map<String, dynamic> data) {
    final profile = _profile;
    final tunnel = _tunnels[tunnelId];
    if (profile == null || tunnel == null) return;
    final sender = data['relaySender']?.toString() ?? '';
    final action = data['action']?.toString() ?? '';
    if (action == 'message_delete') {
      final id = data['messageId']?.toString() ?? '';
      final index = tunnel.messages.indexWhere((message) => message.id == id);
      if (index < 0 || tunnel.messages[index].authorId != sender) return;
      final messages = [...tunnel.messages];
      messages[index] = messages[index].copyWith(deleted: true);
      final updated = tunnel.copyWith(messages: messages);
      _tunnels[tunnelId] = updated;
      _onTunnelChanged?.call(updated);
    } else if (action == 'reaction_toggle') {
      final id = data['messageId']?.toString() ?? '';
      final emoji = data['emoji']?.toString() ?? '';
      final index = tunnel.messages.indexWhere((message) => message.id == id);
      if (index < 0 || emoji.isEmpty || sender.isEmpty) return;
      final message = tunnel.messages[index];
      final reactions = <String, List<String>>{
        for (final entry in message.reactions.entries)
          entry.key: [...entry.value],
      };
      final users = reactions.putIfAbsent(emoji, () => <String>[]);
      if (data['add'] == true) {
        if (!users.contains(sender)) users.add(sender);
      } else {
        users.remove(sender);
      }
      if (users.isEmpty) reactions.remove(emoji);
      final messages = [...tunnel.messages];
      messages[index] = message.copyWith(reactions: reactions);
      final updated = tunnel.copyWith(messages: messages);
      _tunnels[tunnelId] = updated;
      _onTunnelChanged?.call(updated);
    } else if (action == 'tunnel_update' && sender == tunnel.ownerId) {
      final revision = int.tryParse(data['revision']?.toString() ?? '') ?? 0;
      if (revision < tunnel.revision) return;
      final updated = tunnel.copyWith(
        name: data['name']?.toString() ?? tunnel.name,
        isPrivate: data['isPrivate'] != false,
        secret: data['secret']?.toString() ?? tunnel.secret,
        avatarBase64: data['avatarBase64']?.toString() ?? tunnel.avatarBase64,
        revision: revision,
      );
      _tunnels[tunnelId] = updated;
      _onTunnelChanged?.call(updated);
      if (updated.secret != tunnel.secret) unawaited(_ensureTunnel(updated));
    }
  }

  static void _rememberContact(String tunnelId, String id, String name) {
    final profile = _profile;
    if (profile == null || id.isEmpty || id == profile.id) return;
    _onContactSeen?.call(
      CgContact(
        id: id,
        nickname: name.trim().isEmpty ? 'user' : name,
        lastSeenAt: DateTime.now(),
        tunnelIds: <String>[tunnelId],
      ),
    );
  }

  static Future<void> _handleSignal(
    String tunnelId,
    Map<String, dynamic> signal,
  ) async {
    final action = signal['action']?.toString() ?? '';
    if (action != 'call_invite' && action != 'group_call_invite') return;
    final callId = signal['callId']?.toString() ?? '';
    final from =
        signal['from']?.toString() ?? signal['relaySender']?.toString() ?? '';
    final profile = _profile;
    final tunnel = _tunnels[tunnelId];
    if (profile == null ||
        tunnel == null ||
        from.isEmpty ||
        from == profile.id ||
        !CgSignalRegistry.claim(callId) ||
        _dialogOpen) {
      return;
    }
    final fromName =
        signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        (_ru ? 'Собеседник' : 'Peer');
    final video = signal['video'] == true;
    final group = action == 'group_call_invite';
    _rememberContact(tunnelId, from, fromName);

    final context = chernogramNavigatorKey.currentContext;
    if (context == null) return;
    _dialogOpen = true;
    await ChernogramSound.startIncomingCall(video: video);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          group
              ? Icons.groups_2_rounded
              : video
              ? Icons.videocam_rounded
              : Icons.call_rounded,
          size: 40,
        ),
        title: Text(
          group
              ? (video
                    ? (_ru ? 'Групповой видеозвонок' : 'Group video call')
                    : (_ru ? 'Групповой звонок' : 'Group call'))
              : (video
                    ? (_ru ? 'Видеозвонок' : 'Video call')
                    : (_ru ? 'Аудиозвонок' : 'Audio call')),
        ),
        content: Text(
          group
              ? (_ru
                    ? '$fromName приглашает в звонок до 6 участников.'
                    : '$fromName invites you to a call for up to 6 participants.')
              : (_ru ? '$fromName звонит вам' : '$fromName is calling you'),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: <Widget>[
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            icon: const Icon(Icons.call_end_rounded),
          ),
          const SizedBox(width: 20),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: ChernogramColors.success,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call_rounded),
          ),
        ],
      ),
    );
    await ChernogramSound.stopIncomingCall();
    _dialogOpen = false;

    final session = _sessions[tunnelId];
    if (accepted != true) {
      if (!group) {
        await session?.sendSignal(<String, dynamic>{
          'action': 'call_decline',
          'callId': callId,
          'from': profile.id,
          'target': from,
        });
      }
      _appendLocalCallEvent(
        tunnelId: tunnelId,
        authorId: from,
        authorName: fromName,
        video: video,
        group: group,
        status: 'missed',
        durationSeconds: 0,
        participants: group ? 1 : 2,
      );
      return;
    }

    final navigator = chernogramNavigatorKey.currentState;
    if (navigator == null) return;
    final outcome = await navigator.push<CgCallOutcome>(
      MaterialPageRoute<CgCallOutcome>(
        builder: (_) => group
            ? ChernogramGroupCallScreen(
                tunnelName: tunnel.displayName,
                tunnelId: tunnel.id,
                secret: tunnel.secret,
                profileId: profile.id,
                nickname: profile.nickname,
                callId: callId,
                isHost: false,
                video: video,
                ru: _ru,
              )
            : ChernogramCallScreen(
                tunnelName: tunnel.displayName,
                tunnelId: tunnel.id,
                secret: tunnel.secret,
                profileId: profile.id,
                nickname: profile.nickname,
                peerId: from,
                peerName: fromName,
                callId: callId,
                isCaller: false,
                video: video,
                ru: _ru,
              ),
      ),
    );
    if (outcome != null) {
      _appendLocalCallEvent(
        tunnelId: tunnelId,
        authorId: from,
        authorName: fromName,
        video: video,
        group: group,
        status: outcome.status,
        durationSeconds: outcome.durationSeconds,
        participants: group ? 2 : 2,
      );
    }
  }

  static void _appendLocalCallEvent({
    required String tunnelId,
    required String authorId,
    required String authorName,
    required bool video,
    required bool group,
    required String status,
    required int durationSeconds,
    required int participants,
  }) {
    final tunnel = _tunnels[tunnelId];
    if (tunnel == null) return;
    final message = CgMessage(
      id: CgIds.random(24),
      authorId: authorId,
      authorName: authorName,
      text: '',
      sentAt: DateTime.now(),
      type: 'call',
      meta: <String, dynamic>{
        'video': video,
        'group': group,
        'status': status,
        'durationSeconds': durationSeconds,
        'participants': participants,
      },
    );
    final updated = tunnel.copyWith(
      messages: <CgMessage>[...tunnel.messages, message],
    );
    _tunnels[tunnelId] = updated;
    _onTunnelChanged?.call(updated);
  }

  static Future<void> publishMessage({
    required CgProfile profile,
    required CgTunnel tunnel,
    required CgMessage message,
  }) async {
    _profile ??= profile;
    _tunnels[tunnel.id] = tunnel;
    await _ensureTunnel(tunnel);
    final session = _sessions[tunnel.id];
    if (session == null) {
      throw StateError('Room transport is unavailable');
    }
    session.replaceHistory(
      tunnel.messages.map((item) => item.toJson()).toList(),
    );
    await session.sendMessage(message.toJson());
  }

  static Future<void> stop() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _sessions.clear();
    _tunnels.clear();
    await ChernogramSound.stopIncomingCall();
  }
}
