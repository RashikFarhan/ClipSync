import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'key_service.dart';
import 'database_service.dart';
import 'pairing_service.dart';
import 'webrtc_service.dart';
import '../../models/peer_device.dart';

class SignalingService extends ChangeNotifier {
  final KeyService keyService;
  final DatabaseService _dbService;
  WebRTCService? _webrtcService;
  PairingService? _pairingService; // set after construction to notify scanner

  MqttServerClient? _client;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  bool isConnected = false;
  final List<String> logs = [];

  SignalingService({
    required this.keyService,
    required DatabaseService dbService,
  }) : _dbService = dbService;

  void attachWebRTC(WebRTCService service) {
    _webrtcService = service;
  }

  /// Wire PairingService so we can call notifyHandshakeSuccess on it.
  void attachPairingService(PairingService service) {
    _pairingService = service;
  }

  void _addLog(String msg) {
    logs.insert(0, '${DateTime.now().toLocal().toString().split(".").first}: $msg');
    if (logs.length > 50) logs.removeLast();
    notifyListeners();
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final deviceId = keyService.deviceId;
    if (deviceId == null) {
      _addLog('Error: KeyService deviceId is null');
      return;
    }
    await _connect(deviceId);
  }

  Future<void> _connect(String deviceId) async {
    final myTopic = 'clipboard_sync/v1/$deviceId';

    _client = MqttServerClient(
        'broker.emqx.io', 'cs_${DateTime.now().millisecondsSinceEpoch}');
    _client!.port = 1883;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 30;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.onConnected = _onConnected;

    _client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('cs_${DateTime.now().millisecondsSinceEpoch}')
        .withWillTopic('clipboard_sync/v1/$deviceId/will')
        .withWillMessage('disconnected')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      _addLog('Connecting to MQTT broker…');
      await _client!.connect();
    } catch (e) {
      _addLog('Connection failed: $e');
      _client?.disconnect();
      _scheduleReconnect(deviceId);
      return;
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      isConnected = true;
      _reconnectDelaySeconds = 10; // reset backoff on success
      _addLog('MQTT Connected ✓');
      notifyListeners();

      // Subscribe to own topic
      _client!.subscribe(myTopic, MqttQos.atLeastOnce);

      // Auto-reconnect: subscribe to all known peer topics
      final knownPeers = await _dbService.getPeers();
      for (final peer in knownPeers) {
        final peerTopic = 'clipboard_sync/v1/${peer.peerId}';
        _client!.subscribe(peerTopic, MqttQos.atLeastOnce);
        _addLog('[PEERS] Subscribed to: ${peer.peerName}');
        // Register peer in session map so we can receive messages,
        // but do NOT mark as online — only a live heartbeat does that.
        _webrtcService?.addPeer(peer);
      }

      // Inbound message router
      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final incomingTopic = c[0].topic;
        final recMess = c[0].payload as MqttPublishMessage;
        final rawPayload =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        _routeInbound(incomingTopic, rawPayload, myTopic, deviceId);
      });

      // Start repeating heartbeat every 30 seconds
      _startHeartbeat(myTopic);
    } else {
      _addLog('Connection failed: ${_client!.connectionStatus!.state}');
      _client?.disconnect();
      _scheduleReconnect(deviceId);
    }
  }

  // ── Message Router ─────────────────────────────────────────────────────────

  void _routeInbound(
      String topic, String rawPayload, String myTopic, String myDeviceId) {
    try {
      final decoded = jsonDecode(rawPayload) as Map<String, dynamic>;
      final type = decoded['type'] as String?;

      // ── Messages arriving on OUR topic ─────────────────────────────────────
      if (topic == myTopic) {
        switch (type) {
          case 'pair_ack':
            // Generator received ACK from the scanner.
            final peerId    = decoded['from']       as String?;
            final peerName  = decoded['deviceName'] as String? ?? 'Paired Device';
            final publicKey = decoded['publicKey']  as String? ?? '';
            if (peerId != null) {
              _addLog('[PAIR] pair_ack from $peerName — saving peer & sending Handshake_Success');
              final peer = PeerDevice(
                peerId: peerId,
                peerName: peerName,
                publicKey: publicKey,
                lastSeen: DateTime.now(),
              );
              _dbService.upsertPeer(peer).then((_) {
                _webrtcService?.addPeer(peer);
                _webrtcService?.markPeerOnline(peerId);
              });
              // Subscribe to the scanner's topic
              final scannerTopic = 'clipboard_sync/v1/$peerId';
              _client!.subscribe(scannerTopic, MqttQos.atLeastOnce);
              _addLog('[PAIR] Subscribed to scanner: $peerName');

              // Send Handshake_Success back so the scanner transitions to paired
              _sendHandshakeSuccess(peerId, myDeviceId);
              // Tell our own PairingService that we're paired
              _pairingService?.notifyPairAckReceived(peerId, peerName);
            }
            break;

          case 'handshake_success':
            // Scanner received confirmation from generator — pairing complete
            final fromPeer = decoded['from'] as String?;
            if (fromPeer != null) {
              _addLog('[PAIR] Handshake_Success from $fromPeer ✓ Pairing complete!');
              _pairingService?.notifyHandshakeSuccess(fromPeer);
            }
            break;

          case 'clip_event':
            // ★ CRITICAL: Clips sent TO us land on OUR topic — must be handled here!
            final payload = decoded['payload'] as String?;
            final fromId = decoded['from'] as String? ?? 'remote';
            // Guard: ignore clips we sent ourselves (self-echo)
            if (fromId == myDeviceId) break;
            if (payload != null) {
              _addLog('[SYNC] Clip received from ${fromId.length > 8 ? fromId.substring(0, 8) : fromId}…');
              _webrtcService?.handleIncomingPayload(fromId, payload);
            }
            break;

          default:
            if (type != null) _addLog('Self-topic msg type: $type');
        }
        return;
      }

      // ── Messages from a peer's topic ───────────────────────────────────────
      final parts = topic.split('/');
      final fromPeerId = parts.length >= 3 ? parts[2] : topic;

      switch (type) {
        case 'heartbeat':
          _handleHeartbeat(fromPeerId, decoded);
          break;
        case 'clip_event':
          final payload = decoded['payload'] as String?;
          if (payload != null) {
            _addLog('[MESH] Clip from ${fromPeerId.substring(0, 8)}…');
            _webrtcService?.handleIncomingPayload(fromPeerId, payload);
          }
          break;
        default:
          _addLog('Unknown type "$type" on $topic');
      }
    } catch (e) {
      _addLog('Malformed payload on $topic: $e');
    }
  }

  // ── Pair Handshake Helpers ─────────────────────────────────────────────────

  /// Sends a handshake_success message back to the scanner's topic.
  /// This unblocks the scanner from the waitingForAck state.
  void _sendHandshakeSuccess(String scannerPeerId, String myDeviceId) {
    if (_client == null || !isConnected) return;
    final topic = 'clipboard_sync/v1/$scannerPeerId';
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      'type': 'handshake_success',
      'from': myDeviceId,
    }));
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    _addLog('[PAIR] handshake_success sent → $scannerPeerId');
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  void _startHeartbeat(String topic) {
    _heartbeatTimer?.cancel();
    // Send one immediately, then repeat every 30 s
    _publishHeartbeat(topic);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) _publishHeartbeat(topic);
    });
  }

  void _publishHeartbeat(String topic) {
    if (_client == null || !isConnected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      'type': 'heartbeat',
      'status': 'Ready',
      'deviceName': keyService.deviceLabel ?? keyService.deviceId?.substring(0, 8) ?? 'Unknown',
      'publicKey': keyService.publicKeyHex ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    _addLog('Heartbeat sent.');
  }

  void _handleHeartbeat(String peerId, Map<String, dynamic> data) async {
    _addLog('[MESH] Heartbeat from ${peerId.substring(0, 8)}…');
    _webrtcService?.markPeerOnline(peerId);
    final peer = PeerDevice(
      peerId: peerId,
      peerName: data['deviceName'] as String? ?? 'Unknown Device',
      publicKey: data['publicKey'] as String? ?? '',
      lastSeen: DateTime.now(),
    );
    await _dbService.upsertPeer(peer);
  }

  // ── Auto-reconnect ─────────────────────────────────────────────────────────

  int _reconnectDelaySeconds = 10;

  void _scheduleReconnect(String deviceId) {
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: _reconnectDelaySeconds);
    _addLog('Reconnect in ${_reconnectDelaySeconds}s…');
    // Exponential backoff: 10 → 20 → 40 → 60 (max)
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(10, 60);
    _reconnectTimer = Timer(delay, () async {
      _addLog('Attempting reconnect…');
      await _connect(deviceId);
    });
  }

  // ── Publish APIs ───────────────────────────────────────────────────────────

  /// Publishes a clip event to a specific peer topic.
  Future<bool> publishToPeer(String peerId, String encodedPayload) async {
    if (_client == null || !isConnected) {
      _addLog('[BROADCAST] Skipped — not connected.');
      return false;
    }
    final topic = 'clipboard_sync/v1/$peerId';
    final builder = MqttClientPayloadBuilder();
    builder.addString(
        jsonEncode({
          'type': 'clip_event',
          'payload': encodedPayload,
          'from': keyService.deviceId ?? '',
        }));
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    _addLog('[BROADCAST] Published to ${peerId.substring(0, 8)}…');
    return true;
  }

  /// Sends the pair_ack signal to the generator's MQTT topic.
  Future<void> pairAckToPeer(
    String peerId, {
    required String from,
    required String deviceName,
    required String publicKey,
  }) async {
    if (_client == null || !isConnected) {
      _addLog('[PAIR] Cannot send ack — not connected to MQTT.');
      return;
    }
    final topic = 'clipboard_sync/v1/$peerId';
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      'type': 'pair_ack',
      'from': from,
      'deviceName': deviceName,
      'publicKey': publicKey,
    }));
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    _addLog('[PAIR] pair_ack sent to $peerId.');
  }

  /// Legacy broadcast — kept for SyncReceiver compat.
  void broadcastClipEvent(String encodedPayload) {
    final deviceId = keyService.deviceId;
    if (deviceId == null) return;
    publishToPeer(deviceId, encodedPayload);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onConnected() {}

  void _onDisconnected() {
    isConnected = false;
    _heartbeatTimer?.cancel();
    _webrtcService?.activeSessions
        .forEach((s) => _webrtcService?.markPeerOffline(s.peer.peerId));
    _addLog('MQTT Disconnected — scheduling reconnect…');
    notifyListeners();
    final deviceId = keyService.deviceId;
    if (deviceId != null) _scheduleReconnect(deviceId);
  }

  void _onSubscribed(String topic) {
    _addLog('Subscribed → ${topic.split("/").last}');
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}
