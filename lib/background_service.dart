import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';
import 'internet_core.dart';

const String _appActiveAtKey = 'chernogram_app_active_at_v1';
const String _seenBackgroundMessagesKey = 'chernogram_bg_seen_messages_v1';
const String _seenBackgroundCallsKey = 'chernogram_bg_seen_calls_v1';

@pragma('vm:entry-point')
void startChernogramBackgroundTask() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_ChernogramBackgroundTask());
}

class ChernogramBackgroundService {
  static Future<void> setAppActive(bool active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _appActiveAtKey,
        active ? DateTime.now().millisecondsSinceEpoch : 0,
      );
    } catch (_) {}
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chernogram_connection',
        channelName: 'Связь Чернограма',
        channelDescription:
            'Поддерживает получение сообщений и входящих звонков в фоне',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    try {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          serviceTypes: const <ForegroundServiceTypes>[
            ForegroundServiceTypes.remoteMessaging,
          ],
          serviceId: 75001,
          notificationTitle: 'Чернограм на связи',
          notificationText: 'Сообщения и звонки работают в фоне',
          callback: startChernogramBackgroundTask,
        );
      }
    } catch (_) {}
  }
}

class _ChernogramBackgroundTask extends TaskHandler {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, StreamSubscription<InternetEvent>> _subscriptions =
      <String, StreamSubscription<InternetEvent>>{};
  final Map<String, String> _sessionSecrets = <String, String>{};
  final Set<String> _seenMessages = <String>{};
  final Set<String> _seenCalls = <String>{};

