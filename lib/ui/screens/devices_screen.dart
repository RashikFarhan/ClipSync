import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/services/pairing_service.dart';
import '../../core/services/health_service.dart';
import '../../models/peer_device.dart';
import 'add_device_modal.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final devicesProvider = context.watch<DevicesProvider>();
    final peers = devicesProvider.peers;
    final log = devicesProvider.meshLog;

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        title: Row(
          children: [
            const Text('Mesh Devices', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${devicesProvider.onlineCount} Online',
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddDeviceModal(context),
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Add Device', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // ── Health Dashboard ──────────────────────────────────────────────
          if (!kIsWeb && Platform.isAndroid)
            const _AndroidHealthBanner(),

          // ── Peer Cards ────────────────────────────────────────────────────
          Expanded(
            flex: peers.isEmpty ? 1 : 2,
            child: peers.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: peers.length,
                    itemBuilder: (_, i) => _PeerCard(
                      peer: peers[i],
                      onRemove: () => devicesProvider.removePeer(peers[i].peerId),
                    ),
                  ),
          ),

          // ── Mesh Event Log ────────────────────────────────────────────────
          if (log.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 8, top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  Icon(Icons.terminal, size: 14, color: Color(0xFF00E5FF)),
                  SizedBox(width: 6),
                  Text('MESH EVENT LOG', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: log.length,
                  itemBuilder: (_, i) {
                    final line = log[i];
                    Color c = Colors.white54;
                    if (line.contains('Success')) c = const Color(0xFF00E5FF);
                    if (line.contains('ERROR')) c = Colors.redAccent;
                    if (line.contains('BROADCAST')) c = Colors.amber;
                    if (line.contains('Simulation')) c = Colors.purpleAccent;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Text(line, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: c)),
                    );
                  },
                ),
              ),
            ),
          ],
          // ── Pairing Log ──────────────────────────────────────────────────────
          const _PairingLogSection(),
        ],
      ),
    );
  }

  Widget _emptyState() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.devices_other, size: 64, color: Colors.white12),
        SizedBox(height: 16),
        Text('No Trusted Devices', style: TextStyle(color: Colors.white54, fontSize: 18)),
        SizedBox(height: 8),
        Text('Tap "Add Device" to pair with another\nClipSync device via QR code.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24, fontSize: 13)),
        SizedBox(height: 4),
        Text('Tap 🧪 to simulate a mesh for demo.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white12, fontSize: 11)),
      ],
    ),
  );
}

class _AndroidHealthBanner extends StatelessWidget {
  const _AndroidHealthBanner();

  @override
  Widget build(BuildContext context) {
    final health = context.watch<HealthService>();
    final notificationsOk = health.notificationsEnabled;
    final a11yOk = health.isAccessibilityEnabled;
    final batteryOk = !health.isBatteryOptimized;

    if (notificationsOk && a11yOk && batteryOk) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 12),
              Text('Action Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          if (!notificationsOk)
            _HealthRow(
              icon: Icons.notifications_off_outlined,
              label: 'Notifications are blocked',
              onFix: health.fixNotifications,
            ),
          if (!a11yOk)
            _HealthRow(
              icon: Icons.accessibility_new,
              label: 'Paste access required',
              onFix: health.fixAccessibility,
            ),
          if (!batteryOk)
            _HealthRow(
              icon: Icons.battery_alert,
              label: 'Battery optimization is on',
              onFix: health.disableBatteryOptimization,
            ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onFix;

  const _HealthRow({required this.icon, required this.label, required this.onFix});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
          TextButton(
            onPressed: onFix,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('FIX', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  final PeerDevice peer;
  final VoidCallback onRemove;

  const _PeerCard({required this.peer, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isOnline = peer.isOnline;
    final isSelf = peer.isSelf;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelf ? const Color(0xFF0A1A1A) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelf
            ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
            : isOnline
              ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
              : Colors.white12,
          width: isSelf ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Online indicator dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? const Color(0xFF00E5FF) : Colors.white24,
              boxShadow: isOnline
                  ? [const BoxShadow(color: Color(0xFF00E5FF), blurRadius: 8, spreadRadius: 1)]
                  : [],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        peer.peerName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    if (isSelf)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('You', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    isOnline ? 'Online' : 'Last seen ${_formatLastSeen(peer.lastSeen)}',
                    style: TextStyle(color: isOnline ? const Color(0xFF00E5FF) : Colors.white38, fontSize: 12),
                  ),
                  if (!isSelf) ...[ 
                    const SizedBox(width: 8),
                    Text('ID: ${peer.peerId.substring(0, 8)}…', style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ]),
              ],
            ),
          ),
          // Only show remove button for remote peers, not for self
          if (!isSelf)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.white24, size: 20),
              tooltip: 'Remove peer',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _PairingLogSection extends StatelessWidget {
  const _PairingLogSection();

  @override
  Widget build(BuildContext context) {
    final pairing = context.watch<PairingService>();
    final log = pairing.pairingLog;
    if (log.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 8, top: 4),
          child: Row(children: [
            Icon(Icons.link, size: 14, color: Colors.amber),
            SizedBox(width: 6),
            Text('PAIRING LOG', style: TextStyle(color: Colors.amber, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          ]),
        ),
        Container(
          height: 150,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: log.length,
            itemBuilder: (_, i) {
              final line = log[i];
              Color c = Colors.white54;
              if (line.contains('validated') || line.contains('Success') || line.contains('Paired')) c = const Color(0xFF00E5FF);
              if (line.contains('ERROR')) c = Colors.redAccent;
              if (line.contains('Peers count')) c = Colors.amber;
              if (line.contains('Writing') || line.contains('Saving')) c = Colors.lightGreenAccent;
              if (line.contains('Mock') || line.contains('Demo')) c = Colors.purpleAccent;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Text(line, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: c)),
              );
            },
          ),
        ),
      ],
    );
  }
}
