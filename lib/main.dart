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

/// Global toggle: when true the app root shows QuickManagerOverlay instead of
/// HomeScreen.  Flipped by the hotkey handler in registerGlobalHotkey().
final ValueNotifier<bool> overlayActive = ValueNotifier(false);

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

  // WebRTC incoming clips → refresh Vault + loop guard
  // NOTE: We deliberately do NOT write synced clips to the Windows clipboard.
  // Writing to the clipboard would trigger the Win32 format-listener which then
  // re-captures the text as a "new" local copy, causing a duplicate vault entry.
  // Users paste synced clips via the overlay (hotkey) only.
  webrtcService.onRemoteClipReceived = (clip, fromPeerId) {
    clipProvider.loadClips();
    // Still mark as synced so if somehow the clipboard is read, the guard fires
    clipboardChannel.markAsSynced(clip.content);
  };

  // ── Device identity — use REAL device names ────────────────────────────────
  final deviceId = keyService.deviceId ?? 'unknown';
  
  final prefs = await SharedPreferences.getInstance();
  String? customName = prefs.getString('custom_device_name');

  String deviceLabel;
  if (customName != null && customName.isNotEmpty) {
    deviceLabel = customName;
  } else if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
      child: ClipSyncApp(
        clipProvider: clipProvider,
        windowsBridge: windowsBridge,
        trayService: trayService,
      ),
    ),
  );
}

class ClipSyncApp extends StatelessWidget {
  final ClipProvider clipProvider;
  final WindowsBridge windowsBridge;
  final TrayService trayService;

  const ClipSyncApp({
    super.key,
    required this.clipProvider,
    required this.windowsBridge,
    required this.trayService,
  });

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
      // Use the ValueListenableBuilder so the entire widget tree swaps.
      // In overlay mode the window IS the panel (no frame, exact size).
      home: ValueListenableBuilder<bool>(
        valueListenable: overlayActive,
        builder: (context, isOverlay, _) {
          if (isOverlay) {
            return QuickManagerOverlay(
              onClose: () async {
                // 1. Flip state FIRST so Flutter renders HomeScreen
                overlayActive.value = false;

                // 2. Restore the window to normal main-app mode
                if (!kIsWeb && Platform.isWindows) {
                  await windowManager.setTitleBarStyle(TitleBarStyle.normal);
                  await windowManager.setAlwaysOnTop(false);
                  await windowManager.setSkipTaskbar(false);
                  await windowManager.setSize(const Size(420, 780));
                  await windowManager.center();
                  // Hide to tray immediately
                  await trayService.minimizeToTray();
                }
              },
            );
          }
          return const HomeScreen();
        },
      ),
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
      clipHotKey = HotKey(
          key: PhysicalKeyboardKey.keyV,
          modifiers: [HotKeyModifier.alt, HotKeyModifier.shift]);
    }
  } else {
    clipHotKey = HotKey(
        key: PhysicalKeyboardKey.keyV,
        modifiers: [HotKeyModifier.alt, HotKeyModifier.shift]);
  }

  await hotKeyManager.register(
    clipHotKey,
    keyDownHandler: (v) async {
      // Already showing overlay — ignore
      if (overlayActive.value) return;

      // Transform the window into a frameless floating panel.
      // setAsFrameless() removes ALL Win32 window chrome — no title bar,
      // no resize border, no border shadow. The window now IS the card.
      await windowManager.setAsFrameless();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setSize(const Size(380, 500));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();

      // Swap root widget to the overlay
      overlayActive.value = true;
    },
  );
  healthService.setHotkeyRegistered(true);
}
