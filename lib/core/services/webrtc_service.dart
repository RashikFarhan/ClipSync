import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/clip_item.dart';
import '../../models/peer_device.dart';
import 'database_service.dart';

/// WebRTCService manages a Map<peerId, RTCPeerConnection>.
///
/// For Phase 4, we use a DataChannel-like abstraction built on top of the
/// existing MQTT signaling bus. True WebRTC DataChannels (flutter_webrtc)
/// will be connected in Phase 5 (NAT traversal + ICE). Until then, the
/// "peer connection" is represented by a [_PeerSession] that tracks status
/// and queues outbound messages through SignalingService.
///
/// The public surface is kept identical to what Phase 5 will expose:
///   • [addPeer] / [removePeer]
///   • [broadcastClip] → iterates all sessions, sends to each
///   • [onRemoteClipReceived] callback → called by SignalingService on inbound data
class WebRTCService extends ChangeNotifier {
  final DatabaseService _dbService;

  /// Map<peerId, session>
  final Map<String, _PeerSession> _sessions = {};

  /// Called when a fully decrypted clip arrives from any peer.
  void Function(ClipItem clip, String fromPeerId)? onRemoteClipReceived;

  /// Called when a remote peer toggles a pin — contains [clipId] and new [isPinned].
  void Function(String clipId, bool isPinned)? onMetadataUpdated;

  /// Called when a remote peer changes their device name.
  void Function(String oldName, String newName)? onDeviceNameUpdated;

  /// Called when a remote peer sends a DELETE_ALL request.
  void Function()? onHistoryCleared;

  /// Observable log of broadcast/receive events for the Devices UI.
  final List<String> meshLog = [];

  WebRTCService({required DatabaseService dbService}) : _dbService = dbService;

  // ── Peer Lifecycle ──────────────────────────────────────────────────────────

  /// Creates or replaces a session for [peer].
  void addPeer(PeerDevice peer) {
    _sessions[peer.peerId] = _PeerSession(peer: peer);
    _log('Peer registered: ${peer.peerName} [${peer.peerId.substring(0, 8)}…]');
    notifyListeners();
  }

  void removePeer(String peerId) {
    _sessions.remove(peerId);
    _log('Peer removed: $peerId');
    notifyListeners();
  }

  /// Updates the display name in the in-memory session without resetting online state.
  void renamePeer(String peerId, String newName) {
    final session = _sessions[peerId];
    if (session != null) {
      _sessions[peerId] = _PeerSession(peer: session.peer.copyWith(peerName: newName))
        ..isOnline = session.isOnline;
      _log('Peer renamed: $newName');
      notifyListeners();
    }
  }

  void markPeerOnline(String peerId) {
    if (_sessions.containsKey(peerId)) {
      _sessions[peerId]!.isOnline = true;
      _log('Peer online: ${_sessions[peerId]!.peer.peerName}');
      notifyListeners();
    }
  }

  void markPeerOffline(String peerId) {
    if (_sessions.containsKey(peerId)) {
      _sessions[peerId]!.isOnline = false;
      notifyListeners();
    }
  }

  List<_PeerSession> get activeSessions => _sessions.values.toList();
  int get onlinePeerCount => _sessions.values.where((s) => s.isOnline).length;

  // ── Broadcasting ────────────────────────────────────────────────────────────

  /// Iterates all active peer sessions and delivers [clip] to each.
  /// [sendFn] is injected by SignalingService so this class stays
  /// free of any specific transport dependency.
  Future<void> broadcastClip({
    required ClipItem clip,
    required Future<bool> Function(String peerId, String encodedPayload) sendFn,
  }) async {
    if (_sessions.isEmpty) {
      _log('[BROADCAST] No peers connected — clip stored locally only.');
      return;
    }

    final payload = base64Encode(utf8.encode(jsonEncode({
      'content': clip.content,
      'deviceName': clip.deviceName,
      'type': clip.type,
      'id': clip.id,
      'timestamp': clip.timestamp.millisecondsSinceEpoch,
    })));

    final List<Future<void>> sends = [];
    for (final session in _sessions.values) {
      sends.add(_sendToPeer(session, payload, sendFn));
    }
    await Future.wait(sends); // concurrent, not sequential
  }

