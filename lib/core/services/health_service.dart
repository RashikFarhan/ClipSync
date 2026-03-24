import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/peer_device.dart';
import 'signaling_service.dart';
import 'webrtc_service.dart';

class HealthService extends ChangeNotifier {
  final SignalingService _signaling;
  final WebRTCService _webrtc;
  Timer? _pollingTimer;

  static const _androidChannel = MethodChannel('com.antigravity.clipsync/health');

  bool isMqttConnected = false;
  int activeWebRTCPeers = 0;
  List<PeerDevice> trustedPeers = [];

  // Real values — loaded from native Android
  bool isAccessibilityEnabled = false;
  bool isBatteryOptimized = true;
  bool canDrawOverlays = false;

  // Windows-specific
  bool isHotkeyRegistered = false;

  HealthService(this._signaling, this._webrtc) {
    _signaling.addListener(_syncStatus);
    _webrtc.addListener(_syncStatus);
    _syncStatus();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshHealth());
    refreshHealth();
  }

  void _syncStatus() {
    isMqttConnected = _signaling.isConnected;
    activeWebRTCPeers = _webrtc.onlinePeerCount;
    trustedPeers = _webrtc.activeSessions.map((s) => s.peer).toList();
    notifyListeners();
  }

  Future<void> refreshHealth() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      try {
        final Map result = await _androidChannel.invokeMethod('getHealthStatus');
        isAccessibilityEnabled = (result['accessibilityEnabled'] as bool?) ?? false;
        isBatteryOptimized = (result['batteryOptimized'] as bool?) ?? true;
        canDrawOverlays = (result['canDrawOverlays'] as bool?) ?? false;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> fixAccessibility() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('openAccessibilitySettings');
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 1));
    await refreshHealth();
  }

  Future<bool> requestAddTileService() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _androidChannel.invokeMethod('requestAddTileService');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disableBatteryOptimization() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 1));
    await refreshHealth();
  }

  Future<void> openOverlaySettings() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('openOverlaySettings');
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 1));
    await refreshHealth();
  }

  Future<void> openBatterySettings() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('openBatterySettings');
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 1));
    await refreshHealth();
  }

  void setHotkeyRegistered(bool value) {
    isHotkeyRegistered = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _signaling.removeListener(_syncStatus);
    _webrtc.removeListener(_syncStatus);
    super.dispose();
  }
}
