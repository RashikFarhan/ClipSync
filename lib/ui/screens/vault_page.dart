import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/clip_provider.dart';
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
            Image.asset('assets/logo.png', width: 24, height: 24, color: const Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            const Text('ClipSync', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 12),
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle))
          ],
        ),
      ),
      body: CustomScrollView(
        physics: GestureConstants.vaultScrollPhysics,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: DeviceFilterBar()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
          if (pinned.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 16),
                child: Row(
                  children: const [
                    Icon(Icons.push_pin, color: Color(0xFF00E5FF), size: 18),
                    SizedBox(width: 8),
                    Text('Pinned Clips', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 16),
                child: Row(
                  children: const [
                    Icon(Icons.history, color: Colors.white54, size: 18),
                    SizedBox(width: 8),
                    Text('Recent Activity', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                  child: Text("Vault Empty. Inject Test Data via icon above.", 
                     style: TextStyle(color: Colors.white54)),
                )
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
            onTap: () {}, // Handled directly in clip_tile long press and pin button now, but could be quick copy here
            onLongPress: () {}, // Delegate long press to context menu in ClipTile directly
          ),
        ),
        childCount: items.length,
      ),
    );
  }
}