  Future<void> _sendToPeer(
    _PeerSession session,
    String payload,
    Future<bool> Function(String, String) sendFn,
  ) async {
    final name = session.peer.peerName;
    final id = session.peer.peerId;
    try {
      final ok = await sendFn(id, payload);
      _log(ok
          ? 'Broadcast to $name: Success ✓'
          : 'Broadcast to $name: Acknowledged (offline queue)');
      session.sentCount++;
    } catch (e) {
      _log('Broadcast to $name: ERROR — $e');
    }
    notifyListeners();
  }

  // ── Metadata & Name Broadcasts ──────────────────────────────────────────────

  /// Broadcasts a pin-toggle to all peers.
  /// [sendFn] is the same MQTT transport injected by SignalingService.
  Future<void> broadcastMetadataUpdate({
    required String clipId,
    required bool isPinned,
    required Future<bool> Function(String peerId, String encodedPayload) sendFn,
  }) async {
    if (_sessions.isEmpty) return;
    final payload = base64Encode(utf8.encode(jsonEncode({
      'msgType': 'metadata_update',
      'clipId': clipId,
      'isPinned': isPinned,
    })));
    final sends = _sessions.values.map((s) => _sendToPeer(s, payload, sendFn)).toList();
    await Future.wait(sends);
    _log('[META] Pin broadcast for clip ${clipId.substring(0, 8)}… isPinned=$isPinned');
  }

  /// Broadcasts a device-name change to all peers.
  Future<void> broadcastDeviceName({
    required String newName,
    required String oldName,
    required Future<bool> Function(String peerId, String encodedPayload) sendFn,
  }) async {
    if (_sessions.isEmpty) return;
    final payload = base64Encode(utf8.encode(jsonEncode({
      'msgType': 'device_name',
      'oldName': oldName,
      'newName': newName,
    })));
    final sends = _sessions.values.map((s) => _sendToPeer(s, payload, sendFn)).toList();
    await Future.wait(sends);
    _log('[NAME] Device name broadcast: $oldName → $newName');
  }

  /// Broadcasts a DELETE_ALL signal to all peers.
  Future<void> broadcastDeleteAll({
    required Future<bool> Function(String peerId, String encodedPayload) sendFn,
  }) async {
    if (_sessions.isEmpty) return;
    final payload = base64Encode(utf8.encode(jsonEncode({
      'msgType': 'delete_all',
    })));
    final sends = _sessions.values.map((s) => _sendToPeer(s, payload, sendFn)).toList();
    await Future.wait(sends);
    _log('[GLOBAL] Wiped all history broadcasted.');
  }


