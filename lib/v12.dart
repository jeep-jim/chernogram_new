import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing2/qrcode.dart';

import 'agent_screen.dart';
import 'app_monitor.dart';
import 'brand.dart';
import 'call_service.dart';
import 'chat_media.dart';
import 'chat_screen.dart';
import 'crash_reporter.dart';
import 'core_models.dart';
import 'device_contacts_screen.dart';
import 'group_call_service.dart';
import 'music_player.dart';
import 'notification_service.dart';
import 'pending_call.dart';
import 'permission_center.dart';
import 'internet_core.dart';

const String _androidInstallUrl =
    'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/chernogram.apk';

String _encodeStoredJson(Object value) => jsonEncode(value);

Future<void> _saveTunnelsFast(List<CgTunnel> tunnels) async {
  final payload = tunnels.map((item) => item.toJson()).toList(growable: false);
  final encoded = await compute(_encodeStoredJson, payload);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(CgStore.tunnelsKey, encoded);
}

Future<void> _saveContactsFast(List<CgContact> contacts) async {
  final payload = contacts.map((item) => item.toJson()).toList(growable: false);
  final encoded = await compute(_encodeStoredJson, payload);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(CgStore.contactsKey, encoded);
}

Future<String?> _decodeQrImage(Uint8List bytes) {
  return compute(_decodeQrImageInBackground, bytes);
}

String? _decodeQrImageInBackground(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = img.bakeOrientation(decoded);

  for (final order in <img.ChannelOrder>[
    img.ChannelOrder.rgba,
    img.ChannelOrder.abgr,
  ]) {
    final pixels = image
        .convert(numChannels: 4)
        .getBytes(order: order)
        .buffer
        .asInt32List();
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    for (final luminance in <LuminanceSource>[source, source.invert()]) {
      for (final hybrid in <bool>[true, false]) {
        try {
          final bitmap = BinaryBitmap(
            hybrid
                ? HybridBinarizer(luminance)
                : GlobalHistogramBinarizer(luminance),
          );
          final value = QRCodeReader().decode(bitmap).text.trim();
          if (value.isNotEmpty) return value;
        } catch (_) {
          // Try another decoder variant.
        }
      }
    }
  }
  return null;
}

const Set<String> _blockedNicknameRoots = <String>{
  'admin',
  'administrator',
  'support',
  'moderator',
  'security',
  'system',
  'official',
  'chernogram',
  'чернограм',
  'админ',
  'администратор',
  'поддержка',
  'модератор',
  'безопасность',
  'система',
  'официальный',
};

String _nicknameKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s._\-]+'), '')
    .replaceAll('0', 'о')
    .replaceAll('1', 'і');