  CgProfile? _profile;
  bool _syncing = false;
  bool _notificationsReady = false;
  Timer? _restoreNotificationTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadSeen();
    await _ensureNotifications();
    await _syncSessions();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_syncSessions());
    InternetRelay.reconnectAll();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _restoreNotificationTimer?.cancel();
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _sessionSecrets.clear();
    await InternetRelay.shutdownAll();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  Future<void> _loadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _seenMessages.addAll(
        prefs.getStringList(_seenBackgroundMessagesKey) ?? const <String>[],
      );
      _seenCalls.addAll(
        prefs.getStringList(_seenBackgroundCallsKey) ?? const <String>[],
      );
    } catch (_) {}
  }

  Future<void> _saveSeen() async {
    try {
      while (_seenMessages.length > 500) {
        _seenMessages.remove(_seenMessages.first);
      }
      while (_seenCalls.length > 200) {
        _seenCalls.remove(_seenCalls.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _seenBackgroundMessagesKey,
        _seenMessages.toList(growable: false),
      );
      await prefs.setStringList(
        _seenBackgroundCallsKey,
        _seenCalls.toList(growable: false),
      );
    } catch (_) {}
  }

  Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;
    const initialization = InitializationSettings(
      android: AndroidInitializationSettings(
        '@drawable/chernogram_launcher_icon',
      ),
    );
    await _notifications.initialize(settings: initialization);
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'chernogram_messages',
        'Сообщения Чернограма',
        description: 'Новые сообщения и файлы',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'chernogram_calls',
        'Звонки Чернограма',
        description: 'Входящие аудио- и видеозвонки',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    _notificationsReady = true;
  }

  Future<void> _syncSessions() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileRaw = prefs.getString(CgStore.profileKey);
      final tunnelsRaw = prefs.getString(CgStore.tunnelsKey);
      if (profileRaw == null || tunnelsRaw == null) return;

      final profileJson = jsonDecode(profileRaw);
      final tunnelsJson = jsonDecode(tunnelsRaw);
      if (profileJson is! Map || tunnelsJson is! List) return;
      final profile = CgProfile.fromJson(
        Map<String, dynamic>.from(profileJson),
      );
      final tunnels = tunnelsJson
          .whereType<Map>()
          .map((item) => CgTunnel.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
      _profile = profile;

      final activeIds = tunnels.map((item) => item.id).toSet();
      final obsolete = _subscriptions.keys
          .where((id) => !activeIds.contains(id))
          .toList(growable: false);
      for (final id in obsolete) {
        await _subscriptions.remove(id)?.cancel();
        _sessionSecrets.remove(id);
      }

      for (final tunnel in tunnels) {
        final existingSecret = _sessionSecrets[tunnel.id];
        if (existingSecret == tunnel.secret &&
            _subscriptions.containsKey(tunnel.id)) {
          continue;
        }
        await _subscriptions.remove(tunnel.id)?.cancel();
        final session = await InternetRelay.open(
          tunnelId: tunnel.id,
          secret: tunnel.secret,
          profileId: profile.id,
          nickname: profile.nickname,
          history: const <Map<String, dynamic>>[],
          listenOnly: true,
        );
        _sessionSecrets[tunnel.id] = tunnel.secret;
        _subscriptions[tunnel.id] = session.events.listen(
          (event) => unawaited(_handleEvent(tunnel, event)),
        );
      }
    } catch (_) {
      // The next 15-second cycle retries after transient storage/network errors.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _handleEvent(CgTunnel tunnel, InternetEvent event) async {
    final profile = _profile;
    if (profile == null) return;
    if (event.type == 'message') {
      final raw = event.data['message'];
      if (raw is! Map) return;
      final message = CgMessage.fromJson(Map<String, dynamic>.from(raw));
      if (message.id.isEmpty ||
          message.authorId == profile.id ||
          !_isFresh(message.sentAt, const Duration(minutes: 2)) ||
          !_seenMessages.add(message.id)) {
        return;
      }
      await _saveSeen();
      if (await _appIsActive()) return;
      await _showMessage(tunnel, message);
      return;
    }

    if (event.type != 'signal') return;
    final action = event.data['action']?.toString() ?? '';
    if (action != 'call_invite' && action != 'group_call_invite') return;
    final callId = event.data['callId']?.toString() ?? '';
    final sender =
        event.data['from']?.toString() ??
        event.data['relaySender']?.toString() ??
        '';
    final sentAt = DateTime.tryParse(event.data['sentAt']?.toString() ?? '');
    if (callId.isEmpty ||
        sender.isEmpty ||
        sender == profile.id ||
        sentAt == null ||
        !_isFresh(sentAt, const Duration(seconds: 90)) ||
        !_seenCalls.add('${tunnel.id}:$callId')) {
      return;
    }
    await _saveSeen();
    if (await _appIsActive()) return;
    await _showIncomingCall(tunnel, event.data);
  }

  bool _isFresh(DateTime value, Duration limit) =>
      DateTime.now().difference(value.toLocal()).abs() <= limit;

  Future<bool> _appIsActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_appActiveAtKey) ?? 0;
      if (timestamp <= 0) return false;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      return age >= Duration.zero && age < const Duration(seconds: 25);
    } catch (_) {
      return false;
    }
  }

  Future<void> _showMessage(CgTunnel tunnel, CgMessage message) async {
    await _ensureNotifications();
    final body = message.text.trim().isNotEmpty
        ? message.text.trim()
        : message.attachment != null
        ? 'Получен файл: ${message.attachment!.name}'
        : 'Новое сообщение';
    await _notifications.show(
      id: message.id.hashCode,
      title: message.authorName.trim().isNotEmpty
          ? message.authorName.trim()
          : tunnel.displayName,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'chernogram_messages',
          'Сообщения Чернограма',
          channelDescription: 'Новые сообщения и файлы',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          icon: '@drawable/chernogram_launcher_icon',
        ),
      ),
      payload: tunnel.id,
    );
  }

  Future<void> _showIncomingCall(
    CgTunnel tunnel,
    Map<String, dynamic> data,
  ) async {
    await _ensureNotifications();
    final video = data['video'] == true || data['video']?.toString() == 'true';
    final group = data['action']?.toString() == 'group_call_invite';
    final caller =
        data['fromName']?.toString().trim().isNotEmpty == true
        ? data['fromName'].toString().trim()
        : data['relaySenderName']?.toString().trim().isNotEmpty == true
        ? data['relaySenderName'].toString().trim()
        : tunnel.displayName;

    await FlutterForegroundTask.updateService(
      notificationTitle: video ? 'Входящий видеозвонок' : 'Входящий звонок',
      notificationText: '$caller звонит — нажмите, чтобы ответить',
    );
    _restoreNotificationTimer?.cancel();
    _restoreNotificationTimer = Timer(const Duration(seconds: 60), () {
      unawaited(
        FlutterForegroundTask.updateService(
          notificationTitle: 'Чернограм на связи',
          notificationText: 'Сообщения и звонки работают в фоне',
        ),
      );
    });

    await _notifications.show(
      id: data['callId']?.toString().hashCode ??
          DateTime.now().millisecondsSinceEpoch,
      title: group
          ? (video ? 'Групповой видеозвонок' : 'Групповой звонок')
          : (video ? 'Видеозвонок' : 'Входящий звонок'),
      body: '$caller звонит вам',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'chernogram_calls',
          'Звонки Чернограма',
          channelDescription: 'Входящие аудио- и видеозвонки',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          timeoutAfter: 60000,
          visibility: NotificationVisibility.private,
          icon: '@drawable/chernogram_launcher_icon',
        ),
      ),
      payload: tunnel.id,
    );
  }
}
