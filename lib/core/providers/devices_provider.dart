import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/webrtc_service.dart';
import '../services/key_service.dart';
import '../../models/peer_device.dart';

class DevicesProvider extends ChangeNotifier {
  final DatabaseService _dbService;
  final WebRTCService _webrtcService;
  final KeyService _keyService;

  List<PeerDevice> _peers = [];

  DevicesProvider({
    required DatabaseService dbService,
    required WebRTCService webrtcService,
    required KeyService keyService,
  })  : _dbService = dbService,
        _webrtcService = webrtcService,
        _keyService = keyService {
    _webrtcService.addListener(_syncFromWebRTC);
    _load();
  }

  /// All peers — "This Device" is always first in the list.
  List<PeerDevice> get peers => _peers;

  Future<void> _load() async {
    final stored = await _dbService.getPeers();

    // Build peers list with on/offline status from WebRTC sessions
    final remotePeers = stored.map((p) {
      final session = _webrtcService.activeSessions
          .cast<dynamic>()
          .firstWhere((s) => s.peer.peerId == p.peerId, orElse: () => null);
      return p.copyWith(isOnline: session?.isOnline ?? false);
    }).toList();

    // Prepend "This Device" as a synthetic always-online entry
    final selfId = _keyService.deviceId ?? 'self';
    final selfName = _keyService.deviceLabel ?? 'This Device';
    final selfPeer = PeerDevice(
      peerId: selfId,
      peerName: '$selfName (This Device)',
      publicKey: _keyService.publicKeyHex ?? '',
      lastSeen: DateTime.now(),
      isOnline: true, // always online — it IS the running device
      isSelf: true,
    );

    _peers = [selfPeer, ...remotePeers];
    notifyListeners();
  }

  void _syncFromWebRTC() => _load();

  Future<void> reload() => _load();

  Future<void> removePeer(String peerId) async {
    await _dbService.removePeer(peerId);
    _webrtcService.removePeer(peerId);
    await _load();
  }

  /// Updates the display name of an existing peer by peerId.
  Future<void> renamePeer(String peerId, String newName) async {
    await _dbService.updatePeerName(peerId, newName);
    _webrtcService.renamePeer(peerId, newName);
    await _load();
  }

  Future<void> addMockPeer(PeerDevice peer) async {
    await _dbService.upsertPeer(peer);
    _webrtcService.addPeer(peer);
    await _load();
  }

  List<String> get meshLog => _webrtcService.meshLog;
  int get onlineCount => _webrtcService.onlinePeerCount + 1; // +1 for self

  @override
  void dispose() {
    _webrtcService.removeListener(_syncFromWebRTC);
    super.dispose();
  }
}
