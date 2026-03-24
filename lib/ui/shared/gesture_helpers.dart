import 'package:flutter/material.dart';

/// Cross-platform constants for touch targets, animation durations, and
/// gesture thresholds. Shared by all UI files that implement interactive
/// elements — enforces consistent UX on both APK and EXE.
class GestureConstants {
  GestureConstants._();

  /// Minimum tap target per Material spec / Apple HIG: 48×48dp
  static const double minTouchTarget = 48.0;

  /// Swipe-to-delete: dismiss threshold (fraction of tile width)
  static const double swipeDismissThreshold = 0.45;

  /// Long-press duration before context menu appears
  static const Duration longPressDuration = Duration(milliseconds: 400);

  /// Snackbar undo window
  static const Duration undoWindow = Duration(seconds: 4);

  /// Smooth-scroll physics used in all Vault lists
  static const ScrollPhysics vaultScrollPhysics = BouncingScrollPhysics();
}

/// Wraps a widget with a full-width [InkWell] that guarantees a minimum
/// touch target of [GestureConstants.minTouchTarget] on every axis.
class AccessibleTapTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  const AccessibleTapTarget({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget w = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: GestureConstants.minTouchTarget,
          minHeight: GestureConstants.minTouchTarget,
        ),
        child: child,
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

/// Shows a styled [BottomSheet] context menu with icon-labelled actions.
///
/// Each action is an [AccessibleTapTarget], so minimum 48dp touch target
/// is always guaranteed on mobile.
Future<void> showClipContextMenu(
  BuildContext context, {
  required List<ClipContextAction> actions,
  required String title,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions.map((a) => AccessibleTapTarget(
            onTap: () { Navigator.of(context).pop(); a.onTap(); },
            child: ListTile(
              leading: Icon(a.icon, color: a.destructive ? Colors.redAccent : const Color(0xFF00E5FF)),
              title: Text(
                a.label,
                style: TextStyle(
                  color: a.destructive ? Colors.redAccent : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )),
        ],
      ),
    ),
  );
}

class ClipContextAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const ClipContextAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// Builds a row of device-filter chips with guaranteed 48dp tap targets.
class DeviceFilterChipRow extends StatelessWidget {
  final List<String> devices;
  final String activeDevice;
  final void Function(String) onSelected;

  const DeviceFilterChipRow({
    super.key,
    required this.devices,
    required this.activeDevice,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: GestureConstants.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: devices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = devices[i];
          final selected = d == activeDevice;
          return GestureDetector(
            onTap: () => onSelected(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minWidth: GestureConstants.minTouchTarget),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(24),
                border: selected ? null : Border.all(color: Colors.white12),
              ),
              child: Text(
                d,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
