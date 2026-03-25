import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/providers/clip_provider.dart';
import '../../bridge/clipboard_channel.dart';
import '../../models/clip_item.dart';
import '../widgets/clip_tile.dart';
import '../widgets/device_filter_bar.dart';
import '../shared/gesture_helpers.dart';

class VaultPage extends StatelessWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClipProvider>();
    final pinned = provider.pinnedClips;
    final recent = provider.recentClips;

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/logo.png',
                width: 24, height: 24, color: const Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            const Text('ClipSync',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 12),
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Color(0xFF00E5FF), shape: BoxShape.circle)),
          ],
        ),
        // Android only: manual sync button
        actions: [
          if (!kIsWeb && Platform.isAndroid)
            _SyncNowButton(),
        ],
      ),
      body: CustomScrollView(
        physics: GestureConstants.vaultScrollPhysics,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: DeviceFilterBar()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          if (pinned.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16, bottom: 16),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, color: Color(0xFF00E5FF), size: 18),
                    SizedBox(width: 8),
                    Text('Pinned Clips',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _buildSliverList(pinned),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],

          if (recent.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 16, bottom: 16),
                child: Row(
                  children: [
                    Icon(Icons.history, color: Colors.white54, size: 18),
                    SizedBox(width: 8),
                    Text('Recent Activity',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _buildSliverList(recent),
            ),
          ],

          if (pinned.isEmpty && recent.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'Vault is empty.\nCopy anything on another device to start syncing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  SliverList _buildSliverList(List<ClipItem> items) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipTile(
            clip: items[index],
            onTap: () {},
            onLongPress: () {},
          ),
        ),
        childCount: items.length,
      ),
    );
  }
}

/// Android-only manual "Sync Clipboard Now" button in the AppBar.
/// Reads the current system clipboard and pushes it to the vault.
class _SyncNowButton extends StatefulWidget {
  @override
  State<_SyncNowButton> createState() => _SyncNowButtonState();
}

class _SyncNowButtonState extends State<_SyncNowButton> {
  bool _syncing = false;

  Future<void> _doSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      // Read current clipboard content
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clipboard is empty'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      // Push through the clipboard channel (which handles dedup + broadcast)
      final channel = context.read<ClipboardChannel>();
      channel.simulateLocalCopy(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✓ Synced: ${text.length > 30 ? '${text.substring(0, 30)}…' : text}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _syncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF00E5FF)),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.cloud_upload_outlined,
                  color: Color(0xFF00E5FF)),
              tooltip: 'Sync Current Clipboard',
              onPressed: _doSync,
            ),
    );
  }
}
