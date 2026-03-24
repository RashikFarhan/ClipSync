import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/providers/clip_provider.dart';
import '../../bridge/windows_bridge.dart';

/// A frameless, always-on-top overlay window for quick paste on Windows.
/// Shown when the user presses the global hotkey (Win+Shift+V).
class QuickManagerOverlay extends StatelessWidget {
  const QuickManagerOverlay({super.key});

  // No static show() — overlay is now pushed as a full route by main.dart

  @override
  Widget build(BuildContext context) {
    final clipProvider = context.watch<ClipProvider>();
    final clips = clipProvider.filteredClips.take(50).toList();

    return Material(
      color: Colors.black, // Fully opaque to hide the app skeleton
      child: SafeArea(
        child: Center(
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.content_paste_go, color: Color(0xFF00E5FF), size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Quick Paste',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // Clip grid
                if (clips.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.content_paste_off, color: Colors.white24, size: 48),
                        SizedBox(height: 12),
                        Text('Vault is empty', style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: clips.length,
                      itemBuilder: (ctx, i) {
                        final clip = clips[i];
                        return _QuickClipTile(
                          content: clip.content,
                          deviceName: clip.deviceName,
                          isPinned: clip.isPinned,
                          onTap: () async {
                            final bridge = context.read<WindowsBridge>();
                            // 1. Set clipboard
                            await bridge.setClipboard(clip.content);
                            // 2. Pop the overlay route (window is still shown)
                            if (context.mounted) Navigator.of(context).pop();
                            // 3. Brief pause so the window can hide (done in main.dart)
                            //    and the OS shifts focus back to the previous app
                            await Future.delayed(const Duration(milliseconds: 350));
                            // 4. Simulate Ctrl+V — by now focus is in the target app
                            await bridge.simulatePaste();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickClipTile extends StatelessWidget {
  final String content;
  final String deviceName;
  final bool isPinned;
  final VoidCallback onTap;

  const _QuickClipTile({
    required this.content,
    required this.deviceName,
    required this.isPinned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPinned
                ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isPinned) const Icon(Icons.push_pin, color: Color(0xFF00E5FF), size: 12),
                if (isPinned) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    deviceName,
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                content,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
