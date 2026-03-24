import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'core/services/database_service.dart';
import 'core/services/key_service.dart';
import 'core/services/signaling_service.dart';
import 'core/services/tray_service.dart';
import 'core/services/sync_receiver.dart';
import 'core/services/webrtc_service.dart';
import 'core/services/pairing_service.dart';
import 'core/services/health_service.dart';
import 'core/providers/clip_provider.dart';
import 'core/providers/devices_provider.dart';
import 'bridge/clipboard_channel.dart';
import 'bridge/windows_bridge.dart';
import 'bridge/quick_paste_bridge.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/quick_manager_overlay.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isAutostart = args.contains('--autostart');

  // ── Window & hotkey managers MUST be initialized before anything else ────────
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    await hotKeyManager.unregisterAll();
    WindowOptions windowOptions = WindowOptions(
      size: const Size(420, 780),
      minimumSize: const Size(380, 600),
      center: true,
      title: 'ClipSync',
      titleBarStyle: TitleBarStyle.normal,
      skipTaskbar: isAutostart,
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (isAutostart) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  // ── Service instantiation ──────────────────────────────────────────────────
  final dbService       = DatabaseService();
  final keyService      = KeyService();
  final windowsBridge   = WindowsBridge();
  final webrtcService   = WebRTCService(dbService: dbService);
  final signalingService = SignalingService(
    keyService: keyService,
    dbService: dbService,
  );
  final clipboardChannel = ClipboardChannel(dbService);
  final clipProvider    = ClipProvider(dbService);
  final devicesProvider = DevicesProvider(
    dbService: dbService,
    webrtcService: webrtcService,
    keyService: keyService,
  );
  final pairingService = PairingService(
    keyService: keyService,
    dbService: dbService,
    signalingService: signalingService,
    webrtcService: webrtcService,
  );
  final healthService = HealthService(signalingService, webrtcService);
  final syncReceiver    = SyncReceiver(
    dbService: dbService,
    signalingService: signalingService,
    windowsBridge: windowsBridge,
  );
  final trayService     = TrayService();

  // ── Quick Paste bridge (Android native overlay <-> Dart DB) ────────────────
  // ignore: unused_local_variable
  final quickPasteBridge = QuickPasteBridge(dbService);

  // ── Init keys ─────────────────────────────────────────────────────────────
  await keyService.init();

  // ── Circular-dep bridge: SignalingService ↔ WebRTCService ↔ PairingService
  signalingService.attachWebRTC(webrtcService);
  signalingService.attachPairingService(pairingService); // closes the ACK loop
  clipProvider.attachWebRTC(webrtcService, signalingService.publishToPeer);

  // WebRTC incoming clips → refresh Vault + platform injection, with loop guard
  webrtcService.onRemoteClipReceived = (clip, fromPeerId) {
    clipProvider.loadClips();
    // Mark the content so the local clipboard listener doesn't re-broadcast it
    clipboardChannel.markAsSynced(clip.content);
    if (!kIsWeb && Platform.isWindows) {
      windowsBridge.setClipboard(clip.content);
    }
  };

  // ── Device identity — use REAL device names ────────────────────────────────
  final deviceId = keyService.deviceId ?? 'unknown';
  
  final prefs = await SharedPreferences.getInstance();
  String? customName = prefs.getString('custom_device_name');

  String deviceLabel;
  if (customName != null && customName.isNotEmpty) {
    deviceLabel = customName;
  } else if (!kIsWeb && Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Use the real computer name — available in Dart stdlib, no plugin needed
    deviceLabel = Platform.localHostname;
  } else if (!kIsWeb && Platform.isAndroid) {
    // Query the Android build model from native side
    try {
      final model = await const MethodChannel('com.antigravity.clipsync/health')
          .invokeMethod<String>('getDeviceModel');
      deviceLabel = model ?? 'Mobile ${deviceId.substring(0, 4)}';
    } catch (_) {
      deviceLabel = 'Mobile ${deviceId.substring(0, 4)}';
    }
  } else {
    deviceLabel = 'Device ${deviceId.substring(0, 4)}';
  }
  keyService.deviceLabel = deviceLabel;          // used in pair_ack + heartbeats
  clipboardChannel.setDeviceName(deviceLabel);

  // ── Windows-specific setup ─────────────────────────────────────────────────
  if (!kIsWeb && Platform.isWindows) {
    await trayService.init();
    trayService.onShowVault = () => navigatorKey.currentState?.popUntil((r) => r.isFirst);
    windowManager.addListener(_TrayWindowListener(trayService));

    await registerGlobalHotkey(clipProvider, windowsBridge, trayService, healthService);
  }

  // ── Bootstrap services (post-frame so engine is ready) ────────────────────
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await signalingService.init();
    await windowsBridge.startClipboardListener();

    // Start foreground service on Android
    if (!kIsWeb && Platform.isAndroid) {
      await clipboardChannel.startForegroundService();
    }

    // Only wire tray sync status on Windows
    if (!kIsWeb && Platform.isWindows) {
      signalingService.addListener(() {
        trayService.setSyncStatus(signalingService.isConnected);
      });
    }
  });

  // ── Local clipboard capture → multi-peer broadcast ────────────────────────
  clipboardChannel.onClipCaptured = (clip) {
    webrtcService.broadcastClip(
      clip: clip,
      sendFn: signalingService.publishToPeer,
    );
    clipProvider.loadClips();
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: signalingService),
        ChangeNotifierProvider.value(value: clipProvider),
        ChangeNotifierProvider.value(value: webrtcService),
        ChangeNotifierProvider.value(value: devicesProvider),
        ChangeNotifierProvider.value(value: syncReceiver),
        ChangeNotifierProvider.value(value: pairingService),
        ChangeNotifierProvider.value(value: healthService),
        Provider.value(value: clipboardChannel),
        Provider.value(value: windowsBridge),
        Provider.value(value: trayService),
        Provider.value(value: keyService),
        Provider.value(value: dbService),
      ],
      child: const ClipSyncApp(),
    ),
  );
}

