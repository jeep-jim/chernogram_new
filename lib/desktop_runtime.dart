import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class CgDesktopRuntime with WindowListener, TrayListener {
  CgDesktopRuntime._();

  static final CgDesktopRuntime instance = CgDesktopRuntime._();
  static bool _initialized = false;
  bool _quitting = false;

  static Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(instance);
    trayManager.addListener(instance);

    try {
      final data = await rootBundle.load('assets/icons/chernogram_tray.ico');
      final dir = await getTemporaryDirectory();
      final icon = File('${dir.path}${Platform.pathSeparator}chernogram_tray.ico');
      await icon.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await trayManager.setIcon(icon.path);
      await trayManager.setToolTip('Чернограм');
      await trayManager.setContextMenu(
        Menu(
          items: <MenuItem>[
            MenuItem(key: 'show', label: 'Открыть Чернограм'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Выйти полностью'),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> hideToTray() async {
    if (!Platform.isWindows || _quitting) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> quit() async {
    if (!Platform.isWindows || _quitting) return;
    _quitting = true;
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (!_quitting) hideToTray();
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      showWindow();
    } else if (menuItem.key == 'exit') {
      quit();
    }
  }
}
