import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class TrayService {
  SystemTray? _systemTray;
  AppWindow? _appWindow;

  bool _isSyncOnline = false;

  VoidCallback? onShowVault;
  VoidCallback? onExit;

  Future<void> init() async {
    if (kIsWeb || !Platform.isWindows) return;

    _systemTray = SystemTray();
    _appWindow = AppWindow();

    // Prevent the OS from destroying the process when the window is closed.
    await windowManager.setPreventClose(true);

    await _systemTray!.initSystemTray(
      title: 'ClipSync',
      iconPath: 'assets/icons/tray_icon.ico',
      toolTip: 'ClipSync — Universal Clipboard',
    );

    await _rebuildMenu();

    _systemTray!.registerSystemTrayEventHandler((eventName) async {
      if (eventName == 'leftMouseUp') {
        await showWindow();
      } else if (eventName == 'rightMouseUp') {
        await _systemTray!.popUpContextMenu();
      }
    });
  }

  Future<void> setSyncStatus(bool isOnline) async {
    if (kIsWeb || !Platform.isWindows) return;
    _isSyncOnline = isOnline;
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    if (_systemTray == null) return;
    await _systemTray!.setContextMenu([
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
          await _appWindow?.close();
          if (onExit != null) onExit!();
        },
      ),
    ]);
  }

  /// Reveals the window from tray, adds it back to the taskbar.
  Future<void> showWindow() async {
    if (kIsWeb || !Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
    await _appWindow?.show();
    await windowManager.focus();
    if (onShowVault != null) onShowVault!();
  }

  /// Hides to tray and removes from taskbar — called on window close.
  Future<void> minimizeToTray() async {
    if (kIsWeb || !Platform.isWindows) return;
    await _appWindow?.hide();
    await windowManager.setSkipTaskbar(true);
  }
}
