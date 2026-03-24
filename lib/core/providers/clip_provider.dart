import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/webrtc_service.dart';
import '../../models/clip_item.dart';

class ClipProvider extends ChangeNotifier {
  final DatabaseService _dbService;
  WebRTCService? _webrtcService;

  List<ClipItem> _clips = [];
  String _activeDeviceFilter = 'All';

  // ── Broadcast send function (injected from main.dart) ─────────────────────
  Future<bool> Function(String peerId, String payload)? _sendFn;

  ClipProvider(this._dbService) {
    loadClips();
  }

  void attachWebRTC(WebRTCService webrtc, Future<bool> Function(String, String) sendFn) {
    _webrtcService = webrtc;
    _sendFn = sendFn;

    // React to metadata updates from remote peers
    webrtc.onMetadataUpdated = (_, __) => loadClips();
    // React to device name changes from remote peers
    webrtc.onDeviceNameUpdated = (oldName, newName) => _renameDevice(oldName, newName);
    // React to mass deletion from remote peers
    webrtc.onHistoryCleared = () => loadClips();
  }

  // ── Selectors ──────────────────────────────────────────────────────────────

  List<ClipItem> get filteredClips {
    if (_activeDeviceFilter == 'All') return _clips;
    return _clips.where((c) => c.deviceName == _activeDeviceFilter).toList();
  }

  List<ClipItem> get pinnedClips => filteredClips.where((c) => c.isPinned).toList();
  List<ClipItem> get recentClips => filteredClips.where((c) => !c.isPinned).toList();

  List<String> get availableDevices {
    final devices = _clips.map((c) => c.deviceName).toSet().toList();
    devices.insert(0, 'All');
    return devices;
  }

  String get activeDeviceFilter => _activeDeviceFilter;

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> loadClips() async {
    _clips = await _dbService.getClips();
    notifyListeners();
  }

  void setDeviceFilter(String device) {
    _activeDeviceFilter = device;
    notifyListeners();
  }

  /// Toggles pin locally AND broadcasts METADATA_UPDATE to all peers.
  Future<void> togglePin(ClipItem clip) async {
    final newPinned = !clip.isPinned;
    await _dbService.togglePinById(clip.id, newPinned);
    await loadClips();

    // Broadcast to mesh
    if (_webrtcService != null && _sendFn != null) {
      await _webrtcService!.broadcastMetadataUpdate(
        clipId: clip.id,
        isPinned: newPinned,
        sendFn: _sendFn!,
      );
    }
  }

  /// Deletes a clip locally (no mesh broadcast — deletion is local-only by design).
  Future<void> deleteClip(String id) async {
    await _dbService.deleteClip(id);
    await loadClips();
  }

  /// Clears EVERYTHING locally and optionally broadcasts DELETE_ALL
  Future<void> clearAllHistory({bool broadcast = true}) async {
    await _dbService.deleteAllClips();
    await loadClips();

    if (broadcast && _webrtcService != null && _sendFn != null) {
      await _webrtcService!.broadcastDeleteAll(sendFn: _sendFn!);
    }
  }

  /// Broadcasts a device name change to all peers.
  Future<void> broadcastDeviceNameChange(String oldName, String newName) async {
    if (_webrtcService != null && _sendFn != null) {
      await _webrtcService!.broadcastDeviceName(
        newName: newName,
        oldName: oldName,
        sendFn: _sendFn!,
      );
    }
  }

  /// Called when a remote peer renames their device — updates all matching clips in DB.
  void _renameDevice(String oldName, String newName) {
    _clips = _clips.map((c) =>
        c.deviceName == oldName ? ClipItem(
          id: c.id, content: c.content, type: c.type,
          timestamp: c.timestamp, deviceName: newName, isPinned: c.isPinned,
        ) : c,
    ).toList();
    notifyListeners();
  }

}

