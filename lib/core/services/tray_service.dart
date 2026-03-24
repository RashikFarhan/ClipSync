import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class TrayService {
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  bool _isSyncOnline = false;

  VoidCallback? onShowVault;
  VoidCallback? onExit;

  Future<void> init() async {
    if (kIsWeb || !Platform.isWindows) return;

    // Prevent the OS from destroying the process when the window is closed.
    await windowManager.setPreventClose(true);

    await _systemTray.initSystemTray(
      title: 'ClipSync',
      iconPath: 'assets/icons/tray_icon.ico',
      toolTip: 'ClipSync — Universal Clipboard',
    );

    await _rebuildMenu();

    _systemTray.registerSystemTrayEventHandler((eventName) async {
      if (eventName == 'leftMouseUp') {
        await showWindow();
      } else if (eventName == 'rightMouseUp') {
        await _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> setSyncStatus(bool isOnline) async {
    _isSyncOnline = isOnline;
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    await _systemTray.setContextMenu([
      MenuItem(
        label: 'Show Vault',
        onClicked: () async => showWindow(),
      ),
      MenuItem(
        label: _isSyncOnline ? '● Sync: Online' : '○ Sync: Offline',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItem(
        label: 'Exit ClipSync',
        onClicked: () async {
          await windowManager.setPreventClose(false);
          await _appWindow.close();
          if (onExit != null) onExit!();
        },
      ),
    ]);
  }

  /// Reveals the window from tray, adds it back to the taskbar.
  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await _appWindow.show();
    await windowManager.focus();
    if (onShowVault != null) onShowVault!();
  }

  /// Hides to tray and removes from taskbar — called on window close.
  Future<void> minimizeToTray() async {
    await _appWindow.hide();
    await windowManager.setSkipTaskbar(true);
  }
}
