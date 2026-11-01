import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Manages Windows desktop window lifecycle and the system tray.
class WindowsTrayManager with TrayListener, WindowListener {
  static final WindowsTrayManager instance = WindowsTrayManager._();
  WindowsTrayManager._();

  bool _initialized = false;

  Future<void> init() async {
    if (!Platform.isWindows || _initialized) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    const windowOptions = WindowOptions(
      size: Size(980, 680),
      minimumSize: Size(420, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'HotShare',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.show();
      await windowManager.focus();
    });

    // Prevent direct closing so the app can minimize to the tray
    await windowManager.setPreventClose(true);

    // Initialize System Tray
    trayManager.addListener(this);
    await trayManager.setIcon(
      'windows/runner/resources/app_icon.ico',
    );
    await trayManager.setToolTip('HotShare - Peer to Peer File Sharing');

    final menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'Open HotShare',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Quit',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);

    _initialized = true;
  }

  @override
  void onWindowClose() async {
    // Minimize to tray instead of quitting
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      await windowManager.destroy();
    }
  }

  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
