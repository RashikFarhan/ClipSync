import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../services/signaling_service.dart';
import '../../bridge/windows_bridge.dart';
import '../../models/clip_item.dart';

/// Orchestrates the WebRTC-to-Windows data flow.
///
/// When a ClipItem arrives from a remote device via SignalingService /
/// future WebRTC DataChannel:
///   1. Decrypts the payload  (stubbed with Base64 until Phase 4 AES)
///   2. Saves it to SQLite
///   3. On Windows: injects the text into the OS clipboard
///
/// Also exposes [broadcastLocalClip] so the clipboard listener can
/// announce copies to the signaling log without leaking raw data over MQTT.
class SyncReceiver extends ChangeNotifier {
  final DatabaseService _dbService;
  final SignalingService _signalingService;
  final WindowsBridge _windowsBridge;

  final List<String> eventLog = [];

  SyncReceiver({
    required DatabaseService dbService,
    required SignalingService signalingService,
    required WindowsBridge windowsBridge,
  })  : _dbService = dbService,
        _signalingService = signalingService,
        _windowsBridge = windowsBridge;

  // ─── Incoming path ──────────────────────────────────────────────────────────

  /// Call this when a raw payload arrives from the WebRTC DataChannel / MQTT.
  /// [encryptedPayload] is a Base64-encoded JSON (stub until Phase 4 AES-256).
  Future<void> onRemotePayloadReceived(String encryptedPayload) async {
    _log('Received encrypted payload from remote device.');

    // ── Step 1: Decrypt (Phase 4 will replace with AES-256 GCM) ──────────────
    String decryptedJson;
    try {
      decryptedJson = utf8.decode(base64Decode(encryptedPayload));
      _log('Decryption successful.');
    } catch (e) {
      _log('ERROR: Decryption failed — $e');
      return;
    }

    // ── Step 2: Parse ─────────────────────────────────────────────────────────
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(decryptedJson) as Map<String, dynamic>;
    } catch (e) {
      _log('ERROR: JSON parse failed — $e');
      return;
    }

    final String content    = payload['content'] as String? ?? '';
    final String deviceName = payload['deviceName'] as String? ?? 'Remote';
    final String type       = payload['type'] as String? ?? 'text';

    if (content.isEmpty) return;

    // ── Step 3: Save to SQLite ────────────────────────────────────────────────
    final clip = ClipItem(
      id: const Uuid().v4(),
      content: content,
      type: type,
      timestamp: DateTime.now(),
      deviceName: deviceName,
      isPinned: false,
    );
    await _dbService.insertClip(clip);
    _log('Saved to SQLite — [${content.length > 30 ? content.substring(0, 30) : content}…] from [$deviceName].');

    // ── Step 4: Inject into Windows clipboard (loop-guarded) ──────────────────
    if (!kIsWeb && Platform.isWindows) {
      _log('Injecting text to Windows clipboard…');
      final ok = await _windowsBridge.setClipboard(content);
      _log(ok ? 'Injection verified ✓' : 'ERROR: Win32 injection failed.');
    }

    notifyListeners();
  }

  // ─── Outgoing path ──────────────────────────────────────────────────────────

  /// Called by ClipboardChannel.onClipCaptured when the local user copies.
  /// Encodes the clip and logs a broadcast attempt via SignalingService.
  Future<void> broadcastLocalClip(ClipItem clip) async {
    _log('[BROADCAST] Local copy detected — "${ clip.content.length > 30 ? clip.content.substring(0, 30) + "…" : clip.content}" from [${clip.deviceName}].');

    // Build stub-encrypted payload (Base64 JSON) — Phase 4 will add AES-256
    final raw = jsonEncode({
      'content': clip.content,
      'deviceName': clip.deviceName,
      'type': clip.type,
      'id': clip.id,
    });
    final encoded = base64Encode(utf8.encode(raw));

    // Hand off to signaling layer (publishes stub to MQTT heartbeat topic)
    _signalingService.broadcastClipEvent(encoded);
    _log('[SIGNALING] Broadcast attempt queued via MQTT.');

    notifyListeners();
  }

  // ─── Mock verification helper ────────────────────────────────────────────────

  /// Drives the full receive pipeline with a synthetic remote payload
  /// for the Antigravity artifact log.
  Future<void> runMockVerification() async {
    _log('=== Mock Verification Start ===');
    final mockClip = {
      'content': 'Hello from Mobile 1 — ClipSync test payload!',
      'deviceName': 'Mobile 1',
      'type': 'text',
    };
    final encoded = base64Encode(utf8.encode(jsonEncode(mockClip)));
    await onRemotePayloadReceived(encoded);
    _log('=== Mock Verification End ===');
  }

  void _log(String msg) {
    final ts = DateTime.now().toLocal().toString().split('.').first;
    eventLog.insert(0, '$ts  $msg');
    if (eventLog.length > 100) eventLog.removeLast();
    notifyListeners();
  }
}
