import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/clip_item.dart';
import '../../core/providers/clip_provider.dart';
import '../shared/gesture_helpers.dart';

/// A card tile representing a single clipboard entry.
///
/// Gesture contract (Task 2 audit):
///   • Tap       → [onTap] callback (quick copy / paste overlay)
///   • Long-press → context menu with Pin, Copy, Delete (≥ 48dp target)
///   • Swipe left → confirm-delete with Undo snackbar
///
/// Touch targets: all icon buttons use [AccessibleTapTarget] (48×48dp min).
class ClipTile extends StatelessWidget {
  final ClipItem clip;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ClipTile({
    super.key,
    required this.clip,
    required this.onTap,
    required this.onLongPress,
  });

  IconData _getIcon() {
    switch (clip.type) {
      case 'link':  return Icons.link;
      case 'code':  return Icons.code;
      case 'image': return Icons.image;
      default:      return Icons.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(clip.id),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: GestureConstants.swipeDismissThreshold},
      confirmDismiss: (_) async => _confirmDelete(context),
      onDismissed: (_) {
        context.read<ClipProvider>().deleteClip(clip.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Clip removed'),
            duration: GestureConstants.undoWindow,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'UNDO',
              textColor: const Color(0xFF00E5FF),
              onPressed: () {
                // Re-insert the clip
                context.read<ClipProvider>().loadClips();
              },
            ),
          ),
        );
        HapticFeedback.lightImpact();
      },
      background: _swipeBackground(),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showContextMenu(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: clip.isPinned ? const Color(0xFF1A2A2E) : const Color(0xFF252528),
            borderRadius: BorderRadius.circular(24),
            border: clip.isPinned
                ? Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5), width: 1.5)
                : null,
            boxShadow: clip.isPinned
                ? [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.08), blurRadius: 12)]
                : null,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // ── Header row ─────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(_getIcon(), color: const Color(0xFF00E5FF), size: 20),
                  // Device label chip
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        clip.deviceName.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Content ───────────────────────────────────────────────────
              Text(
                clip.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 8),

              // ── Footer row ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTimestamp(clip.timestamp),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  // Pin button — guaranteed 48dp touch target
                  AccessibleTapTarget(
                    tooltip: clip.isPinned ? 'Unpin' : 'Pin',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<ClipProvider>().togglePin(clip);
                    },
                    child: Icon(
                      clip.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: clip.isPinned ? const Color(0xFF00E5FF) : Colors.white24,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground() => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    decoration: BoxDecoration(
      color: Colors.redAccent.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
  );

  Future<bool?> _confirmDelete(BuildContext context) async => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Delete Clip?', style: TextStyle(color: Colors.white)),
      content: Text(
        '"${clip.content.substring(0, clip.content.length.clamp(0, 60))}…"',
        style: const TextStyle(color: Colors.white54),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );

  void _showContextMenu(BuildContext context) {
    showClipContextMenu(
      context,
      title: clip.content.substring(0, clip.content.length.clamp(0, 60)),
      actions: [
        ClipContextAction(
          icon: clip.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: clip.isPinned ? 'Unpin' : 'Pin to Top',
          onTap: () => context.read<ClipProvider>().togglePin(clip),
        ),
        ClipContextAction(
          icon: Icons.copy,
          label: 'Copy',
          onTap: () => Clipboard.setData(ClipboardData(text: clip.content)),
        ),
        ClipContextAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => context.read<ClipProvider>().deleteClip(clip.id),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

