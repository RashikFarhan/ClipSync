import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/health_service.dart';

/// Shows a 2-step instruction overlay before redirecting to battery settings.
void showBatteryOptimizationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.battery_alert, color: Color(0xFF00E5FF)),
        SizedBox(width: 8),
        Text('Battery Optimization', style: TextStyle(color: Colors.white, fontSize: 18)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'To keep ClipSync running in the background when you swipe it away, follow these steps:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _instructionStep(1, 'Find "ClipSync" in the All Apps list.'),
          const SizedBox(height: 10),
          _instructionStep(2, 'Tap Battery → select "Don\'t optimize" (or "Unrestricted").'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
            ),
            child: const Text(
              'Your phone will open Battery Optimization settings now.',
              style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Later', style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            Navigator.pop(ctx);
            context.read<HealthService>().disableBatteryOptimization();
          },
          child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

Widget _instructionStep(int number, String text) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        color: Color(0xFF00E5FF),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text('$number',
          style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ),
  ],
);
