import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'key_service.dart';
import 'database_service.dart';
import 'signaling_service.dart';
import 'webrtc_service.dart';
import '../../models/peer_device.dart';

/// Handles the full QR pairing lifecycle:
///   1. Generating our own QR payload (Show My QR)
///   2. Parsing a scanned QR payload (Scan a Device)
///   3. Persisting the new peer to SQLite via upsert (keyed by peerId)
///   4. Firing an MQTT pair_ack to bootstrap the WebRTC session
///   5. Waiting for Handshake_Success ACK confirming the generator accepted us
class PairingService extends ChangeNotifier {
  final KeyService _keyService;
  final DatabaseService _dbService;
  final SignalingService _signalingService;
  final WebRTCService _webrtcService;

  PairingServiceState state = PairingServiceState.idle;
  String? lastPairedDeviceName;
  String? lastError;
  final List<String> pairingLog = [];

  /// Called back by SignalingService when a Handshake_Success arrives.
  /// Set by SignalingService after construction.
  Function(String peerId)? onHandshakeSuccess;

  PairingService({
    required KeyService keyService,
    required DatabaseService dbService,
    required SignalingService signalingService,
    required WebRTCService webrtcService,
  })  : _keyService = keyService,
        _dbService = dbService,
        _signalingService = signalingService,
        _webrtcService = webrtcService;

  // ── QR Generation ───────────────────────────────────────────────────────────

  /// Builds the JSON string that is encoded into the QR code.
  String buildQRPayload(String deviceName) {
    final payload = {
      'schema': 'clipsync_v1',
      'deviceId': _keyService.deviceId ?? 'unknown',
      'publicKey': _keyService.publicKeyHex ?? '',
      'deviceName': deviceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  // ── QR Parsing & Pairing ────────────────────────────────────────────────────

  /// Called when a QR code has been successfully scanned (scanner/mobile side).
  Future<bool> handleScannedQR(String rawValue) async {
    _setState(PairingServiceState.validating);
    _log('QR Scanned — parsing payload…');

    // 1. Parse JSON
    Map<String, dynamic> data;
    try {
      data = jsonDecode(rawValue) as Map<String, dynamic>;
    } catch (_) {
      return _fail('Invalid QR — not a JSON payload.');
    }

    // 2. Schema validation
    if (data['schema'] != 'clipsync_v1') {
      return _fail('Invalid QR — not a ClipSync pairing code.');
    }

    final peerId     = data['deviceId']   as String?;
    final publicKey  = data['publicKey']  as String?;
    final deviceName = data['deviceName'] as String?;
    final timestamp  = data['timestamp']  as int?;

    if (peerId == null || publicKey == null || deviceName == null) {
      return _fail('QR missing required fields.');
    }

    // 3. Freshness check — reject QRs older than 5 minutes
    if (timestamp != null) {
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > 5 * 60 * 1000) {
        return _fail('QR expired (older than 5 min). Regenerate on the source device.');
      }
    }

    // 4. Self-pairing guard
    if (peerId == _keyService.deviceId) {
      return _fail('Cannot pair with yourself.');
    }

    _log('Validating peer: $deviceName…');
    _log('Public key validated ✓');

    // 5. Write to peers table — upsert by peerId guarantees no duplicates
    _setState(PairingServiceState.saving);
    _log('Writing to database…');
    final peer = PeerDevice(
      peerId: peerId,
      peerName: deviceName,
      publicKey: publicKey,
      lastSeen: DateTime.now(),
    );
    await _dbService.upsertPeer(peer);
    _log('Peer saved (upserted by peerId).');

    final allPeers = await _dbService.getPeers();
    _log('Total peers in DB: ${allPeers.length}');

    // 6. Register in WebRTCService session map
    _webrtcService.addPeer(peer);

    // 7. Send pair_ack to the generator with our REAL device name + publicKey
    _log('Sending pair_ack to $deviceName…');
    final myDeviceId   = _keyService.deviceId ?? '';
    final myPublicKey  = _keyService.publicKeyHex ?? '';
    // Use the device label from ClipboardChannel — stored in keyService
    final myDeviceName = _keyService.deviceLabel ?? 'Mobile ${myDeviceId.substring(0, 4)}';
    await _signalingService.pairAckToPeer(
      peerId,
      from: myDeviceId,
      deviceName: myDeviceName,
      publicKey: myPublicKey,
    );
    _log('pair_ack sent → waiting for Handshake_Success from $deviceName…');

    // 8. Now wait for the generator to confirm (handled in SignalingService → notifyHandshakeSuccess)
    _setState(PairingServiceState.waitingForAck);
    lastPairedDeviceName = deviceName;
    return true;
  }

  /// Called by SignalingService when handshake_success is received.
  /// Transitions the scanner out of the waiting state.
  void notifyHandshakeSuccess(String peerId) {
    _log('Handshake_Success received from $peerId — pairing complete! ✓');
    _setState(PairingServiceState.success);
  }

  /// Called by SignalingService when pair_ack is received (Generator side).
  /// Transitions the generator out of the waiting state.
  void notifyPairAckReceived(String peerId, String peerName) {
    _log('Pair ACK received from $peerName ($peerId) — pairing complete! ✓');
    lastPairedDeviceName = peerName;
    _setState(PairingServiceState.success);
  }

  /// Simulates a full pairing flow for the Antigravity demo.
  Future<void> runMockPairingDemo(String localDeviceName) async {
    final mockPeer = {
      'schema': 'clipsync_v1',
      'deviceId': const Uuid().v4(),
      'publicKey': 'mock_pk_${DateTime.now().millisecondsSinceEpoch}',
      'deviceName': 'Demo Android Device',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _log('=== Mock Pairing Demo Started ===');
    await handleScannedQR(jsonEncode(mockPeer));
    _log('=== Mock Pairing Demo Complete ===');
  }

  void reset() {
    state = PairingServiceState.idle;
    lastPairedDeviceName = null;
    lastError = null;
    notifyListeners();
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  void _setState(PairingServiceState s) {
    state = s;
    notifyListeners();
  }

  bool _fail(String msg) {
    lastError = msg;
    _log('ERROR: $msg');
    _setState(PairingServiceState.error);
    return false;
  }

  void _log(String msg) {
    final ts = DateTime.now().toLocal().toString().split('.').first;
    pairingLog.insert(0, '$ts  $msg');
    if (pairingLog.length > 50) pairingLog.removeLast();
  }
}

enum PairingServiceState {
  idle,
  validating,
  saving,
  waitingForAck,   // scanner sent pair_ack, waiting for handshake_success
  success,
  error,
}
