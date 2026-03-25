import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/pairing_service.dart';
import '../../core/services/key_service.dart';
import '../widgets/pairing_widgets.dart';
import '../widgets/qr_scanner_widget.dart';

enum _AddDevicePath { none, showQR, scan }

/// Platform-adaptive modal for the two-path pairing flow.
///
/// On Android → displayed as a DraggableScrollableSheet (bottom sheet).
/// On Windows/web → displayed as a themed Dialog.
///
/// Both paths share the code below; only the wrapping chrome differs.
void showAddDeviceModal(BuildContext context) {
  bool isDesktop = false;
  if (!kIsWeb) {
    isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  if (isDesktop) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        child: _AddDeviceContent(isDialog: true),
      ),
    );
  } else {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => _AddDeviceContent(
          isDialog: false,
          scrollController: controller,
        ),
      ),
    );
  }
}

class _AddDeviceContent extends StatefulWidget {
  final bool isDialog;
  final ScrollController? scrollController;

  const _AddDeviceContent({required this.isDialog, this.scrollController});

  @override
  State<_AddDeviceContent> createState() => _AddDeviceContentState();
}

class _AddDeviceContentState extends State<_AddDeviceContent> {
  _AddDevicePath _path = _AddDevicePath.none;

  @override
  void initState() {
    super.initState();
    // Always start fresh when modal opens — allows adding multiple devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PairingService>().reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pairing = context.watch<PairingService>();
    final isSuccess = pairing.state == PairingServiceState.success;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          if (!widget.isDialog)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
            child: Row(
              children: [
                if (_path != _AddDevicePath.none && !isSuccess)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 18),
                    onPressed: () => setState(() { _path = _AddDevicePath.none; pairing.reset(); }),
                  ),
                Expanded(
                  child: Text(
                    isSuccess ? 'Device Added!' :
                    pairing.state == PairingServiceState.waitingForAck ? 'Syncing…' :
                    _path == _AddDevicePath.showQR ? 'Show My QR' :
                    _path == _AddDevicePath.scan   ? 'Scan a Device' :
                    'Add Device',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                PairingStateChip(state: pairing.state),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),
          const Divider(color: Colors.white12, height: 1),

          // Body
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: isSuccess
                  ? _buildSuccessView(pairing)
                  : _buildBody(context, pairing),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, PairingService pairing) {
    return switch (_path) {
      _AddDevicePath.none  => _buildChoiceTiles(),
      _AddDevicePath.showQR => _buildQRView(pairing),
      _AddDevicePath.scan  => _buildScanView(pairing),
    };
  }

  Widget _buildSuccessView(PairingService pairing) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PairingSuccessBanner(deviceName: pairing.lastPairedDeviceName ?? 'New Device'),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Another Device'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () {
            pairing.reset();
            setState(() => _path = _AddDevicePath.none);
          },
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done', style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }

  // ── Path chooser ───────────────────────────────────────────────────────────

  Widget _buildChoiceTiles() => Column(
    children: [
      const Text(
        'Choose how you want to connect to another device',
        style: TextStyle(color: Colors.white54, fontSize: 14),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      _ChoiceTile(
        icon: Icons.qr_code_2,
        title: 'Show My QR',
        subtitle: 'Let another device scan this screen to pair with you',
        onTap: () => setState(() => _path = _AddDevicePath.showQR),
      ),
      const SizedBox(height: 16),
      _ChoiceTile(
        icon: Icons.qr_code_scanner,
        title: 'Scan a Device',
        subtitle: 'Scan another device\'s QR code using your camera',
        onTap: () => setState(() => _path = _AddDevicePath.scan),
      ),
    ],
  );

  // ── Show QR path ───────────────────────────────────────────────────────────

  Widget _buildQRView(PairingService pairing) {
    // Local device name — derived from KeyService to prevent collision
    final localName = context.read<KeyService>().deviceLabel ?? 'My Device';
    final qrData = pairing.buildQRPayload(localName);
    return PairingQRWidget(qrData: qrData, deviceName: localName);
  }

  // ── Scan path ──────────────────────────────────────────────────────────────

  Widget _buildScanView(PairingService pairing) {
    final isProcessing = pairing.state == PairingServiceState.validating ||
        pairing.state == PairingServiceState.saving;

    if (isProcessing || pairing.state == PairingServiceState.waitingForAck) {
      final label = pairing.state == PairingServiceState.waitingForAck
          ? 'Waiting for confirmation from\n${pairing.lastPairedDeviceName ?? "peer"}…'
          : pairing.state == PairingServiceState.validating
              ? 'Validating peer…'
              : 'Saving to database…';
      return SizedBox(
        height: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
            const SizedBox(height: 20),
            Text(label,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (pairing.state == PairingServiceState.waitingForAck)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: TextButton(
                  onPressed: () { pairing.reset(); setState(() => _path = _AddDevicePath.none); },
                  child: const Text('Cancel & Re-Scan', style: TextStyle(color: Colors.white38)),
                ),
              ),
          ],
        ),
      );
    }

    if (pairing.state == PairingServiceState.error) {
      return SizedBox(
        height: 260,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(pairing.lastError ?? 'Unknown error',
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white24)),
              onPressed: () { pairing.reset(); },
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 380,
      child: QRScannerWidget(
        onScanned: (val) async {
          await pairing.handleScannedQR(val);
        },
      ),
    );
  }
}

// ── Choice Tile ────────────────────────────────────────────────────────────────

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF00E5FF).withValues(alpha: 0.08),
                const Color(0xFF1A1A2E).withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF00E5FF), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}
