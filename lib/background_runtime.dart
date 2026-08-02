import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';
import 'internet_core.dart';

const String _backgroundEnabledKey = 'cg_always_connected_v1';
const String _serviceChannelId = 'chernogram_connection';
const String _messageChannelId = 'chernogram_messages';
const String _callChannelId = 'chernogram_calls';
const int _serviceNotificationId = 68001;

class CgBackgroundRuntime {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _configured = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _configured) return;
    _configured = true;
    await _ensureChannels();
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: chernogramBackgroundEntry,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _serviceChannelId,
        initialNotificationTitle: 'Чернограм',
        initialNotificationContent: 'Всегда на связи',
        foregroundServiceNotificationId: _serviceNotificationId,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
    if (await isEnabled()) await _service.startService();
  }

  static Future<void> _ensureChannels() async {
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(
          '@drawable/chernogram_launcher_icon',
        ),
      ),
    );
    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _serviceChannelId,
        'Соединение Чернограма',
        description: 'Поддерживает доставку сообщений и звонков в фоне.',
        importance: Importance.low,
        showBadge: false,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _messageChannelId,
        'Сообщения',
        description: 'Новые сообщения Чернограма.',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _callChannelId,
        'Звонки',
        description: 'Входящие звонки Чернограма.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_backgroundEnabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundEnabledKey, value);
    if (!Platform.isAndroid) return;
    if (value) {
      await initialize();
      await _service.startService();
    } else {
      _service.invoke('stopService');
    }
  }

  static void setAppVisible(bool visible) {
    if (!Platform.isAndroid) return;
    _service.invoke('appState', <String, dynamic>{'visible': visible});
  }
}

@pragma('vm:entry-point')
Future<void> chernogramBackgroundEntry(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings(
        '@drawable/chernogram_launcher_icon',
      ),
    ),
  );

  var appVisible = false;
  final sessions = <InternetTunnelSession>[];
  final subscriptions = <StreamSubscription<InternetEvent>>[];
  final shownIds = <String>{};

  service.on('appState').listen((event) {
    appVisible = event?['visible'] == true;
  });
  service.on('stopService').listen((_) async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final session in sessions) {
      await session.close();
    }
    await service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'Чернограм',
      content: 'Сообщения и звонки принимаются в фоне',
    );
  }

  final profile = await CgStore.loadOrCreateProfile();
  final tunnels = await CgStore.loadTunnels();
  final recent = tunnels.toList()
    ..sort((a, b) {
      final at = a.messages.isEmpty ? a.createdAt : a.messages.last.sentAt;
      final bt = b.messages.isEmpty ? b.createdAt : b.messages.last.sentAt;
      return bt.compareTo(at);
    });

  Future<void> persistIncoming(CgTunnel tunnel, CgMessage incoming) async {
    final all = await CgStore.loadTunnels();
    final tunnelIndex = all.indexWhere((item) => item.id == tunnel.id);
    if (tunnelIndex < 0) return;
    final current = all[tunnelIndex];
    if (current.messages.any((item) => item.id == incoming.id)) return;
    all[tunnelIndex] = current.copyWith(
      messages: <CgMessage>[...current.messages, incoming],
    );
    await CgStore.saveTunnels(all);
  }

  Future<void> showMessage(CgTunnel tunnel, CgMessage message) async {
    if (appVisible || message.authorId == profile.id || !shownIds.add(message.id)) {
      return;
    }
    final fresh = DateTime.now()
            .difference(message.sentAt.toLocal())
            .inMinutes
            .abs() <=
        3;
    if (!fresh) return;
    final body = message.text.trim().isNotEmpty
        ? message.text.trim()
        : message.attachment?.name ?? 'Новое событие';
    await notifications.show(
      message.id.hashCode & 0x7fffffff,
      tunnel.displayName,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _messageChannelId,
          'Сообщения',
          channelDescription: 'Новые сообщения Чернограма.',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.private,
          icon: '@drawable/chernogram_launcher_icon',
        ),
      ),
      payload: jsonEncode(<String, dynamic>{
        'kind': 'message',
        'tunnelId': tunnel.id,
        'messageId': message.id,
      }),
    );
  }

  Future<void> showCall(CgTunnel tunnel, Map<String, dynamic> signal) async {
    final callId = signal['callId']?.toString() ?? '';
    final from = signal['from']?.toString() ??
        signal['relaySender']?.toString() ??
        '';
    if (callId.isEmpty || from == profile.id || !shownIds.add('call:$callId')) {
      return;
    }
    final caller = signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        'Собеседник';
    final video = signal['video'] == true;
    await notifications.show(
      callId.hashCode & 0x7fffffff,
      video ? 'Видеозвонок' : 'Входящий звонок',
      '$caller • ${tunnel.displayName}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannelId,
          'Звонки',
          channelDescription: 'Входящие звонки Чернограма.',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          visibility: NotificationVisibility.public,
          icon: '@drawable/chernogram_launcher_icon',
          playSound: true,
          enableVibration: true,
        ),
      ),
      payload: jsonEncode(<String, dynamic>{
        'kind': 'call',
        'tunnelId': tunnel.id,
        'signal': signal,
      }),
    );
  }

  for (final tunnel in recent.take(12)) {
    try {
      final session = await InternetRelay.open(
        tunnelId: tunnel.id,
        secret: tunnel.secret,
        profileId: profile.id,
        nickname: profile.nickname,
        history: tunnel.messages.map((item) => item.toJson()).toList(),
      );
      sessions.add(session);
      subscriptions.add(
        session.events.listen((event) {
          if (event.type == 'message' && event.data['message'] is Map) {
            final message = CgMessage.fromJson(
              Map<String, dynamic>.from(event.data['message'] as Map),
            );
            unawaited(persistIncoming(tunnel, message));
            unawaited(showMessage(tunnel, message));
          } else if (event.type == 'signal') {
            final action = event.data['action']?.toString() ?? '';
            if (action == 'call_invite' || action == 'group_call_invite') {
              unawaited(showCall(tunnel, event.data));
            }
          }
        }),
      );
    } catch (_) {}
  }
}
