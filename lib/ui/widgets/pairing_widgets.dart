import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/services/pairing_service.dart';

/// Shows the local QR code with a pulse animation while waiting for a scan.
class PairingQRWidget extends StatefulWidget {
  final String qrData;
  final String deviceName;

  const PairingQRWidget({
    super.key,
    required this.qrData,
    required this.deviceName,
  });

  @override
  State<PairingQRWidget> createState() => _PairingQRWidgetState();
}

class _PairingQRWidgetState extends State<PairingQRWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        // QR code in a glowing card
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: _pulseAnim.value * 0.5),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: child,
          ),
          child: QrImageView(
            data: widget.qrData,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF101010),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF101010),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Pulsing "Waiting" indicator
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: _pulseAnim.value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E5FF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Waiting for connection…',
                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),
        Text(
          'Show this QR to another ClipSync device',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.deviceName,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

/// Animated success banner shown after pairing completes.
class PairingSuccessBanner extends StatefulWidget {
  final String deviceName;
  const PairingSuccessBanner({super.key, required this.deviceName});

  @override
  State<PairingSuccessBanner> createState() => _PairingSuccessBannerState();
}

class _PairingSuccessBannerState extends State<PairingSuccessBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF00E5FF), size: 40),
            ),
            const SizedBox(height: 20),
            const Text('Device Paired Successfully!',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '"${widget.deviceName}" has been added to your trusted mesh.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the pairing state enum as a compact status chip.
class PairingStateChip extends StatelessWidget {
  final PairingServiceState state;
  const PairingStateChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      PairingServiceState.idle          => ('Ready', Colors.white38),
      PairingServiceState.validating    => ('Validating…', Colors.amber),
      PairingServiceState.saving        => ('Saving…', Colors.amber),
      PairingServiceState.waitingForAck => ('Syncing…', const Color(0xFF00E5FF)),
      PairingServiceState.success       => ('Paired ✓', const Color(0xFF43A047)),
      PairingServiceState.error         => ('Error', Colors.redAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
