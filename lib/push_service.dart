import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const String _firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const String _firebaseSenderId = String.fromEnvironment(
  'FIREBASE_MESSAGING_SENDER_ID',
);
const String _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

bool get _firebaseConfigured =>
    _firebaseApiKey.isNotEmpty &&
    _firebaseAppId.isNotEmpty &&
    _firebaseSenderId.isNotEmpty &&
    _firebaseProjectId.isNotEmpty;

FirebaseOptions get _firebaseOptions => const FirebaseOptions(
  apiKey: _firebaseApiKey,
  appId: _firebaseAppId,
  messagingSenderId: _firebaseSenderId,
  projectId: _firebaseProjectId,
);

@pragma('vm:entry-point')
Future<void> chernogramFirebaseBackgroundHandler(RemoteMessage message) async {
  if (!_firebaseConfigured) return;
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: _firebaseOptions);
  }
  if (message.data['wake'] == 'call') {
    await CgPushService.showIncomingCallNotification(message.data);
  }
}

class CgPushEvent {
  final String roomKey;
  final String packetId;
  final String kind;
  final String wake;

  const CgPushEvent({
    required this.roomKey,
    required this.packetId,
    required this.kind,
    required this.wake,
  });

  factory CgPushEvent.fromMessage(RemoteMessage message) => CgPushEvent(
    roomKey: message.data['roomKey'] ?? '',
    packetId: message.data['packetId'] ?? '',
    kind: message.data['kind'] ?? '',
    wake: message.data['wake'] ?? '',
  );
}

class CgPushService {
  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
        'chernogram_messages',
        'Сообщения Чернограма',
        description: 'Новые сообщения и файлы',
        importance: Importance.high,
      );

  static const AndroidNotificationChannel _callChannel =
      AndroidNotificationChannel(
        'chernogram_calls',
        'Звонки Чернограма',
        description: 'Входящие аудио- и видеозвонки',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<CgPushEvent> _events =
      StreamController<CgPushEvent>.broadcast(sync: true);

  static bool _initialized = false;
  static String? _token;

  static bool get configured => _firebaseConfigured;
  static String? get token => _token;
  static Stream<CgPushEvent> get events => _events.stream;

  static Future<void> initialize() async {
    if (_initialized || !_firebaseConfigured) return;
    _initialized = true;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }

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
    await android?.createNotificationChannel(_messageChannel);
    await android?.createNotificationChannel(_callChannel);
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    _token = await messaging.getToken();
    messaging.onTokenRefresh.listen((value) => _token = value);

    FirebaseMessaging.onMessage.listen((message) async {
      final event = CgPushEvent.fromMessage(message);
      _events.add(event);
      if (event.wake == 'call') {
        await showIncomingCallNotification(message.data);
      } else {
        await _notifications.show(
          id: message.hashCode,
          title: message.notification?.title ?? 'Чернограм',
          body: message.notification?.body ?? 'Новое сообщение',
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
          payload: event.roomKey,
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _events.add(CgPushEvent.fromMessage(message));
    });
    final initial = await messaging.getInitialMessage();
    if (initial != null) _events.add(CgPushEvent.fromMessage(initial));
  }

  static Future<String?> refreshToken() async {
    if (!_firebaseConfigured) return null;
    if (!_initialized) await initialize();
    _token = await FirebaseMessaging.instance.getToken();
    return _token;
  }

  static Future<void> showIncomingCallNotification(
    Map<String, dynamic> data,
  ) async {
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
    await android?.createNotificationChannel(_callChannel);

    await _notifications.show(
      id: data['packetId']?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: data['video'] == 'true' ? 'Видеозвонок' : 'Входящий звонок',
      body: 'Откройте Чернограм, чтобы ответить',
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
      payload: data['roomKey']?.toString(),
    );
  }
}
