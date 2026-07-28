import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';
import 'internet_core.dart';
import 'pending_call.dart';

const String _foregroundChannelId = 'chernogram_realtime_service';
const int _foregroundNotificationId = 991;
const String _foregroundStateKey = 'cg_app_foreground_v1';


Future<void> setChernogramAppForeground(bool foreground) async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_foregroundStateKey, foreground);
  FlutterBackgroundService().invoke(
    'appState',
    <String, dynamic>{'foreground': foreground},
  );
}

Future<void> initializeChernogramRealtimeService() async {
  if (!Platform.isAndroid) return;

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _foregroundChannelId,
          'Фоновая связь',
          description: 'Поддерживает сообщения и входящие звонки в фоне.',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: chernogramRealtimeServiceEntryPoint,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: _foregroundChannelId,
      initialNotificationTitle: 'Чернограм',
      initialNotificationContent: 'Фоновая связь активна',
      foregroundServiceNotificationId: _foregroundNotificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: chernogramRealtimeServiceEntryPoint,
      onBackground: chernogramRealtimeIosBackground,
    ),
  );
  await service.startService();
}

@pragma('vm:entry-point')
Future<bool> chernogramRealtimeIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void chernogramRealtimeServiceEntryPoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('chernogram_notification_icon'),
    ),
  );

  final sessions = <String, InternetTunnelSession>{};
  final subscriptions = <String, StreamSubscription<InternetEvent>>{};
  final displayedMessages = <String>{};
  final displayedCalls = <String>{};
  CgProfile? profile;
  List<CgTunnel> tunnels = const <CgTunnel>[];
  bool syncingSessions = false;

  Future<bool> appIsForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_foregroundStateKey) == true;
  }

  Future<void> showMessage(
    String tunnelId,
    CgTunnel tunnel,
    Map<String, dynamic> raw,
  ) async {
    final currentProfile = profile;
    if (currentProfile == null) return;
    final message = CgMessage.fromJson(raw);
    if (message.id.isEmpty ||
        message.authorId == currentProfile.id ||
        !displayedMessages.add(message.id) ||
        await appIsForeground()) {
      return;
    }
    if (displayedMessages.length > 1200) {
      displayedMessages.remove(displayedMessages.first);
    }
    final body = message.text.trim().isNotEmpty
        ? '${message.authorName}: ${message.text.trim()}'
        : '${message.authorName}: ${message.attachment?.name ?? 'Новое сообщение'}';
    await notifications.show(
      id: message.id.hashCode & 0x7fffffff,
      title: tunnel.displayName,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'chernogram_messages',
          'Сообщения',
          channelDescription: 'Новые сообщения и файлы',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: 'tunnel:$tunnelId',
    );
  }

  Future<void> showCall(
    String tunnelId,
    CgTunnel tunnel,
    Map<String, dynamic> signal,
  ) async {
    final currentProfile = profile;
    if (currentProfile == null || await appIsForeground()) return;
    final target = signal['target']?.toString() ?? '';
    if (target.isNotEmpty && target != currentProfile.id) return;
    final signalAt = DateTime.tryParse(
      signal['receivedAt']?.toString() ?? signal['sentAt']?.toString() ?? '',
    );
    if (signalAt != null &&
        DateTime.now().toUtc().difference(signalAt.toUtc()).inSeconds > 25) {
      return;
    }
    final action = signal['action']?.toString() ?? '';
    final group = action == 'group_call_invite';
    final callId = signal['callId']?.toString() ?? '';
    final fromId = signal['from']?.toString() ??
        signal['relaySender']?.toString() ??
        '';
    if (callId.isEmpty ||
        fromId.isEmpty ||
        fromId == currentProfile.id ||
        !displayedCalls.add(callId)) {
      return;
    }
    final fromName = signal['fromName']?.toString() ??
        signal['relaySenderName']?.toString() ??
        tunnel.displayName;
    final video = signal['video'] == true;
    await CgPendingCallStore.save(
      CgPendingCall(
        callId: callId,
        tunnelId: tunnelId,
        fromId: fromId,
        fromName: fromName,
        avatarBase64: signal['avatarBase64']?.toString(),
        video: video,
        group: group,
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final callDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'chernogram_calls_v3',
        'Входящие звонки',
        channelDescription: 'Полноэкранные входящие звонки Чернограма',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(
          'chernogram_incoming',
        ),
        enableVibration: true,
        vibrationPattern: Int64List.fromList(
          <int>[0, 650, 350, 650, 350, 650],
        ),
        visibility: NotificationVisibility.public,
      ),
    );
    await notifications.show(
      id: callId.hashCode & 0x7fffffff,
      title: video ? 'Видеозвонок' : 'Аудиозвонок',
      body: '$fromName звонит вам',
      notificationDetails: callDetails,
      payload: 'call:$callId',
    );
  }

  Future<void> handleEvent(
    String tunnelId,
    CgTunnel tunnel,
    InternetEvent event,
  ) async {
    if (event.type == 'message' && event.data['message'] is Map) {
      await showMessage(
        tunnelId,
        tunnel,
        Map<String, dynamic>.from(event.data['message'] as Map),
      );
      return;
    }
    if (event.type != 'signal') return;
    final action = event.data['action']?.toString() ?? '';
    final callId = event.data['callId']?.toString() ?? '';
    if (action == 'call_invite' || action == 'group_call_invite') {
      await showCall(tunnelId, tunnel, event.data);
      return;
    }
    if (callId.isNotEmpty &&
        (action == 'call_end' ||
            action == 'call_decline' ||
            action == 'group_leave')) {
      displayedCalls.remove(callId);
      await CgPendingCallStore.remove(callId);
      await notifications.cancel(id: callId.hashCode & 0x7fffffff);
    }
  }

  Future<void> closeSessions() async {
    for (final subscription in subscriptions.values) {
      await subscription.cancel();
    }
    subscriptions.clear();
    for (final session in sessions.values) {
      await session.close();
    }
    sessions.clear();
  }

  Future<void> syncSessions() async {
    if (syncingSessions) return;
    syncingSessions = true;
    try {
      final foreground = await appIsForeground();
      if (foreground) {
        await closeSessions();
        if (service is AndroidServiceInstance &&
            await service.isForegroundService()) {
          await service.setAsBackgroundService();
        }
        return;
      }

      if (service is AndroidServiceInstance &&
          !await service.isForegroundService()) {
        await service.setAsForegroundService();
      }

      profile = await CgStore.loadOrCreateProfile();
      tunnels = await CgStore.loadTunnels();
      final currentProfile = profile;
      if (currentProfile == null) return;
      final activeIds = tunnels.map((item) => item.id).toSet();

      final stale = sessions.keys.where((id) => !activeIds.contains(id)).toList();
      for (final id in stale) {
        await subscriptions.remove(id)?.cancel();
        await sessions.remove(id)?.close();
      }

      for (final tunnel in tunnels) {
        if (sessions.containsKey(tunnel.id)) continue;
        try {
          final session = await InternetRelay.open(
            tunnelId: tunnel.id,
            secret: tunnel.secret,
            profileId: currentProfile.id,
            nickname: currentProfile.nickname,
            history: const <Map<String, dynamic>>[],
          );
          sessions[tunnel.id] = session;
          subscriptions[tunnel.id] = session.events.listen(
            (event) => unawaited(handleEvent(tunnel.id, tunnel, event)),
          );
        } catch (_) {}
      }

      if (service is AndroidServiceInstance &&
          await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'Чернограм',
          content: 'Фоновая связь активна',
        );
      }
    } catch (_) {
      // Keep the background isolate alive across temporary radio/storage errors.
    } finally {
      syncingSessions = false;
    }
  }

  service.on('appState').listen((event) async {
    final foreground = event?['foreground'] == true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foregroundStateKey, foreground);
    await syncSessions();
  });

  service.on('refresh').listen((_) => unawaited(syncSessions()));
  service.on('stopService').listen((_) async {
    for (final subscription in subscriptions.values) {
      await subscription.cancel();
    }
    for (final session in sessions.values) {
      await session.close();
    }
    service.stopSelf();
  });

  await syncSessions();
  Timer.periodic(const Duration(seconds: 20), (_) {
    unawaited(syncSessions().catchError((_) {}));
  });
}
