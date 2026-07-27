import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desktop_tray_service.dart';

class CgNotificationService with WidgetsBindingObserver {
  CgNotificationService._();

  static final CgNotificationService instance = CgNotificationService._();
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final StreamController<String> _tunnelClicks =
      StreamController<String>.broadcast();
  static final Set<String> _shownMessageIds = <String>{};

  static bool _initialized = false;
  static AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  static String? _activeTunnelId;
  static String? _pendingTunnelId;

  static Stream<String> get tunnelClicks => _tunnelClicks.stream;
  static bool get isForeground => _lifecycle == AppLifecycleState.resumed;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(instance);

    const android = AndroidInitializationSettings(
      '@drawable/chernogram_launcher_icon',
    );
    final windows = WindowsInitializationSettings(
      appName: 'Чернограм',
      appUserModelId: 'Chernogram.Desktop',
      guid: 'B6C33A77-38D4-4CA0-BE3A-B0C431E40F16',
    );
    final settings = InitializationSettings(
      android: android,
      windows: windows,
    );

    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        _handlePayload(payload);
      }
    } catch (_) {
      // Notification support must never block the messenger from starting.
    }
  }

  static void setActiveTunnel(String? tunnelId) {
    _activeTunnelId = tunnelId;
  }

  static String? consumePendingTunnelId() {
    final value = _pendingTunnelId;
    _pendingTunnelId = null;
    return value;
  }

  static Future<void> showMessage({
    required String messageId,
    required String tunnelId,
    required String title,
    required String body,
  }) async {
    if (!_initialized || messageId.isEmpty || !_shownMessageIds.add(messageId)) {
      return;
    }
    if (_shownMessageIds.length > 1500) {
      _shownMessageIds.remove(_shownMessageIds.first);
    }
    if (isForeground && _activeTunnelId == tunnelId) return;

    final safeBody = body.trim().isEmpty ? 'Новое сообщение' : body.trim();
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'chernogram_messages',
        'Сообщения',
        channelDescription: 'Новые сообщения и файлы',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.message,
      ),
      windows: WindowsNotificationDetails(),
    );

    try {
      await _plugin.show(
        id: messageId.hashCode & 0x7fffffff,
        title: title,
        body: safeBody,
        notificationDetails: details,
        payload: 'tunnel:$tunnelId',
      );
    } catch (_) {
      // Local notification support is optional on unsupported Windows builds.
    }
  }

  static void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) _handlePayload(payload);
  }

  static void _handlePayload(String payload) {
    if (!payload.startsWith('tunnel:')) return;
    final tunnelId = payload.substring('tunnel:'.length);
    if (tunnelId.isEmpty) return;
    _pendingTunnelId = tunnelId;
    if (Platform.isWindows) unawaited(CgDesktopTray.showWindow());
    _tunnelClicks.add(tunnelId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  static Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(instance);
    await _tunnelClicks.close();
  }
}
