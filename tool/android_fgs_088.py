from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:260]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


# 0.88 is Android-startup only. Communication transport is intentionally untouched.
replace_once('pubspec.yaml', 'version: 0.87.0+87', 'version: 0.88.0+88')

# Android 14+ requires a foreground-service type both in the merged manifest
# and in startForeground(). For a chat that keeps its remote messaging channel
# alive, remoteMessaging is the matching Android service type.
background = Path('lib/background_runtime.dart')
text = background.read_text(encoding='utf-8')
old = '''        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _serviceChannelId,
'''
new = '''        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        foregroundServiceTypes: const <AndroidForegroundType>[
          AndroidForegroundType.remoteMessaging,
        ],
        notificationChannelId: _serviceChannelId,
'''
if old not in text:
    raise SystemExit('Android background configuration block not found')
text = text.replace(old, new, 1)

# Never start the foreground service merely because initialize() is called.
# It starts only from the explicit setEnabled(true) path after the app UI is
# already alive. This also neutralizes an old saved "always connected=true"
# value from 0.85/0.87 during the first launch of 0.88.
text = text.replace(
    "    if (await isEnabled()) await _service.startService();\n",
    "    // Explicitly started only by setEnabled(true).\n",
    1,
)
text = text.replace(
    "    return prefs.getBool(_backgroundEnabledKey) ?? true;\n",
    "    return prefs.getBool(_backgroundEnabledKey) ?? false;\n",
    1,
)
text = text.replace(
    "  static void setAppVisible(bool visible) {\n    if (!Platform.isAndroid) return;\n    _service.invoke('appState', <String, dynamic>{'visible': visible});\n  }\n",
    "  static void setAppVisible(bool visible) {\n    if (!Platform.isAndroid || !_configured) return;\n    _service.invoke('appState', <String, dynamic>{'visible': visible});\n  }\n",
    1,
)
background.write_text(text, encoding='utf-8')

# Do not even configure the Android background-service plugin during normal
# app startup. It will be initialized on demand when the user enables
# "Always connected". Push initialization remains independent.
main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
old_main = '''  unawaited(() async {
    if (Platform.isAndroid) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await CgBackgroundRuntime.initialize();
        CgBackgroundRuntime.setAppVisible(true);
      } catch (_) {}
    }
    try {
      await CgPushService.initialize();
    } catch (_) {}
  }());
'''
new_main = '''  unawaited(() async {
    try {
      await CgPushService.initialize();
    } catch (_) {}
  }());
'''
if old_main not in text:
    raise SystemExit('Android delayed background startup block not found')
main.write_text(text.replace(old_main, new_main, 1), encoding='utf-8')

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')
if 'android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING' not in text:
    text = text.replace(
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n',
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n'
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING" />\n',
        1,
    )

# flutter_background_service_android already declares this service as exported=true.
# Match that value and only add the Android 14+ foregroundServiceType so the
# manifest merger stays deterministic.
service_decl = '''        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:exported="true"
            android:foregroundServiceType="remoteMessaging" />

'''
if 'android:name="id.flutter.flutter_background_service.BackgroundService"' not in text:
    marker = '        <meta-data android:name="flutterEmbedding" android:value="2" />\n'
    if marker not in text:
        raise SystemExit('Flutter embedding marker not found in manifest')
    text = text.replace(marker, service_decl + marker, 1)
manifest.write_text(text, encoding='utf-8')

print('Android 0.88 foreground-service startup fix applied')