String? _nicknameError(String value, bool ru) {
  final nickname = value.trim().toLowerCase();
  if (nickname.length < 3 || nickname.length > 24) {
    return ru ? 'Никнейм: от 3 до 24 символов.' : 'Use 3 to 24 characters.';
  }
  if (RegExp(r'[а-яё]', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Кириллица в никнеймах запрещена. Используйте латиницу.'
        : 'Cyrillic letters are not allowed. Use Latin letters.';
  }
  if (!RegExp(r'^[a-z0-9_.-]+$', caseSensitive: false).hasMatch(nickname)) {
    return ru
        ? 'Допустимы латинские буквы, цифры, точка, дефис и подчёркивание.'
        : 'Use Latin letters, digits, dot, dash or underscore.';
  }
  final key = _nicknameKey(nickname);
  for (final root in _blockedNicknameRoots) {
    if (key.contains(_nicknameKey(root))) {
      return ru ? 'Этот никнейм зарезервирован.' : 'This nickname is reserved.';
    }
  }
  return null;
}

String _directPairToken(String left, String right) {
  final ids = <String>[left, right]..sort();
  return base64Url
      .encode(utf8.encode('direct-v1:${ids[0]}:${ids[1]}'))
      .replaceAll('=', '');
}

String _directTunnelId(String left, String right) =>
    'dm_${_directPairToken(left, right)}';

String _directTunnelSecret(String left, String right) =>
    'dm-secret-${_directPairToken(left, right)}';

class ChernogramV12 extends StatefulWidget {
  final bool ru;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onChangeLanguage;
  final VoidCallback onCheckUpdates;

  const ChernogramV12({
    super.key,
    required this.ru,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onChangeLanguage,
    required this.onCheckUpdates,
  });

  @override
  State<ChernogramV12> createState() => _ChernogramV12State();
}

class _ChernogramV12State extends State<ChernogramV12> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<String>? _notificationClickSubscription;
  StreamSubscription<String>? _callClickSubscription;
  Timer? _saveTunnelsTimer;
  Timer? _saveContactsTimer;
  Timer? _presenceRefreshTimer;
  CgProfile? _profile;
  List<CgTunnel> _tunnels = <CgTunnel>[];
  List<CgContact> _contacts = <CgContact>[];
  bool _loading = true;
  bool _privacyLens = false;
  int _tab = 0;
  String? _activeTunnelId;
  Map<String, int> _unreadCounts = <String, int>{};
  final Map<String, int> _onlineByTunnel = <String, int>{};
  final Set<String> _onlineContactIds = <String>{};
  final Map<String, StreamSubscription<InternetEvent>> _relaySubscriptions =
      <String, StreamSubscription<InternetEvent>>{};

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final values = await Future.wait<Object>([
      CgStore.loadOrCreateProfile(),
      CgStore.loadTunnels(),
      CgStore.loadContacts(),
      CgStore.loadPrivacyLens(),
    ]);
    var profile = values[0] as CgProfile;
    if (_nicknameError(profile.nickname, true) != null) {
      profile = profile.copyWith(
        nickname: 'user_${CgIds.random(4).toLowerCase()}',
      );
      await CgStore.saveProfile(profile);
    }
    final prefs = await SharedPreferences.getInstance();
    final unread = <String, int>{};
    final unreadRaw = prefs.getString('cg_unread_v2');
    if (unreadRaw != null) {
      try {
        final decoded = jsonDecode(unreadRaw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            unread[entry.key.toString()] =
                int.tryParse(entry.value.toString()) ?? 0;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _tunnels = values[1] as List<CgTunnel>;
      _contacts = values[2] as List<CgContact>;
      _privacyLens = values[3] as bool;
      _unreadCounts = unread;
      _loading = false;
    });
    await _listenLinks();
    _notificationClickSubscription = CgNotificationService.tunnelClicks.listen(
      _openNotificationTunnel,
    );
    _callClickSubscription = CgNotificationService.callClicks.listen(
      _openPendingCall,
    );
    final pendingTunnelId = CgNotificationService.consumePendingTunnelId();
    if (pendingTunnelId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openNotificationTunnel(pendingTunnelId));
      });
    }
    final pendingCallId = CgNotificationService.consumePendingCallId();
    if (pendingCallId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openPendingCall(pendingCallId));
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        unawaited(CgPermissionCenter.maybePrompt(context, ru: widget.ru));
    });
    unawaited(_prewarmAll());
    unawaited(_syncAppMonitor());
    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshAllPresence(),
    );
  }

  Future<void> _openNotificationTunnel(String tunnelId) async {
    final index = _tunnels.indexWhere((item) => item.id == tunnelId);
    if (index < 0 || !mounted) return;
    await _openTunnel(_tunnels[index]);
  }

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

  Future<void> _persistUnread() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cg_unread_v2', jsonEncode(_unreadCounts));
  }

  void _markRead(String tunnelId) {
    if ((_unreadCounts[tunnelId] ?? 0) == 0) return;
    _unreadCounts[tunnelId] = 0;
    if (mounted) setState(() {});
    unawaited(_persistUnread());
  }

  void _refreshPresence([String? tunnelId]) {
    var changed = false;
    if (tunnelId != null) {
      final session = InternetRelay.session(tunnelId);
      final online = session == null
          ? 0
          : session.members.where((member) => member['self'] != true).length;
      if (_onlineByTunnel[tunnelId] != online) {
        _onlineByTunnel[tunnelId] = online;
        changed = true;
      }
    }

    final activeTunnelIds = _tunnels.map((item) => item.id).toSet();
    for (final id
        in _onlineByTunnel.keys
            .where((id) => !activeTunnelIds.contains(id))
            .toList()) {
      _onlineByTunnel.remove(id);
      changed = true;
    }

    final onlineContactIds = <String>{};
    for (final tunnel in _tunnels) {
      final session = InternetRelay.session(tunnel.id);
      if (session == null) continue;
      for (final member in session.members) {
        if (member['self'] == true) continue;
        final id = member['id']?.toString() ?? '';
        if (id.isNotEmpty) onlineContactIds.add(id);
      }
    }
    final contactsChanged =
        onlineContactIds.length != _onlineContactIds.length ||
        !_onlineContactIds.containsAll(onlineContactIds);
    if (contactsChanged) {
      _onlineContactIds
        ..clear()
        ..addAll(onlineContactIds);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _refreshAllPresence() {
    final nextByTunnel = <String, int>{};
    final nextContacts = <String>{};
    for (final tunnel in _tunnels) {
      final session = InternetRelay.session(tunnel.id);
      if (session == null) continue;
      final peers = session.members.where((member) => member['self'] != true);
      var count = 0;
      for (final member in peers) {
        final id = member['id']?.toString() ?? '';
        if (id.isEmpty || id == _profile?.id) continue;
        count++;
        nextContacts.add(id);
      }
      if (count > 0) nextByTunnel[tunnel.id] = count;
    }
    final tunnelChanged =
        nextByTunnel.length != _onlineByTunnel.length ||
        nextByTunnel.entries.any(
          (entry) => _onlineByTunnel[entry.key] != entry.value,
        );
    final contactsChanged =
        nextContacts.length != _onlineContactIds.length ||
        !_onlineContactIds.containsAll(nextContacts);
    if (!tunnelChanged && !contactsChanged) return;
    _onlineByTunnel
      ..clear()
      ..addAll(nextByTunnel);
    _onlineContactIds
      ..clear()
      ..addAll(nextContacts);
    if (mounted) setState(() {});
  }

  Future<void> _syncAppMonitor() async {
    final profile = _profile;
    if (profile == null) return;
    await ChernogramAppMonitor.sync(
      profile: profile,
      tunnels: _tunnels,
      ru: widget.ru,
      onTunnelChanged: _updateTunnel,
      onContactSeen: _rememberContact,
    );
    _refreshAllPresence();
  }

  Future<void> _prewarmAll() async {
    final profile = _profile;
    if (profile == null) return;
    for (final subscription in _relaySubscriptions.values) {
      await subscription.cancel();
    }
    _relaySubscriptions.clear();
    for (final tunnel in _tunnels) {
      final session = await InternetRelay.open(
        tunnelId: tunnel.id,
        secret: tunnel.secret,
        profileId: profile.id,
        nickname: profile.nickname,
        history: tunnel.historyJson(),
      );
      _relaySubscriptions[tunnel.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(tunnel.id, event)),
      );
      _refreshAllPresence();
      _refreshPresence(tunnel.id);
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': profile.nickname,
          if (profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': profile.avatarBase64,
        }),
      );
    }
  }

  Future<void> _handleBackgroundEvent(
    String tunnelId,
    InternetEvent event,
  ) async {
    if (event.type == 'control' &&
        event.data['action']?.toString() == 'profile_card') {
      final contactId = event.data['relaySender']?.toString() ?? '';
      if (contactId.isNotEmpty && contactId != _profile?.id) {
        _rememberContact(
          CgContact(
            id: contactId,
            nickname:
                event.data['nickname']?.toString() ??
                event.data['relaySenderName']?.toString() ??
                'user',
            lastSeenAt: DateTime.now(),
            tunnelIds: <String>[tunnelId],
            avatarBase64: event.data['avatarBase64']?.toString(),
          ),
        );
      }
      return;
    }
    if (event.type != 'message' || event.data['message'] is! Map) return;
    final raw = Map<String, dynamic>.from(event.data['message'] as Map);
    final incoming = await CgMediaStore.cacheIncomingMessage(
      CgMessage.fromJson(raw),
    );
    if (incoming.authorId != _profile?.id) {
      final tunnelIndexForNotification = _tunnels.indexWhere(
        (item) => item.id == tunnelId,
      );
      final notificationTitle = tunnelIndexForNotification < 0
          ? (widget.ru ? 'Новое сообщение' : 'New message')
          : _tunnels[tunnelIndexForNotification].displayName;
      final body = incoming.text.trim().isNotEmpty
          ? '${incoming.authorName}: ${incoming.text.trim()}'
          : '${incoming.authorName}: ${incoming.attachment?.name ?? (widget.ru ? 'Новое сообщение' : 'New message')}';
      unawaited(
        CgNotificationService.showMessage(
          messageId: incoming.id,
          tunnelId: tunnelId,
          title: notificationTitle,
          body: body,
        ),
      );
    }
    if (incoming.authorId.isNotEmpty && incoming.authorId != _profile?.id) {
      _rememberContact(
        CgContact(
          id: incoming.authorId,
          nickname: incoming.authorName.trim().isEmpty
              ? 'user'
              : incoming.authorName,
          lastSeenAt: DateTime.now(),
          tunnelIds: <String>[tunnelId],
          avatarBase64: incoming.meta['authorAvatarBase64']?.toString(),
        ),
      );
    }
    if (!mounted) return;
    final tunnelIndex = _tunnels.indexWhere((item) => item.id == tunnelId);
    if (tunnelIndex < 0) return;
    final tunnel = _tunnels[tunnelIndex];
    final messageIndex = tunnel.messages.indexWhere(
      (message) => message.id == incoming.id,
    );
    if (messageIndex >= 0 &&
        tunnel.messages[messageIndex].sameVisibleContent(incoming)) {
      return;
    }
    final messages = <CgMessage>[...tunnel.messages];
    if (messageIndex < 0) {
      messages.add(incoming);
    } else {
      messages[messageIndex] = incoming;
    }
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final updated = tunnel.copyWith(messages: messages);
    final copy = <CgTunnel>[..._tunnels];
    copy[tunnelIndex] = updated;
    copy.sort((a, b) {
      final aTime = a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
      final bTime = b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
      return bTime.compareTo(aTime);
    });
    _tunnels = copy;
    if (_activeTunnelId != tunnelId && incoming.authorId != _profile?.id) {
      _unreadCounts[tunnelId] = (_unreadCounts[tunnelId] ?? 0) + 1;
      unawaited(_persistUnread());
    }
    setState(() {});
    final snapshot = List<CgTunnel>.from(_tunnels);
    _saveTunnelsTimer?.cancel();
    _saveTunnelsTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveTunnelsFast(snapshot));
    });
  }

  Future<void> _deleteTunnel(CgTunnel tunnel) async {
    var current = List<CgTunnel>.from(_tunnels);
    for (final item in CgMediaStore.collect(<CgTunnel>[tunnel])) {
      current = await CgMediaStore.purgeItem(current, item);
    }
    _tunnels = current.where((item) => item.id != tunnel.id).toList();
    _unreadCounts.remove(tunnel.id);
    await _relaySubscriptions.remove(tunnel.id)?.cancel();
    await InternetRelay.close(tunnel.id);
    _onlineByTunnel.remove(tunnel.id);
    _refreshPresence();
    await _saveTunnelsFast(_tunnels);
    await _persistUnread();
    if (mounted) setState(() {});
  }

  Future<void> _forwardMessage(CgMessage source, String sourceTunnelId) async {
    final targets = _tunnels
        .where((tunnel) => tunnel.id != sourceTunnelId)
        .toList();
    if (targets.isEmpty || !mounted) return;
    final target = await showModalBottomSheet<CgTunnel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
          itemCount: targets.length,
          itemBuilder: (context, index) {
            final tunnel = targets[index];
            return ListTile(
              leading: _V12TunnelAvatar(tunnel: tunnel, size: 42),
              title: Text(tunnel.displayName),
              onTap: () => Navigator.pop(context, tunnel),
            );
          },
        ),
      ),
    );
    if (target == null) return;
    CgAttachment? transportAttachment = source.attachment;
    if (transportAttachment != null) {
      final file = await CgMediaStore.existingFile(transportAttachment);
      if (file != null && await file.exists()) {
        transportAttachment = transportAttachment.copyWith(
          dataBase64: base64Encode(await file.readAsBytes()),
          clearLocalPath: true,
        );
      }
    }
    final forwarded = CgMessage(
      id: CgIds.random(24),
      authorId: _profile!.id,
      authorName: _profile!.nickname,
      text: source.text,
      sentAt: DateTime.now(),
      type: source.type,
      attachment: transportAttachment,
      meta: <String, dynamic>{
        ...source.meta,
        'forwardedFrom': source.authorName,
      },
    );
    final local = forwarded.attachment == null
        ? forwarded
        : forwarded.copyWith(
            attachment: forwarded.attachment!.copyWith(clearData: true),
          );
    final index = _tunnels.indexWhere((item) => item.id == target.id);
    if (index < 0) return;
    final copy = <CgTunnel>[..._tunnels];
    copy[index] = copy[index].copyWith(
      messages: <CgMessage>[...copy[index].messages, local],
    );
    _tunnels = copy;
    await _saveTunnelsFast(_tunnels);
    final session = await InternetRelay.open(
      tunnelId: target.id,
      secret: target.secret,
      profileId: _profile!.id,
      nickname: _profile!.nickname,
      history: copy[index].historyJson(),
    );
    await session.sendMessage(forwarded.toJson(includeLocalPaths: false));
    if (mounted) setState(() {});
  }

  Future<void> _listenLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_handleUri(initial));
        });
      }
      _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
        unawaited(_handleUri(uri));
      });
    } catch (_) {}
  }

  String? _tokenFromUri(Uri uri) {
    if (uri.scheme == 'chernogram' &&
        uri.host == 'join' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    final invite = uri.queryParameters['invite'];
    return invite == null || invite.isEmpty ? null : invite;
  }

  Future<void> _handleUri(Uri uri) async {
    final token = _tokenFromUri(uri);
    if (token != null) await _joinToken(token);
  }

  Future<void> _joinToken(String token) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final tunnel = CgTunnel.fromInviteToken(token);
    if (tunnel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Это не приглашение.'
                : 'This is not a Chernogram invite.',
          ),
        ),
      );
      return;
    }

    final existing = _tunnels.indexWhere((item) => item.id == tunnel.id);
    if (existing >= 0) {
      await _openTunnel(_tunnels[existing]);
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          tunnel.isPrivate ? Icons.visibility_off_outlined : Icons.public,
          size: 38,
        ),
        title: Text(widget.ru ? 'Подключиться?' : 'Join tunnel?'),
        content: Text(
          '${tunnel.displayName}\n\n${widget.ru ? 'Чат, файлы и звонки работают через интернет.' : 'Chat, files and calls work over the internet.'}',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Подключиться' : 'Join'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _tunnels = [tunnel, ..._tunnels];
      _tab = 0;
    });
    await _saveTunnelsFast(_tunnels);
    await _openTunnel(tunnel);
  }

  Future<void> _scanQr() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _V12QrScanner(ru: widget.ru)),
    );
    if (token != null) await _joinToken(token);
  }

  Future<void> _openMediaLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMediaLibraryScreen(
          ru: widget.ru,
          tunnels: _tunnels,
          onTunnelsChanged: (updated) {
            _tunnels = List<CgTunnel>.from(updated);
            if (mounted) setState(() {});
            final snapshot = List<CgTunnel>.from(_tunnels);
            unawaited(_saveTunnelsFast(snapshot));
          },
        ),
      ),
    );
  }

  Future<void> _openMusicPlayer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMusicPlayerScreen(ru: widget.ru, tunnels: _tunnels),
      ),
    );
  }

  Future<void> _createTunnel() async {
    final profile = _profile;
    if (profile == null) return;
    final result = await showModalBottomSheet<({String name, bool isPrivate})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final name = TextEditingController();
        var isPrivate = true;
        return StatefulBuilder(
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
                  widget.ru ? 'Новый чат' : 'New chat',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.ru
                        ? 'Название — необязательно'
                        : 'Name — optional',
                    hintText: widget.ru
                        ? 'Например: Семья'
                        : 'For example: Family',
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
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    isPrivate
                        ? (widget.ru
                              ? 'Вход только по секретной ссылке или QR.'
                              : 'Join only with a secret link or QR.')
                        : (widget.ru
                              ? 'Ссылку можно свободно пересылать.'
                              : 'The invite can be freely forwarded.'),
                  ),
                  onChanged: (value) => setSheetState(() => isPrivate = value),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, (
                      name: name.text.trim(),
                      isPrivate: isPrivate,
                    )),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      widget.ru ? 'Создать и пригласить' : 'Create and invite',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final tunnel = CgTunnel(
      id: CgIds.random(18),
      name: result.name,
      isPrivate: result.isPrivate,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
    setState(() => _tunnels = [tunnel, ..._tunnels]);
    await _saveTunnelsFast(_tunnels);
    await _openTunnel(tunnel, autoInvite: true);
  }

  Future<void> _createGroupFromDirect(CgTunnel source) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final name = TextEditingController(
      text: widget.ru
          ? 'Группа: ${source.displayName}'
          : 'Group: ${source.displayName}',
    );
    var isPrivate = true;
    final accepted = await showModalBottomSheet<bool>(
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
                widget.ru
                    ? 'Новая группа из переписки'
                    : 'New group from conversation',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'История личной переписки будет скопирована в новый отдельный чат. Исходный личный чат останется без изменений.'
                    : 'The direct conversation history will be copied into a new independent chat. The original direct chat remains unchanged.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.ru ? 'Название группы' : 'Group name',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: isPrivate,
                secondary: Icon(
                  isPrivate
                      ? Icons.visibility_off_outlined
                      : Icons.public_rounded,
                ),
                title: Text(
                  isPrivate
                      ? (widget.ru ? 'Приватная группа' : 'Private group')
                      : (widget.ru ? 'Открытая группа' : 'Public group'),
                ),
                subtitle: Text(
                  isPrivate
                      ? (widget.ru
                            ? 'Вход только по приглашению или QR.'
                            : 'Join only through an invite or QR.')
                      : (widget.ru
                            ? 'Ссылку можно свободно пересылать.'
                            : 'The invite can be freely shared.'),
                ),
                onChanged: (value) => setSheetState(() => isPrivate = value),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.group_add_rounded),
                  label: Text(
                    widget.ru ? 'Создать и пригласить' : 'Create and invite',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted != true || !mounted) {
      name.dispose();
      return;
    }
    final displayName = name.text.trim().isEmpty
        ? (widget.ru ? 'Новая группа' : 'New group')
        : name.text.trim();
    name.dispose();
    final group = CgTunnel(
      id: CgIds.random(18),
      name: displayName,
      isPrivate: isPrivate,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      avatarBase64: source.avatarBase64,
      messages: List<CgMessage>.from(source.messages),
      permissions: const CgPermissions(canInvite: true),
    );
    setState(() => _tunnels = <CgTunnel>[group, ..._tunnels]);
    await _saveTunnelsFast(_tunnels);
    if (!mounted) return;
    await _openTunnel(group, autoInvite: true);
  }

  Future<void> _openTunnel(CgTunnel tunnel, {bool autoInvite = false}) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final currentIndex = _tunnels.indexWhere((item) => item.id == tunnel.id);
    final current = currentIndex < 0 ? tunnel : _tunnels[currentIndex];
    _activeTunnelId = current.id;
    CgNotificationService.setActiveTunnel(current.id);
    _markRead(current.id);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgChatScreen(
          ru: widget.ru,
          profile: profile,
          tunnel: current,
          privacyLens: _privacyLens,
          autoInvite: autoInvite,
          onChanged: _updateTunnel,
          onDelete: _deleteTunnel,
          onForward: (message) => _forwardMessage(message, current.id),
          onContactSeen: _rememberContact,
          onCreateGroupFromDirect: _createGroupFromDirect,
        ),
      ),
    );
    _activeTunnelId = null;
    CgNotificationService.setActiveTunnel(null);
    _markRead(current.id);
  }

  void _updateTunnel(CgTunnel updated) {
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
    final copy = [..._tunnels];
    if (index < 0) {
      copy.insert(0, updated);
    } else {
      copy[index] = updated;
    }
    copy.sort((a, b) {
      final aTime = a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
      final bTime = b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
      return bTime.compareTo(aTime);
    });
    _tunnels = copy;
    if (mounted) setState(() {});
    _saveTunnelsTimer?.cancel();
    final snapshot = List<CgTunnel>.from(_tunnels);
    _saveTunnelsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveTunnelsFast(snapshot));
    });
    unawaited(_syncAppMonitor());
    _refreshAllPresence();
  }

  void _rememberContact(CgContact incoming) {
    if (incoming.id.isEmpty || incoming.id == _profile?.id) return;
    final index = _contacts.indexWhere((item) => item.id == incoming.id);
    if (index < 0) {
      _contacts = [incoming, ..._contacts];
    } else {
      final existing = _contacts[index];
      final updated = existing.copyWith(
        nickname: incoming.nickname.trim().isEmpty
            ? existing.nickname
            : incoming.nickname,
        lastSeenAt: incoming.lastSeenAt,
        tunnelIds: <String>{
          ...existing.tunnelIds,
          ...incoming.tunnelIds,
        }.toList(),
        avatarBase64: incoming.avatarBase64,
      );
      final copy = [..._contacts];
      copy[index] = updated;
      _contacts = copy;
    }
    _contacts.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    if (mounted) setState(() {});
    _saveContactsTimer?.cancel();
    _presenceRefreshTimer?.cancel();
    unawaited(ChernogramAppMonitor.stop());
    final snapshot = List<CgContact>.from(_contacts);
    _saveContactsTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveContactsFast(snapshot));
    });
    unawaited(_ensureDirectTunnel(incoming));
  }

  Future<CgTunnel> _ensureDirectTunnel(CgContact contact) async {
    final profile = _profile;
    if (profile == null) {
      throw StateError('Profile is not loaded');
    }
    final directId = _directTunnelId(profile.id, contact.id);
    final existingIndex = _tunnels.indexWhere((item) => item.id == directId);
    CgTunnel direct;
    var changed = false;
    if (existingIndex >= 0) {
      final existing = _tunnels[existingIndex];
      direct = existing.copyWith(
        name: contact.nickname,
        avatarBase64: contact.avatarBase64,
      );
      if (direct.name != existing.name ||
          direct.avatarBase64 != existing.avatarBase64) {
        final copy = <CgTunnel>[..._tunnels];
        copy[existingIndex] = direct;
        _tunnels = copy;
        changed = true;
      }
    } else {
      direct = CgTunnel(
        id: directId,
        name: contact.nickname,
        isPrivate: true,
        ownerId: '',
        secret: _directTunnelSecret(profile.id, contact.id),
        createdAt: DateTime.now(),
        avatarBase64: contact.avatarBase64,
        messages: const <CgMessage>[],
      );
      _tunnels = <CgTunnel>[direct, ..._tunnels];
      changed = true;
    }
    if (changed) {
      await _saveTunnelsFast(_tunnels);
      if (mounted) setState(() {});
    }
    if (!_relaySubscriptions.containsKey(direct.id)) {
      final session = await InternetRelay.open(
        tunnelId: direct.id,
        secret: direct.secret,
        profileId: profile.id,
        nickname: profile.nickname,
        history: direct.historyJson(),
      );
      _relaySubscriptions[direct.id] = session.events.listen(
        (event) => unawaited(_handleBackgroundEvent(direct.id, event)),
      );
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': profile.nickname,
          if (profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': profile.avatarBase64,
        }),
      );
    }
    return direct;
  }

  Future<void> _openContact(CgContact contact) async {
    final direct = await _ensureDirectTunnel(contact);
    if (!mounted) return;
    await _openTunnel(direct);
  }

  Future<void> _saveProfile(CgProfile profile) async {
    await CgStore.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
    for (final tunnel in _tunnels) {
      final session = InternetRelay.session(tunnel.id);
      if (session == null) continue;
      unawaited(
        session.sendControl(<String, dynamic>{
          'operationId': CgIds.random(24),
          'action': 'profile_card',
          'nickname': profile.nickname,
          if (profile.avatarBase64?.isNotEmpty == true)
            'avatarBase64': profile.avatarBase64,
        }),
      );
    }
  }

  Future<void> _togglePrivacy() async {
    final next = !_privacyLens;
    await CgStore.savePrivacyLens(next);
    if (mounted) setState(() => _privacyLens = next);
  }

  @override
  void dispose() {
    _saveTunnelsTimer?.cancel();
    _saveContactsTimer?.cancel();
    unawaited(_linkSubscription?.cancel());
    unawaited(_notificationClickSubscription?.cancel());
    unawaited(_callClickSubscription?.cancel());
    for (final subscription in _relaySubscriptions.values) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(body: Center(child: ChernogramLogo(size: 112)));
    }

    final pages = <Widget>[
      _V12ChatsHome(
        ru: widget.ru,
        tunnels: _tunnels,
        contacts: _contacts,
        unreadCounts: _unreadCounts,
        onlineByTunnel: _onlineByTunnel,
        privacyLens: _privacyLens,
        onCreate: _createTunnel,
        onScan: _scanQr,
        onOpen: _openTunnel,
        onOpenContact: _openContact,
      ),
      _V12ContactsScreen(
        ru: widget.ru,
        contacts: _contacts,
        onlineContactIds: _onlineContactIds,
        privacyLens: _privacyLens,
        onOpen: _openContact,
      ),
      CgAgentScreen(
        ru: widget.ru,
        profile: _profile!,
        tunnels: _tunnels,
        privacyLens: _privacyLens,
        onCreateTunnel: _createTunnel,
        onTogglePrivacy: _togglePrivacy,
      ),
      _V12ProfileScreen(
        ru: widget.ru,
        profile: _profile!,
        onSave: _saveProfile,
        onCheckUpdates: widget.onCheckUpdates,
        onChangeLanguage: widget.onChangeLanguage,
      ),
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: BrandHeader(
          ru: widget.ru,
          subtitle: widget.ru ? 'чаты и звонки' : 'chats and calls',
        ),
        actions: [
          GlassIconButton(
            icon: Icons.folder_copy_outlined,
            tooltip: widget.ru ? 'Файлы и медиа' : 'Files and media',
            onPressed: _openMediaLibrary,
          ),
          const SizedBox(width: 10),
          GlassIconButton(
            icon: Icons.queue_music_rounded,
            tooltip: widget.ru ? 'Музыкальный плеер' : 'Music player',
            onPressed: _openMusicPlayer,
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: widget.ru ? 'Меню' : 'Menu',
            onSelected: (value) {
              if (value == 'theme') widget.onToggleTheme();
              if (value == 'language') widget.onChangeLanguage();
              if (value == 'update') widget.onCheckUpdates();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(
                    widget.darkMode ? Icons.light_mode : Icons.dark_mode,
                  ),
                  title: Text(
                    widget.darkMode
                        ? (widget.ru ? 'Светлая тема' : 'Light theme')
                        : (widget.ru ? 'Тёмная тема' : 'Dark theme'),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'language',
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(widget.ru ? 'English' : 'Русский'),
                ),
              ),
              PopupMenuItem(
                value: 'update',
                child: ListTile(
                  leading: const Icon(Icons.system_update_alt_rounded),
                  title: Text(
                    widget.ru ? 'Проверить обновления' : 'Check updates',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum_rounded),
            label: widget.ru ? 'Чаты' : 'Chats',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline_rounded),
            selectedIcon: const Icon(Icons.people_rounded),
            label: widget.ru ? 'Контакты' : 'Contacts',
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: widget.ru ? 'Агент' : 'Agent',
          ),
          NavigationDestination(
            icon: _V12ProfileAvatar(
              nickname: _profile!.nickname,
              avatarBase64: _profile!.avatarBase64,
              size: 25,
            ),
            selectedIcon: _V12ProfileAvatar(
              nickname: _profile!.nickname,
              avatarBase64: _profile!.avatarBase64,
              size: 29,
            ),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _FastChatHost extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final CgTunnel tunnel;
  final bool privacyLens;
  final bool autoInvite;
  final ValueChanged<CgTunnel> onChanged;
  final ValueChanged<CgContact> onContactSeen;

  const _FastChatHost({
    required this.ru,
    required this.profile,
    required this.tunnel,
    required this.privacyLens,
    required this.autoInvite,
    required this.onChanged,
    required this.onContactSeen,
  });

  @override
  State<_FastChatHost> createState() => _FastChatHostState();
}

class _FastChatHostState extends State<_FastChatHost> {
  bool _showChat = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (InternetRelay.session(widget.tunnel.id) == null) {
        unawaited(
          InternetRelay.open(
            tunnelId: widget.tunnel.id,
            secret: widget.tunnel.secret,
            profileId: widget.profile.id,
            nickname: widget.profile.nickname,
            history: const <Map<String, dynamic>>[],
          ),
        );
      }
      setState(() => _showChat = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showChat) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: widget.ru ? 'Назад' : 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            widget.privacyLens ? '••••••••' : widget.tunnel.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: const Center(child: ChernogramLogo(size: 82)),
      );
    }

    return Stack(
      children: [
        CgChatScreen(
          ru: widget.ru,
          profile: widget.profile,
          tunnel: widget.tunnel,
          privacyLens: widget.privacyLens,
          autoInvite: widget.autoInvite,
          onChanged: widget.onChanged,
          onContactSeen: widget.onContactSeen,
        ),
        Positioned(
          left: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: 58,
              height: kToolbarHeight,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: IconButton(
                  tooltip: widget.ru ? 'Назад' : 'Back',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _V12ChatsHome extends StatefulWidget {
  final bool ru;
  final List<CgTunnel> tunnels;
  final List<CgContact> contacts;
  final Map<String, int> unreadCounts;
  final Map<String, int> onlineByTunnel;
  final bool privacyLens;
  final VoidCallback onCreate;
  final VoidCallback onScan;
  final Future<void> Function(CgTunnel tunnel) onOpen;
  final Future<void> Function(CgContact contact) onOpenContact;

  const _V12ChatsHome({
    required this.ru,
    required this.tunnels,
    required this.contacts,
    required this.unreadCounts,
    required this.onlineByTunnel,
    required this.privacyLens,
    required this.onCreate,
    required this.onScan,
    required this.onOpen,
    required this.onOpenContact,
  });

  @override
  State<_V12ChatsHome> createState() => _V12ChatsHomeState();
}

class _V12ChatsHomeState extends State<_V12ChatsHome> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;
  bool _aboutOpen = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<CgTunnel> get _visibleTunnels => widget.tunnels
      .where((item) => !item.id.startsWith('dm_') || item.messages.isNotEmpty)
      .toList(growable: false);

  String _key(String value) => value.trim().toLowerCase();

  bool _chatMatches(CgTunnel tunnel, String query) {
    if (_key(tunnel.displayName).contains(query)) return true;
    return tunnel.messages.reversed
        .take(50)
        .any(
          (message) =>
              _key(message.authorName).contains(query) ||
              _key(message.text).contains(query) ||
              _key(message.attachment?.name ?? '').contains(query),
        );
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleTunnels;
    final query = _key(_search.text);
    final foundChats = query.isEmpty
        ? const <CgTunnel>[]
        : visible.where((item) => _chatMatches(item, query)).toList();
    final foundPeople = query.isEmpty
        ? const <CgContact>[]
        : widget.contacts.where((item) {
            return _key(item.nickname).contains(query) ||
                _key(item.id).contains(query);
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 106),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.ru
                          ? 'Связь без границ'
                          : 'Connection without borders',
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.ru ? 'О проекте' : 'About',
                    onPressed: () => setState(() => _aboutOpen = !_aboutOpen),
                    icon: AnimatedRotation(
                      turns: _aboutOpen ? .5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                widget.ru
                    ? 'Общайся без впн и рекламы.'
                    : 'Chat without VPN or ads.',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .58),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _aboutOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.ru
                                  ? 'Чернограм объединяет чаты, звонки, файлы, музыку и прямой обмен между людьми и собственными устройствами. История хранится локально, а тяжёлый контент загружается только по запросу.'
                                  : 'Chernogram combines chats, calls, files, music and direct sharing between people and your own devices. History stays local and heavy content loads only on demand.',
                              style: TextStyle(
                                height: 1.35,
                                color: scheme.onSurface.withValues(alpha: .66),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: <Widget>[
                                _pill(
                                  context,
                                  Icons.block_rounded,
                                  widget.ru ? 'Без рекламы' : 'No ads',
                                ),
                                _pill(
                                  context,
                                  Icons.folder_copy_outlined,
                                  widget.ru ? 'P2P-файлы' : 'P2P files',
                                ),
                                _pill(
                                  context,
                                  Icons.offline_bolt_outlined,
                                  widget.ru
                                      ? 'Локальная история'
                                      : 'Local history',
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _searching
                    ? TextField(
                        key: const ValueKey<String>('home-search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: widget.ru
                              ? 'Чаты, люди и аккаунты'
                              : 'Chats, people and accounts',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            onPressed: _closeSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                          filled: true,
                          fillColor: scheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      )
                    : Row(
                        key: const ValueKey<String>('home-actions'),
                        children: <Widget>[
                          SizedBox(
                            width: 54,
                            height: 48,
                            child: Material(
                              color: Colors.white.withValues(alpha: .92),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: _openSearch,
                                borderRadius: BorderRadius.circular(16),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: scheme.primary,
                                  size: 25,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 6,
                            child: FilledButton.icon(
                              onPressed: widget.onCreate,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(widget.ru ? 'Новый чат' : 'New chat'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: FilledButton.tonalIcon(
                              onPressed: widget.onScan,
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: const Text('QR'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        if (_searching)
          ..._searchResults(context, query, foundChats, foundPeople)
        else ...<Widget>[
          _header(context, widget.ru ? 'Чаты' : 'Chats', '${visible.length}'),
          const SizedBox(height: 6),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 54),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.forum_outlined,
                    size: 64,
                    color: scheme.onSurface.withValues(alpha: .16),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.ru ? 'Чатов пока нет' : 'No chats yet',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            )
          else
            for (final tunnel in visible) _chatTile(context, tunnel),
        ],
      ],
    );
  }

  List<Widget> _searchResults(
    BuildContext context,
    String query,
    List<CgTunnel> chats,
    List<CgContact> people,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (query.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
          child: Text(
            widget.ru
                ? 'Введите название чата, никнейм или ID аккаунта.'
                : 'Type a chat name, nickname or account ID.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: .55)),
          ),
        ),
      ];
    }
    if (chats.isEmpty && people.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Center(
            child: Text(widget.ru ? 'Ничего не найдено' : 'Nothing found'),
          ),
        ),
      ];
    }
    return <Widget>[
      if (chats.isNotEmpty) ...<Widget>[
        _header(context, widget.ru ? 'Чаты' : 'Chats', '${chats.length}'),
        for (final tunnel in chats) _chatTile(context, tunnel),
        const SizedBox(height: 12),
      ],
      if (people.isNotEmpty) ...<Widget>[
        _header(
          context,
          widget.ru ? 'Люди и аккаунты' : 'People and accounts',
          '${people.length}',
        ),
        for (final contact in people) _contactTile(context, contact),
      ],
    ];
  }

  Widget _header(BuildContext context, String title, String count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            count,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: .45)),
          ),
        ],
      ),
    );
  }

  Widget _chatTile(BuildContext context, CgTunnel tunnel) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(widget.onOpen(tunnel)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          child: Row(
            children: <Widget>[
              _V12TunnelAvatar(tunnel: tunnel, size: 50),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.privacyLens
                                ? '••••••••'
                                : tunnel.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if ((widget.onlineByTunnel[tunnel.id] ?? 0) >
                            0) ...<Widget>[
                          const SizedBox(width: 7),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C7F2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.onlineByTunnel[tunnel.id]}',
                            style: const TextStyle(
                              color: Color(0xFF22C7F2),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.privacyLens
                          ? '••••••••••'
                          : _lastMessage(tunnel, widget.ru),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .52),
                      ),
                    ),
                  ],
                ),
              ),
              if ((widget.unreadCounts[tunnel.id] ?? 0) > 0)
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${widget.unreadCounts[tunnel.id]}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactTile(BuildContext context, CgContact contact) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(widget.onOpenContact(contact)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          child: Row(
            children: <Widget>[
              _V12ProfileAvatar(
                nickname: contact.nickname,
                avatarBase64: contact.avatarBase64,
                size: 48,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.privacyLens ? '••••••••' : contact.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.privacyLens ? '••••••••' : 'ID ${contact.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .52),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }

  static String _lastMessage(CgTunnel tunnel, bool ru) {
    final visible = tunnel.messages
        .where((message) => message.meta['localHidden'] != true)
        .toList();
    if (visible.isEmpty) return ru ? 'Готов к приглашению' : 'Ready to invite';
    final message = visible.last;
    if (message.deleted) return ru ? 'Сообщение удалено' : 'Message deleted';
    if (message.type == 'call') return ru ? 'Звонок' : 'Call';
    if (message.attachment != null) return message.attachment!.name;
    return message.text;
  }
}

class _V12TunnelAvatar extends StatelessWidget {
  final CgTunnel tunnel;
  final double size;

  const _V12TunnelAvatar({required this.tunnel, required this.size});

  @override
  Widget build(BuildContext context) {
    final raw = tunnel.avatarBase64;
    if (raw != null) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(raw),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: (size * 3).round(),
          ),
        );
      } catch (_) {}
    }
    final letter = tunnel.displayName.trim().isEmpty
        ? '#'
        : tunnel.displayName.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * .36,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _V12ContactsScreen extends StatelessWidget {
  final bool ru;
  final List<CgContact> contacts;
  final Set<String> onlineContactIds;
  final bool privacyLens;
  final Future<void> Function(CgContact contact) onOpen;

  const _V12ContactsScreen({
    required this.ru,
    required this.contacts,
    required this.onlineContactIds,
    required this.privacyLens,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
      children: [
        Text(
          ru ? 'Контакты' : 'Contacts',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          ru
              ? 'Здесь сохраняются люди, с которыми вы общались.'
              : 'People you have chatted with are saved here.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: .56)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgDeviceContactsScreen(ru: ru),
              ),
            ),
            icon: const Icon(Icons.contact_phone_outlined),
            label: Text(
              ru ? 'Телефонная книга и набор номера' : 'Phone book and dialer',
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 70,
                  color: scheme.onSurface.withValues(alpha: .18),
                ),
                const SizedBox(height: 12),
                Text(
                  ru ? 'Контактов пока нет' : 'No contacts yet',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          )
        else
          for (final contact in contacts)
            Card(
              margin: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                onTap: () => onOpen(contact),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                leading: _V12ContactAvatar(
                  contact: contact,
                  online: onlineContactIds.contains(contact.id),
                ),
                title: Text(
                  privacyLens ? '••••••••' : '@${contact.nickname}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      privacyLens
                          ? '••••••••'
                          : _lastSeen(contact.lastSeenAt, ru),
                    ),
                    if (!privacyLens)
                      Text(
                        'ID ${contact.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurface.withValues(alpha: .42),
                        ),
                      ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: ru ? 'Личное сообщение' : 'Private message',
                  onPressed: () => onOpen(contact),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ),
            ),
      ],
    );
  }

  static String _lastSeen(DateTime value, bool ru) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return ru ? 'только что' : 'just now';
    if (difference.inHours < 1) {
      return ru
          ? '${difference.inMinutes} мин назад'
          : '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return ru
          ? '${difference.inHours} ч назад'
          : '${difference.inHours} h ago';
    }
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}';
  }
}

