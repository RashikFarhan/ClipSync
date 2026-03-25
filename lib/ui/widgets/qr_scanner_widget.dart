import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Platform-aware QR scanner widget.
/// On Android / iOS: launches the live camera scanner.
/// On Windows / Web: shows a manual-entry fallback.
class QRScannerWidget extends StatefulWidget {
  final void Function(String value) onScanned;

  const QRScannerWidget({super.key, required this.onScanned});

  @override
  State<QRScannerWidget> createState() => _QRScannerWidgetState();
}

class _QRScannerWidgetState extends State<QRScannerWidget> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  _ScannerState _state = _ScannerState.checking;
  bool _scanned = false;

  // For Windows / web fallback
  final TextEditingController _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    if (kIsWeb) {
      setState(() => _state = _ScannerState.desktopFallback);
      return;
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // Desktop — no live camera scanner; use manual entry
      setState(() => _state = _ScannerState.desktopFallback);
      return;
    }

    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() => _state = _ScannerState.scanning);
    } else if (status.isDenied) {
      final result = await Permission.camera.request();
      if (result.isGranted) {
        setState(() => _state = _ScannerState.scanning);
      } else if (result.isPermanentlyDenied) {
        setState(() => _state = _ScannerState.permPermanentlyDenied);
      } else {
        setState(() => _state = _ScannerState.permDenied);
      }
    } else if (status.isPermanentlyDenied) {
      setState(() => _state = _ScannerState.permPermanentlyDenied);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final val = barcode.rawValue;
      if (val != null && val.isNotEmpty) {
        _scanned = true;
        widget.onScanned(val);
        break;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _ScannerState.checking => _buildChecking(),
      _ScannerState.scanning => _buildScanner(),
      _ScannerState.permDenied => _buildPermDenied(permanent: false),
      _ScannerState.permPermanentlyDenied => _buildPermDenied(permanent: true),
      _ScannerState.desktopFallback => _buildDesktopFallback(),
    };
  }

  Widget _buildChecking() => const Center(
    child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
  );

  Widget _buildScanner() => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: MobileScanner(controller: _ctrl, onDetect: _onDetect),
      ),
      // Viewfinder overlay
      Center(
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF00E5FF), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Align the QR code within the frame',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ),
    ],
  );

  Widget _buildPermDenied({required bool permanent}) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.camera_alt_outlined, color: Colors.white38, size: 56),
        const SizedBox(height: 16),
        const Text('Camera Permission Required',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          permanent
              ? 'Camera access was permanently denied. Please enable it in your device Settings → App Permissions.'
              : 'ClipSync needs camera access to scan another device\'s QR code for secure pairing. No photos are taken or stored.',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (permanent)
          OutlinedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
              side: const BorderSide(color: Color(0xFF00E5FF)),
            ),
            onPressed: openAppSettings,
          )
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: _requestPermission,
            child: const Text('Grant Permission', style: TextStyle(color: Colors.black)),
          ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _state = _ScannerState.desktopFallback),
          child: const Text('Enter Code Manually Instead', style: TextStyle(color: Colors.white38)),
        ),
      ],
    ),
  );

  Widget _buildDesktopFallback() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF00E5FF), size: 48),
        const SizedBox(height: 16),
        const Text('Enter Pairing Code',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'No camera detected on this device.\nPaste the JSON pairing code shown on the remote device.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _manualCtrl,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '{"schema":"clipsync_v1","deviceId":…}',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00E5FF)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              final val = _manualCtrl.text.trim();
              if (val.isNotEmpty) widget.onScanned(val);
            },
            child: const Text('Pair Device', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ),
  );
}

enum _ScannerState { checking, scanning, permDenied, permPermanentlyDenied, desktopFallback }
