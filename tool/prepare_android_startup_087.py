from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
start = text.find('Future<void> main() async {')
end = text.find('class ChernogramApp', start)
if start < 0 or end < 0:
    raise SystemExit('main() boundaries not found')
expected = '''Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(chernogramFirebaseBackgroundHandler);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (Platform.isWindows) await CgDesktopRuntime.initialize();
  if (Platform.isAndroid) await CgBackgroundRuntime.initialize();
  runApp(const ChernogramApp());
  CgBackgroundRuntime.setAppVisible(true);
  unawaited(CgPushService.initialize());
}

'''
path.write_text(text[:start] + expected + text[end:], encoding='utf-8')
print('main() normalized for Android 0.87 startup patch')