class _V12ContactAvatar extends StatelessWidget {
  final CgContact contact;
  final bool online;

  const _V12ContactAvatar({required this.contact, required this.online});

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (contact.avatarBase64 != null) {
      try {
        avatar = CircleAvatar(
          backgroundImage: MemoryImage(base64Decode(contact.avatarBase64!)),
        );
      } catch (_) {
        avatar = _fallback(context);
      }
    } else {
      avatar = _fallback(context);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (online)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFF22C7F2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    final letter = contact.nickname.trim().isEmpty
        ? '?'
        : contact.nickname.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _V12ProfileScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final ValueChanged<CgProfile> onSave;
  final VoidCallback onCheckUpdates;
  final VoidCallback onChangeLanguage;

  const _V12ProfileScreen({
    required this.ru,
    required this.profile,
    required this.onSave,
    required this.onCheckUpdates,
    required this.onChangeLanguage,
  });

  @override
  State<_V12ProfileScreen> createState() => _V12ProfileScreenState();
}

class _V12ProfileScreenState extends State<_V12ProfileScreen> {
  late final TextEditingController _nickname = TextEditingController(
    text: widget.profile.nickname,
  );
  String? _avatarBase64;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _avatarBase64 = widget.profile.avatarBase64;
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  Future<void> _showBuildInfo() async {
    if (!mounted) return;
    final notes = widget.ru
        ? <String>[
            'Убрана светлая полоса Android в тёмной теме.',
            'Входящий звонок теперь принимается на любом экране приложения.',
            'Отбой и очистка WebRTC не блокируют интерфейс Android.',
            'В чатах показано число собеседников онлайн.',
            'В контактах добавлены точки «в сети» и точный отступ 2 пикселя.',
            'Добавлены QR и отправка постоянной ссылки установки Android.',
          ]
        : <String>[
            'Removed the light Android divider in dark mode.',
            'Incoming calls are now handled on every application screen.',
            'Hang-up and WebRTC cleanup no longer block Android UI.',
            'Chats show the number of online peers.',
            'Contacts show online dots and use an exact 2-pixel gap.',
            'Added a QR code and permanent Android installation link.',
          ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Сборка Чернограма' : 'Cernogram build',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _version,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .55),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(
                          Icons.circle,
                          size: 7,
                          color: Color(0xFF22C7F2),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text(note)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: QrImageView(data: _androidInstallUrl, size: 190),
              ),
              const SizedBox(height: 12),
              SelectableText(
                _androidInstallUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .58),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Share.share(
                    widget.ru
                        ? 'Установить Чернограм для Android:\n$_androidInstallUrl'
                        : 'Install Cernogram for Android:\n$_androidInstallUrl',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(
                    widget.ru
                        ? 'Отправить ссылку на установку'
                        : 'Share installation link',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final shared =
                        await ChernogramCrashReporter.shareDiagnosticReport(
                          ru: widget.ru,
                        );
                    if (!shared && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            widget.ru
                                ? 'Не удалось подготовить журнал ошибок'
                                : 'Could not prepare the crash report',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.bug_report_outlined),
                  label: Text(
                    widget.ru
                        ? 'Отправить журнал ошибок'
                        : 'Share crash report',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes != null) setState(() => _avatarBase64 = base64Encode(bytes));
  }

  void _save() {
    final nickname = _nickname.text.trim().toLowerCase();
    final error = _nicknameError(nickname, widget.ru);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.onSave(
      widget.profile.copyWith(nickname: nickname, avatarBase64: _avatarBase64),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.ru ? 'Профиль сохранён' : 'Profile saved')),
    );
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
    children: [
      Center(
        child: GestureDetector(
          onTap: _pickAvatar,
          child: _V12ProfileAvatar(
            nickname: _nickname.text,
            avatarBase64: _avatarBase64,
            size: 108,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: Text(
          '@${widget.profile.nickname}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
      Center(
        child: Text(
          'ID ${widget.profile.id}',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .48),
          ),
        ),
      ),
      if (_version.isNotEmpty)
        Center(
          child: InkWell(
            onTap: _showBuildInfo,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '${widget.ru ? 'Версия' : 'Version'} $_version',
                style: TextStyle(
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .58),
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 20),
      TextField(
        controller: _nickname,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.ru ? 'Никнейм' : 'Nickname',
          prefixText: '@',
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(widget.ru ? 'Сохранить профиль' : 'Save profile'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: widget.onCheckUpdates,
        icon: const Icon(Icons.system_update_alt_rounded),
        label: Text(widget.ru ? 'Проверить обновления' : 'Check updates'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => CgPermissionCenter.open(context, ru: widget.ru),
        icon: const Icon(Icons.admin_panel_settings_outlined),
        label: Text(widget.ru ? 'Доступы приложения' : 'App permissions'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: widget.onChangeLanguage,
        icon: const Icon(Icons.language),
        label: Text(widget.ru ? 'English' : 'Русский'),
      ),
    ],
  );
}

class _V12ProfileAvatar extends StatelessWidget {
  final String nickname;
  final String? avatarBase64;
  final double size;

  const _V12ProfileAvatar({
    required this.nickname,
    required this.avatarBase64,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarBase64 != null) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(avatarBase64!),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    final letter = nickname.trim().isEmpty
        ? '?'
        : nickname.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C5CFF), Color(0xFF18B8FF)],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .40,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _V12QrScanner extends StatefulWidget {
  final bool ru;

  const _V12QrScanner({required this.ru});

  @override
  State<_V12QrScanner> createState() => _V12QrScannerState();
}

class _V12QrScannerState extends State<_V12QrScanner> {
  bool _handled = false;
  bool _readingFile = false;
  MobileScannerController? _controller;

  bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) _controller = MobileScannerController();
  }

  String? _extract(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      if (uri.scheme == 'chernogram' &&
          uri.host == 'join' &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      final invite = uri.queryParameters['invite'];
      if (invite != null && invite.isNotEmpty) return invite;
    }
    return CgTunnel.fromInviteToken(value) == null ? null : value;
  }

  void _detect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final token = _extract(raw);
      if (token == null) continue;
      _handled = true;
      Navigator.pop(context, token);
      return;
    }
  }

  Future<void> _pickImage() async {
    if (_readingFile) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _showError(
        widget.ru
            ? 'Не удалось прочитать выбранное изображение.'
            : 'Could not read the selected image.',
      );
      return;
    }
    setState(() => _readingFile = true);
    try {
      final raw = await _decodeQrImage(bytes);
      if (!mounted) return;
      if (raw == null) {
        _showError(
          widget.ru
              ? 'QR-код не найден. Выберите чёткий скриншот или фотографию.'
              : 'No QR code was found. Choose a clear screenshot or photo.',
        );
        return;
      }
      final token = _extract(raw);
      if (token == null) {
        _showError(
          widget.ru
              ? 'Этот QR-код не содержит приглашение Чернограма.'
              : 'This QR code does not contain a Chernogram invite.',
        );
        return;
      }
      _handled = true;
      Navigator.pop(context, token);
    } finally {
      if (mounted) setState(() => _readingFile = false);
    }
  }

  void _showError(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.ru ? 'Принять приглашение' : 'Accept invite'),
    ),
    body: Column(
      children: [
        Expanded(
          child: _cameraSupported
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(controller: _controller, onDetect: _detect),
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF18B8FF),
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 92,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.ru
                              ? 'На компьютере загрузите скриншот или фотографию QR-кода.'
                              : 'On desktop, upload a screenshot or photo of the QR code.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _readingFile ? null : _pickImage,
                icon: _readingFile
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(
                  widget.ru
                      ? 'Загрузить изображение QR-кода'
                      : 'Upload QR-code image',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