class ClipSyncApp extends StatelessWidget {
  const ClipSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ClipSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101010),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          surface: Color(0xFF252528),
        ),
        fontFamily: 'Inter',
      ),
      home: const HomeScreen(),
    );
  }
}

// ── Window Listener: Minimize to Tray ─────────────────────────────────────────
class _TrayWindowListener extends WindowListener {
  final TrayService _trayService;
  _TrayWindowListener(this._trayService);

  @override
  void onWindowClose() async => await _trayService.minimizeToTray();
}

Future<void> registerGlobalHotkey(
  ClipProvider clipProvider,
  WindowsBridge windowsBridge,
  TrayService trayService,
  HealthService healthService,
) async {
  await hotKeyManager.unregisterAll();

  final prefs = await SharedPreferences.getInstance();
  HotKey clipHotKey;
  
  final savedJson = prefs.getString('custom_hotkey');
  if (savedJson != null) {
    try {
      clipHotKey = HotKey.fromJson(jsonDecode(savedJson));
    } catch (_) {
      clipHotKey = HotKey(key: PhysicalKeyboardKey.keyV, modifiers: [HotKeyModifier.alt, HotKeyModifier.shift]);
    }
  } else {
    clipHotKey = HotKey(key: PhysicalKeyboardKey.keyV, modifiers: [HotKeyModifier.alt, HotKeyModifier.shift]);
  }

  await hotKeyManager.register(
    clipHotKey,
    keyDownHandler: (v) async {
      // ── Overlay-only window approach ──────────────────────────────────────
      // Hide the title bar so it looks like a standalone clip picker (Win+V style).
      // Resize to the overlay card size, show it, and restore everything on dismiss.
      const overlaySize = Size(420, 600);

      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(overlaySize);
      await windowManager.center();
      await windowManager.show();

      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        await Navigator.of(ctx).push(
          PageRouteBuilder(
            opaque: true, // fully opaque — main app NOT visible
            barrierColor: Colors.transparent,
            pageBuilder: (_, __, ___) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: clipProvider),
                Provider.value(value: windowsBridge),
              ],
              child: const QuickManagerOverlay(),
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 120),
          ),
        );
        // Overlay dismissed — restore window chrome and hide to tray
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSize(const Size(420, 780));
        await trayService.minimizeToTray();
      }
    },
  );
  healthService.setHotkeyRegistered(true);
}
