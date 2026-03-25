import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../main.dart';
import '../core/services/tray_service.dart';
import '../core/services/database_service.dart';
import '../bridge/clipboard_channel.dart';
import '../bridge/windows_bridge.dart';
import '../core/services/health_service.dart';
import '../core/providers/clip_provider.dart';
import '../core/services/key_service.dart';
import 'widgets/battery_dialog.dart';

// ── Quick "upcoming" badge widget ────────────────────────────────────────────
class _UpcomingBadge extends StatelessWidget {
  const _UpcomingBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: const Text('Upcoming',
            style: TextStyle(
                color: Colors.amber,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Windows boot toggle
  bool _startOnBoot = false;
  bool _loadingBoot = true;

  // Clipboard settings
  int _maxClipItems = 50; // Only 50 is active

  // Device limit (max 3 active)

  @override
  void initState() {
    super.initState();
    _loadBootState();
    _loadSettings();
  }

  Future<void> _loadBootState() async {
    if (!kIsWeb && Platform.isWindows) {
      final bridge = context.read<WindowsBridge>();
      final val = await bridge.getStartOnBoot();
      if (mounted) setState(() { _startOnBoot = val; _loadingBoot = false; });
    } else {
      if (mounted) setState(() => _loadingBoot = false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _maxClipItems = prefs.getInt('maxClipItems') ?? 50;
      });
      DatabaseService.maxClips = _maxClipItems;
    }
  }


  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12, top: 4),
        child: Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF00E5FF), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
        ]),
      );

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: children),
      );

  Widget _statusTile(
          {required IconData icon,
          required String title,
          required String subtitle,
          required Widget trailing}) =>
      ListTile(
        leading: Icon(icon, color: Colors.white54),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: trailing,
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _divider() => const Divider(color: Colors.white12, height: 1);

  // ── Upcoming tile (greyed, no interaction) ────────────────────────────────
  Widget _upcomingTile(
      {required IconData icon,
      required String title,
      required String subtitle,
      Widget? trailing}) =>
      Opacity(
        opacity: 0.45,
        child: ListTile(
          leading: Icon(icon, color: Colors.white54),
          title: Row(
            children: [
              Text(title, style: const TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              const _UpcomingBadge(),
            ],
          ),
          subtitle: Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: trailing,
          enabled: false,
        ),
      );

  @override
  Widget build(BuildContext context) {
    bool isWindows = !kIsWeb && Platform.isWindows;
    bool isAndroid = !kIsWeb && Platform.isAndroid;
    final health = context.watch<HealthService>();

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        children: [

          // ── SYSTEM STATUS ────────────────────────────────────────────────
          _sectionHeader('SYSTEM STATUS'),
          _card(children: [
            _statusTile(
              icon: Icons.wifi,
              title: 'Network',
              subtitle: 'Multi-device signaling',
              trailing: _badge(
                health.isMqttConnected ? 'Online' : 'Offline',
                health.isMqttConnected ? const Color(0xFF00E5FF) : Colors.redAccent,
              ),
            ),
            _divider(),
            _statusTile(
              icon: Icons.hub,
              title: 'Mesh',
              subtitle: 'Direct E2E peers',
              trailing: _badge(
                '${health.activeWebRTCPeers} peer(s) connected',
                const Color(0xFF43A047),
              ),
            ),
            if (isAndroid) ...[
              _divider(),
              ListTile(
                leading: const Icon(Icons.accessibility_new, color: Colors.white54),
                title: const Text('Accessibility Service', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Required for overlay paste', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: health.isAccessibilityEnabled
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : OutlinedButton(
                        onPressed: () => health.fixAccessibility(),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), foregroundColor: Colors.redAccent),
                        child: const Text('Fix'),
                      ),
              ),
              _divider(),
              ListTile(
                leading: const Icon(Icons.layers, color: Colors.white54),
                title: const Text('Display Over Other Apps', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Required for Quick Paste overlay', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: health.canDrawOverlays
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : OutlinedButton(
                        onPressed: () => health.openOverlaySettings(),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amber), foregroundColor: Colors.amber),
                        child: const Text('Grant'),
                      ),
              ),
              _divider(),
              ListTile(
                leading: const Icon(Icons.battery_alert, color: Colors.white54),
                title: const Text('Power Management', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Prevents OS from killing sync', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: !health.isBatteryOptimized
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : OutlinedButton(
                        onPressed: () => showBatteryOptimizationDialog(context),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amber), foregroundColor: Colors.amber),
                        child: const Text('Fix'),
                      ),
              ),
            ],
            if (isWindows) ...[
              _divider(),
              _statusTile(
                icon: Icons.keyboard,
                title: 'Global Hotkey',
                subtitle: 'Overlay shortcut: Alt + Shift + V',
                trailing: health.isHotkeyRegistered
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : const Icon(Icons.error_outline, color: Colors.redAccent),
              ),
            ],
          ]),

          // ── SYNC ─────────────────────────────────────────────────────────
          _sectionHeader('SYNC'),
          _card(children: [
            ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.white54),
              title: const Text('Local Device Name', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Tap to edit your device name', style: TextStyle(color: Colors.white38, fontSize: 12)),
              trailing: Text(
                context.read<ClipboardChannel>().currentDeviceName,
                style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
              ),
              onTap: () async {
                final clipboard = context.read<ClipboardChannel>();
                final provider = context.read<ClipProvider>();
                String newName = clipboard.currentDeviceName;
                final changed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: const Text('Device Name', style: TextStyle(color: Colors.white)),
                    content: TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                      ),
                      controller: TextEditingController(text: newName),
                      onChanged: (v) => newName = v.trim(),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save', style: TextStyle(color: Color(0xFF00E5FF)))),
                    ],
                  ),
                );
                if (changed == true && newName.isNotEmpty && newName != clipboard.currentDeviceName) {
                  final oldName = clipboard.currentDeviceName;
                  clipboard.setDeviceName(newName);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('custom_device_name', newName);
                  if (context.mounted) {
                    Provider.of<KeyService>(context, listen: false).deviceLabel = newName;
                    await Provider.of<DatabaseService>(context, listen: false).updateSourceDeviceName(oldName, newName);
                  }
                  await provider.broadcastDeviceNameChange(oldName, newName);
                  if (context.mounted) setState(() {});
                }
              },
            ),
            _divider(),
            // Sync Images — disabled, upcoming
            _upcomingTile(
              icon: Icons.image,
              title: 'Sync Images',
              subtitle: 'Image clipboard sync across devices',
              trailing: Switch(value: false, onChanged: null, activeThumbColor: Colors.white38),
            ),
          ]),

          // ── CLIPBOARD ────────────────────────────────────────────────────
          _sectionHeader('CLIPBOARD'),
          _card(children: [
            // Max clipboard items — only 50 is active
            ListTile(
              leading: const Icon(Icons.storage, color: Colors.white54),
              title: const Text('Max Clips Per Device', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                  'Oldest unpinned clips are removed when limit is reached',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              trailing: DropdownButton<int>(
                value: 50,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                onChanged: (_) {}, // always 50 for now
                items: [
                  const DropdownMenuItem(value: 50, child: Text('50', style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(
                    value: 100,
                    enabled: false,
                    child: Row(children: const [
                      Text('100 ', style: TextStyle(color: Colors.white38)),
                      _UpcomingBadge(),
                    ]),
                  ),
                  DropdownMenuItem(
                    value: 200,
                    enabled: false,
                    child: Row(children: const [
                      Text('200 ', style: TextStyle(color: Colors.white38)),
                      _UpcomingBadge(),
                    ]),
                  ),
                  DropdownMenuItem(
                    value: 500,
                    enabled: false,
                    child: Row(children: const [
                      Text('500 ', style: TextStyle(color: Colors.white38)),
                      _UpcomingBadge(),
                    ]),
                  ),
                ],
              ),
            ),
            _divider(),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              title: const Text('Clear All History', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Wipes clips on this device and all connected peers', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Clear History?', style: TextStyle(color: Colors.redAccent)),
                    content: const Text(
                      'This will delete all unpinned clips from this device and broadcast a wipe to all peers.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('WIPE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  final clipProvider = Provider.of<ClipProvider>(context, listen: false);
                  await clipProvider.clearAllHistory(broadcast: true);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History cleared.')));
                }
              },
            ),
          ]),

          // ── DEVICES ─────────────────────────────────────────────────────
          _sectionHeader('DEVICES'),
          _card(children: [
            ListTile(
              leading: const Icon(Icons.devices, color: Colors.white54),
              title: const Text('Max Devices Per Session', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                  'Maximum number of devices allowed in a mesh session',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              trailing: DropdownButton<int>(
                value: 3,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                onChanged: (_) {},
                items: [
                  const DropdownMenuItem(value: 3, child: Text('3', style: TextStyle(color: Colors.white))),
                  ...List.generate(7, (i) => i + 4).map((n) => DropdownMenuItem(
                    value: n,
                    enabled: false,
                    child: Row(children: [
                      Text('$n ', style: const TextStyle(color: Colors.white38)),
                      const _UpcomingBadge(),
                    ]),
                  )),
                ],
              ),
            ),
          ]),

          // ── PLATFORM SPECIFIC ─────────────────────────────────────────────
          if (isWindows) ...[
            _sectionHeader('WINDOWS'),
            _card(children: [
              if (_loadingBoot)
                const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              else
                ListTile(
                  leading: const Icon(Icons.rocket_launch, color: Colors.white54),
                  title: const Text('Launch on Startup', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Start minimized to tray on Windows login', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: Switch(
                    value: _startOnBoot,
                    activeThumbColor: const Color(0xFF00E5FF),
                    onChanged: (v) async {
                      if (context.mounted) {
                        final bridge = Provider.of<WindowsBridge>(context, listen: false);
                        final ok = await bridge.setStartOnBoot(v);
                        if (context.mounted) {
                          if (ok) setState(() => _startOnBoot = v);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? '${v ? "Added to" : "Removed from"} startup.' : 'Registry write failed.')),
                          );
                        }
                      }
                    },
                  ),
                ),
              _divider(),
              ListTile(
                leading: const Icon(Icons.keyboard, color: Colors.white54),
                title: const Text('Hotkey', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Overlay shortcut: Alt + Shift + V', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: OutlinedButton(
                  onPressed: () async {
                    HotKey? newHotKey;
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF252528),
                        title: const Text('Record New Hotkey', style: TextStyle(color: Colors.white)),
                        content: SizedBox(
                          width: 300,
                          child: HotKeyRecorder(onHotKeyRecorded: (h) => newHotKey = h),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Save', style: TextStyle(color: Color(0xFF00E5FF)))),
                        ],
                      ),
                    );
                    if (newHotKey != null && context.mounted) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('custom_hotkey', jsonEncode(newHotKey!.toJson()));
                      if (context.mounted) {
                        final clipProvider = Provider.of<ClipProvider>(context, listen: false);
                        final windowsBridge = Provider.of<WindowsBridge>(context, listen: false);
                        final healthService = Provider.of<HealthService>(context, listen: false);
                        final trayService = TrayService();
                        await registerGlobalHotkey(clipProvider, windowsBridge, trayService, healthService);
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hotkey updated!')));
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF00E5FF)), foregroundColor: const Color(0xFF00E5FF)),
                  child: const Text('Remap'),
                ),
              ),
            ]),
          ],

          if (isAndroid) ...[
            _sectionHeader('ANDROID'),
            _card(children: [
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.white54),
                title: const Text('Re-run Setup Wizard', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Walk through permissions again', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('onboarding_complete_v2', false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Wizard will show on next app restart.')),
                    );
                  }
                },
              ),
            ]),
          ],

          // ── DANGER ZONE ──────────────────────────────────────────────────
          _sectionHeader('DANGER ZONE'),
          _card(children: [
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.deepOrangeAccent),
              title: const Text('Reset All Local Data', style: TextStyle(color: Colors.deepOrangeAccent)),
              subtitle: const Text('Clears device key, paired peers, clips & preferences', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Reset All Data?', style: TextStyle(color: Colors.deepOrangeAccent)),
                    content: const Text(
                      'This will:\n'
                      '  • Delete all clipboard history\n'
                      '  • Remove all paired devices\n'
                      '  • Reset your device identity\n'
                      '  • Clear all settings\n\n'
                      'This action is irreversible.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('RESET', style: TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  final db = Provider.of<DatabaseService>(context, listen: false);
                  final messenger = ScaffoldMessenger.of(context);
                  await db.deleteAllClips();
                  await db.setConfig('private_key', '');
                  await db.setConfig('public_key', '');
                  final peers = await db.getPeers();
                  for (final p in peers) { await db.removePeer(p.peerId); }
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (context.mounted) {
                    messenger.showSnackBar(const SnackBar(content: Text('All data cleared. Please restart the app.')));
                  }
                }
              },
            ),
          ]),

          // ── VERSION ──────────────────────────────────────────────────────
          const Center(
            child: Text(
              'ClipSync v0.1.0 — Public Beta\nDecentralized · E2E Encrypted · Open Mesh',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 1.2, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
