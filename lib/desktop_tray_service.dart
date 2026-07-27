import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class CgDesktopTray with WindowListener, TrayListener {
  CgDesktopTray._();

  static final CgDesktopTray instance = CgDesktopTray._();
  static bool _initialized = false;
  bool _quitting = false;

  static Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    windowManager.addListener(instance);
    trayManager.addListener(instance);
    await windowManager.setPreventClose(true);

    try {
      await trayManager.setIcon('assets/branding/chernogram_tray.ico');
      await trayManager.setToolTip('Чернограм');
      final menu = Menu(
        items: <MenuItem>[
          MenuItem(key: 'show', label: 'Открыть Чернограм'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Выйти'),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (_) {
      // The window remains usable even if a tray implementation is unavailable.
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  static Future<void> showWindow() => instance._showWindow();

  @override
  void onWindowClose() {
    if (_quitting) return;
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      _showWindow();
    } else if (menuItem.key == 'quit') {
      _quit();
    }
  }

  Future<void> _quit() async {
    _quitting = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