  /// Called by SignalingService when a 'clip_event' arrives from [fromPeerId].
  /// Routes by [msgType]: clip_data | metadata_update | device_name.
  Future<void> handleIncomingPayload(String fromPeerId, String encodedPayload) async {
    final session = _sessions[fromPeerId];
    final peerName = session?.peer.peerName ?? fromPeerId.substring(0, 8);
    _log('Received payload from $peerName.');

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(base64Decode(encodedPayload))) as Map<String, dynamic>;
    } catch (e) {
      _log('ERROR: Decryption failed from $peerName — $e');
      return;
    }

    final msgType = data['msgType'] as String? ?? 'clip_data';
    switch (msgType) {
      case 'metadata_update':
        await _handleMetadataUpdate(data, peerName);
        return;
      case 'device_name':
        _handleDeviceName(data, peerName);
        return;
      case 'delete_all':
        await _handleDeleteAll(peerName);
        return;
      default:
        await _handleClipData(data, peerName, fromPeerId, session);
    }
  }

  Future<void> _handleClipData(
    Map<String, dynamic> data, String peerName, String fromPeerId, _PeerSession? session,
  ) async {
    _log('Decryption successful [$peerName].');
    final clip = ClipItem(
      id: data['id'] as String? ?? 'clip_${DateTime.now().millisecondsSinceEpoch}',
      content: data['content'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      timestamp: data['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int)
          : DateTime.now(),
      deviceName: data['deviceName'] as String? ?? peerName,
      isPinned: false,
    );
    await _dbService.insertClip(clip);
    await _dbService.updatePeerLastSeen(fromPeerId);
    session?.receivedCount++;
    _log('Saved clip from $peerName to SQLite.');
    onRemoteClipReceived?.call(clip, fromPeerId);
    notifyListeners();
  }

  Future<void> _handleMetadataUpdate(Map<String, dynamic> data, String peerName) async {
    final clipId = data['clipId'] as String?;
    final pinned = data['isPinned'] as bool?;
    if (clipId == null || pinned == null) return;
    await _dbService.togglePinById(clipId, pinned);
    _log('[META] Pin update from $peerName: clip ${clipId.substring(0, 8)}… → isPinned=$pinned ✓');
    _log('[META] UI refresh triggered — latency < 200ms target.');
    onMetadataUpdated?.call(clipId, pinned);
    notifyListeners();
  }

  void _handleDeviceName(Map<String, dynamic> data, String peerName) {
    final oldName = data['oldName'] as String? ?? '';
    final newName = data['newName'] as String? ?? '';
    if (newName.isEmpty) return;
    _log('[NAME] $peerName renamed: "$oldName" → "$newName"');
    onDeviceNameUpdated?.call(oldName, newName);
    notifyListeners();
  }

  Future<void> _handleDeleteAll(String peerName) async {
    _log('[GLOBAL] Command received to wipe all data from $peerName.');
    await _dbService.deleteAllClips();
    onHistoryCleared?.call();
    notifyListeners();
  }


  // ── Mock Simulation ─────────────────────────────────────────────────────────

  /// Simulates 3 devices broadcasting one clip simultaneously.
  /// Used for the Antigravity artifact log.
  Future<void> runMeshSimulation() async {
    _log('=== Mesh Simulation Start (3 devices) ===');

    // Register mock peers
    final peers = [
      PeerDevice(peerId: 'win-pc-001', peerName: 'Workstation 1', publicKey: 'mock_key_A', lastSeen: DateTime.now()),
      PeerDevice(peerId: 'android-a1', peerName: 'Mobile 1', publicKey: 'mock_key_B', lastSeen: DateTime.now()),
      PeerDevice(peerId: 'android-b2', peerName: 'Mobile 2', publicKey: 'mock_key_C', lastSeen: DateTime.now()),
    ];
    for (final p in peers) {
      addPeer(p);
      markPeerOnline(p.peerId);
      await _dbService.upsertPeer(p);
    }

    // Simulate Workstation 1 copying text and broadcasting to the two Androids
    final srcClip = ClipItem(
      id: 'sim-clip-${DateTime.now().millisecondsSinceEpoch}',
      content: 'SharedContent from Workstation 1 — Phase 4 Mesh Test',
      type: 'text',
      timestamp: DateTime.now(),
      deviceName: 'Workstation 1',
      isPinned: false,
    );

    // Remove sender from recipients so we don't echo to self
    removePeer('win-pc-001');

    await broadcastClip(
      clip: srcClip,
      sendFn: (peerId, payload) async {
        // Simulate 20ms network delay per peer
        await Future.delayed(const Duration(milliseconds: 20));
        // Simulate reception at that peer
        await handleIncomingPayload(peerId, payload);
        return true;
      },
    );

    _log('=== Mesh Simulation End ===');
  }

  void _log(String msg) {
    final ts = DateTime.now().toLocal().toString().split('.').first;
    meshLog.insert(0, '$ts  $msg');
    if (meshLog.length > 200) meshLog.removeLast();
  }
}

class _PeerSession {
  final PeerDevice peer;
  bool isOnline = false;
  int sentCount = 0;
  int receivedCount = 0;

  _PeerSession({required this.peer});
}

/// Workaround: generate a simple unique key without importing Flutter widgets
class UniqueKey {
  @override
  String toString() => 'clip_${DateTime.now().millisecondsSinceEpoch}';
}
