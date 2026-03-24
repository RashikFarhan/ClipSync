import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/services/database_service.dart';
import '../models/clip_item.dart';

class ClipboardChannel {
  static const MethodChannel _channel = MethodChannel('com.antigravity.clipsync/clipboard');
  final DatabaseService _dbService;
  String currentDeviceName = "Mobile 1";

  /// Called whenever a new clip is captured (Android OR Windows).
  /// Used by main.dart to trigger a SignalingService broadcast.
  void Function(ClipItem clip)? onClipCaptured;

  ClipboardChannel(this._dbService) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void setDeviceName(String name) {
    currentDeviceName = name;
  }

  // ── Anti-loop guard ────────────────────────────────────────────────────────
  // Tracks the last text that was received FROM a remote device (via sync).
  // If the native clipboard listener fires for the same text, we ignore it —
  // it was us that wrote it, not the user.
  String? _lastSyncedText;
  String? _lastCopiedText;

  /// Call this when a remote clip is received so we can suppress the echo.
  void markAsSynced(String text) {
    _lastSyncedText = text;
  }

  // Start the foreground service via the health channel (not clipboard channel,
  // because we must not register a native handler on the clipboard channel —
  // the Dart-side handler is the sole listener for onClipboardCopied).
  static const MethodChannel _healthChannel = MethodChannel('com.antigravity.clipsync/health');

  Future<void> startForegroundService() async {
    try {
       await _healthChannel.invokeMethod("startForegroundService");
    } catch (e) {
       debugPrint("Failed to start foreground service natively: $e");
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    // ── Android: Accessibility service detected a clipboard change ─────────
    if (call.method == "onClipboardCopied") {
      final text = call.arguments as String?;
      if (text == null || text.isEmpty) return;

      // Guard: drop if this is text we just synced from a remote device
      if (_lastSyncedText != null && _lastSyncedText == text) {
        _lastSyncedText = null; // consume the guard so next real copy works
        debugPrint("[ClipboardChannel] Dropping echo of synced clip.");
        return;
      }

      final clip = ClipItem(
        id: const Uuid().v4(),
        content: text,
        type: 'text',
        timestamp: DateTime.now(),
        deviceName: currentDeviceName,
        isPinned: false,
      );
      await _dbService.insertClip(clip);
      if (onClipCaptured != null) onClipCaptured!(clip);
      debugPrint("Captured Text: [${text.length > 20 ? '${text.substring(0, 20)}...' : text}] | From: [$currentDeviceName]");

    // ── Windows: native Win32 clipboard format listener fired ──────────────
    } else if (call.method == "onNativeClipboardUpdate") {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return;

      // Guard: skip duplicate + skip synced echo
      if (text == _lastCopiedText) return;
      if (_lastSyncedText != null && _lastSyncedText == text) {
        _lastSyncedText = null;
        debugPrint("[ClipboardChannel][Win] Dropping echo of synced clip.");
        return;
      }

      _lastCopiedText = text;
      final clip = ClipItem(
        id: const Uuid().v4(),
        content: text,
        type: 'text',
        timestamp: DateTime.now(),
        deviceName: currentDeviceName,
        isPinned: false,
      );
      await _dbService.insertClip(clip);
      if (onClipCaptured != null) onClipCaptured!(clip);
      debugPrint("[Win32 Native Hook] Captured Clipboard event: $text");
    }
  }
}
