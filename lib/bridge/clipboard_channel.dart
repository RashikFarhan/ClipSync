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

  // ── Remote-echo guard ──────────────────────────────────────────────────────
  // Tracks text last received FROM a remote device. If the native layer fires
  // onClipboardCopied for the same text, we drop it — it was us who wrote it.
  String? _lastSyncedText;

  // ── Windows duplicate guard ────────────────────────────────────────────────
  String? _lastCopiedText;

  // ── Local duplicate guard ──────────────────────────────────────────────────
  // Prevents a race where two Android entry points (PROCESS_TEXT + onResume)
  // both fire for the same copy event nearly simultaneously.
  String? _lastLocalText;

  /// Call this when a remote clip arrives so we can suppress the echo.
  void markAsSynced(String text) {
    _lastSyncedText = text;
  }

  /// Called by the manual Sync button on Android. Pushes [text] through the
  /// same dedup pipeline as a native capture, then fires onClipCaptured.
  Future<void> simulateLocalCopy(String text) async {
    if (text.isEmpty) return;
    // Dedup check
    if (_lastSyncedText == text || _lastLocalText == text) return;
    _lastLocalText = text;
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
  }

  // foregroundService call goes via health channel so the clipboard channel
  // remains exclusively owned by the Dart-side MethodCallHandler.
  static const MethodChannel _healthChannel =
      MethodChannel('com.antigravity.clipsync/health');

  Future<void> startForegroundService() async {
    try {
      await _healthChannel.invokeMethod("startForegroundService");
    } catch (e) {
      debugPrint("Failed to start foreground service natively: $e");
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    // ── Android: text came in via PROCESS_TEXT, QS tile, or onResume ─────────
    if (call.method == "onClipboardCopied") {
      final text = call.arguments as String?;
      if (text == null || text.isEmpty) return;

      // Guard 1: drop if text was just synced FROM a remote device (echo)
      if (_lastSyncedText != null && _lastSyncedText == text) {
        _lastSyncedText = null; // consume guard so next real copy works
        debugPrint("[ClipboardChannel] Dropping remote-echo clip.");
        return;
      }

      // Guard 2: drop if same as last local capture (dedup across entry points)
      if (_lastLocalText == text) {
        debugPrint("[ClipboardChannel] Dropping duplicate local clip.");
        return;
      }
      _lastLocalText = text;

      final clip = ClipItem(
        id: const Uuid().v4(),
        content: text,
        type: 'text',
        timestamp: DateTime.now(),
        deviceName: currentDeviceName,
        isPinned: false,
      );
      await _dbService.insertClip(clip); // DB-level dedup is a final safety net
      if (onClipCaptured != null) onClipCaptured!(clip);
      debugPrint(
          "Captured: [${text.length > 20 ? '${text.substring(0, 20)}...' : text}] | $currentDeviceName");

    // ── Windows: native Win32 clipboard format listener fired ─────────────────
    } else if (call.method == "onNativeClipboardUpdate") {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return;

      // Skip exact duplicate (rapid Windows events)
      if (text == _lastCopiedText) return;
      // Skip if this is text we just synced from a remote device
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
      debugPrint("[Win32 Native Hook] Captured: $text");
    }
  }
}
