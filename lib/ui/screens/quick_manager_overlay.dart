import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/providers/clip_provider.dart';
import '../../bridge/windows_bridge.dart';

/// Callback used to close the overlay and restore the main app window.
typedef OnOverlayClose = Future<void> Function();

/// --------------------------------------------------------------------------
/// Windows Quick-Paste overlay — modelled after the Win+V clipboard panel.
///
/// **Key design:** The OS window IS the panel. There is no transparent backdrop
/// or positioning widget. The window is sized to exactly match the card, with
/// no title bar and no frame. Dragging the header calls
/// `windowManager.startDragging()`, which moves the real HWND across the
/// display. Losing focus (clicking anywhere else) auto-closes the panel,
/// exactly like Win+V.
/// --------------------------------------------------------------------------
class QuickManagerOverlay extends StatefulWidget {
  final OnOverlayClose onClose;
  const QuickManagerOverlay({super.key, required this.onClose});

  @override
  State<QuickManagerOverlay> createState() => _QuickManagerOverlayState();
}

class _QuickManagerOverlayState extends State<QuickManagerOverlay>
    with WindowListener {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // ── Win+V behaviour: click anywhere outside → close ───────────────────────
  @override
  void onWindowBlur() {
    _close();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    return false;
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final clipProvider = context.watch<ClipProvider>();
    final clips = clipProvider.filteredClips.take(50).toList();

    return Scaffold(
      // The scaffold background IS the panel background — no transparency
      // needed.  The OS window is sized to match this exactly.
      backgroundColor: const Color(0xFF1C1C1C),
      body: Column(
        children: [
          // ── Draggable header (moves the OS window) ──────────────────────
          GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF303030)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.content_paste_go,
                        color: Color(0xFF00E5FF), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Quick Paste',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white38, size: 18),
                      tooltip: 'Close (Esc)',
                      splashRadius: 16,
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Clip list (scrollable, like Win+V) ─────────────────────────
          Expanded(
            child: clips.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.content_paste_off,
                            color: Colors.white24, size: 42),
                        SizedBox(height: 10),
                        Text('Vault is empty',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    itemCount: clips.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (ctx, i) {
                      final clip = clips[i];
                      return _ClipRow(
                        content: clip.content,
                        deviceName: clip.deviceName,
                        isPinned: clip.isPinned,
                        onTap: () async {
                          final bridge = ctx.read<WindowsBridge>();
                          await bridge.setClipboard(clip.content);
                          await _close();
                          // Brief pause for focus to return to the target app
                          await Future.delayed(
                              const Duration(milliseconds: 300));
                          await bridge.simulatePaste();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Individual clip row (matches Win+V visual style) ─────────────────────────
class _ClipRow extends StatefulWidget {
  final String content;
  final String deviceName;
  final bool isPinned;
  final VoidCallback onTap;

  const _ClipRow({
    required this.content,
    required this.deviceName,
    required this.isPinned,
    required this.onTap,
  });

  @override
  State<_ClipRow> createState() => _ClipRowState();
}

class _ClipRowState extends State<_ClipRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF2A2A2A) : const Color(0xFF222222),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                  : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device label + pin
              Row(
                children: [
                  if (widget.isPinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin,
                          color: Color(0xFF00E5FF), size: 11),
                    ),
                  Text(
                    widget.deviceName,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Content preview
              Text(
                widget.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
