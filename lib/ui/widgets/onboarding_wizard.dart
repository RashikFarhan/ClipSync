import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/health_service.dart';
import 'package:provider/provider.dart';

/// First-run onboarding wizard — 4 steps:
/// 1. Accessibility Service (needed for paste injection)
/// 2. Display Over Other Apps (needed for overlay)
/// 3. Notifications (needed for "Sync Now" notification hub)
/// 4. Battery Optimization
class OnboardingWizard extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingWizard({super.key, required this.onComplete});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int _currentStep = 0;
  Timer? _healthPollTimer;

  @override
  void initState() {
    super.initState();
    _healthPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) context.read<HealthService>().refreshHealth();
    });
  }

  @override
  void dispose() {
    _healthPollTimer?.cancel();
    super.dispose();
  }

  Widget _tutorialAsset(int step) {
    // AspectRatio(4:3) = width / height = 4/3
    // Flutter sizes this to fill the available width and sets height automatically.
    // BoxFit.contain ensures the full GIF is always visible — nothing is cropped.
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/gifs/$step.webp',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/gifs/$step.gif',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.ondemand_video, color: Colors.white24, size: 32),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final health = context.watch<HealthService>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
      ),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.rocket_launch, color: Color(0xFF00E5FF), size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Setup Wizard',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Step ${_currentStep + 1}/4',
                  style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Step indicator dots
          Row(
            children: [
              _stepDot(0, health.isAccessibilityEnabled),
              _stepLine(),
              _stepDot(1, health.canDrawOverlays),
              _stepLine(),
              _stepDot(2, health.notificationsEnabled),
              _stepLine(),
              _stepDot(3, !health.isBatteryOptimized),
            ],
          ),
          const SizedBox(height: 24),

          // Step content
          if (_currentStep == 0) _buildAccessibilityStep(health),
          if (_currentStep == 1) _buildOverlayStep(health),
          if (_currentStep == 2) _buildNotificationStep(health),
          if (_currentStep == 3) _buildBatteryStep(health),
        ],
      ),
    );
  }

  // ── Step 1: Accessibility ──────────────────────────────────────────────────
  Widget _buildAccessibilityStep(HealthService health) {
    return _stepCard(
      gifIndex: 1,
      icon: Icons.accessibility_new,
      title: 'Enable Accessibility Service',
      description:
          'ClipSync uses Accessibility to paste text into any app from the overlay.',
      note:
          '(If grayed out → App Info → 3-dot menu → "Allow restricted settings" → then enable ClipSync)',
      isCompleted: health.isAccessibilityEnabled,
      buttonLabel:
          health.isAccessibilityEnabled ? 'Done ✓  →  Next' : 'Open Settings',
      onPressed: health.isAccessibilityEnabled
          ? () => setState(() => _currentStep = 1)
          : () => health.fixAccessibility(),
    );
  }

  // ── Step 2: Overlay permission ─────────────────────────────────────────────
  Widget _buildOverlayStep(HealthService health) {
    return _stepCard(
      gifIndex: 2,
      icon: Icons.layers,
      title: 'Enable Display Over Other Apps',
      description:
          'Allows the Quick Paste overlay to appear on top of any open app.',
      isCompleted: health.canDrawOverlays,
      buttonLabel: health.canDrawOverlays ? 'Done ✓  →  Next' : 'Grant Permission',
      onPressed: health.canDrawOverlays
          ? () => setState(() => _currentStep = 2)
          : () => health.openOverlaySettings(),
    );
  }

  // ── Step 3: Notifications ──────────────────────────────────────────────────
  Widget _buildNotificationStep(HealthService health) {
    return _stepCard(
      gifIndex: 3,
      icon: Icons.notifications_active_outlined,
      title: 'Allow Notifications',
      description:
          'ClipSync keeps a persistent notification in your shade with two actions:\n'
          '• Tap the notification → Quick Paste overlay\n'
          '• Tap [Sync Now] → sync your current clipboard immediately',
      isCompleted: health.notificationsEnabled,
      buttonLabel:
          health.notificationsEnabled ? 'Done ✓  →  Next' : 'Enable Notifications',
      onPressed: health.notificationsEnabled
          ? () => setState(() => _currentStep = 3)
          : () => health.fixNotifications(),
    );
  }

  // ── Step 4: Battery optimization ───────────────────────────────────────────
  Widget _buildBatteryStep(HealthService health) {
    final optimized = health.isBatteryOptimized;
    return _stepCard(
      gifIndex: 4,
      icon: Icons.battery_saver,
      title: 'Allow Background Activity',
      description:
          'Open battery settings for ClipSync and enable:\n'
          '• "Allow background activity"\n'
          '• "Don\'t restrict" (or "No restrictions")\n'
          '• Auto-start (if shown)\n\n'
          'Required for clipboard sync to work when the app is closed.',
      isCompleted: !optimized,
      buttonLabel: !optimized ? 'Done — Finish Setup' : 'Open Battery Settings',
      onPressed: !optimized
          ? () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('onboarding_complete_v2', true);
              widget.onComplete();
            }
          : () => health.openBatterySettings(),
    );
  }

  // ── Generic step card ──────────────────────────────────────────────────────
  Widget _stepCard({
    required int gifIndex,
    required IconData icon,
    required String title,
    required String description,
    String? note,
    required bool isCompleted,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tutorialAsset(gifIndex),
        const SizedBox(height: 16),

        Row(children: [
          Icon(icon,
              color: isCompleted
                  ? const Color(0xFF43A047)
                  : const Color(0xFF00E5FF),
              size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          if (isCompleted)
            const Icon(Icons.check_circle, color: Color(0xFF43A047), size: 20),
        ]),
        const SizedBox(height: 10),
        Text(description,
            style:
                const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  height: 1.5)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: isCompleted
                  ? const Color(0xFF43A047)
                  : const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child:
                Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _stepDot(int step, bool completed) {
    final isActive = _currentStep == step;
    return GestureDetector(
      onTap: () {
        if (step <= _currentStep || completed) setState(() => _currentStep = step);
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed
              ? const Color(0xFF43A047)
              : isActive
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF333333),
        ),
        child: Center(
          child: completed
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : Text('${step + 1}',
                  style: TextStyle(
                    color: isActive ? Colors.black : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  )),
        ),
      ),
    );
  }

  Widget _stepLine() => Expanded(
        child: Container(
            height: 2,
            color: const Color(0xFF333333),
            margin: const EdgeInsets.symmetric(horizontal: 4)),
      );
}
