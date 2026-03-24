import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'dart:convert';
import '../main.dart';
import '../core/services/tray_service.dart';
import '../bridge/clipboard_channel.dart';
import '../bridge/windows_bridge.dart';
import '../core/services/health_service.dart';
import '../core/providers/clip_provider.dart';
import '../core/services/key_service.dart';
import '../core/services/database_service.dart';
import 'widgets/battery_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _startOnBoot = false;
  bool _loadingBoot = true;
  bool _syncImages = true;

  @override
  void initState() {
    super.initState();
    _loadBootState();
    _loadPrefs();
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

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _syncImages = prefs.getBool('syncImages') ?? true;
      });
    }
  }

  Future<void> _savePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = !kIsWeb && Platform.isWindows;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final health = context.watch<HealthService>();

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        title: const Text('Settings Hub', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── SYSTEM HEALTH ────────────────────────────────────────────────
          _sectionHeader('SYSTEM HEALTH'),
          _card(children: [
            _statusTile(
              icon: Icons.wifi,
              title: 'Network',
              subtitle: 'Multi-device signaling bus',
              trailing: _badge(
                health.isMqttConnected ? 'Signal: Online' : 'Signal: Offline',
                health.isMqttConnected ? const Color(0xFF00E5FF) : Colors.redAccent,
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _statusTile(
              icon: Icons.hub,
              title: 'Mesh Status',
              subtitle: 'Direct E2E connection state',
              trailing: _badge('${health.activeWebRTCPeers} Trusted Peers Online', const Color(0xFF43A047)),
            ),

            // ── Android-specific health ──
            if (isAndroid) ...[
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.accessibility_new, color: Colors.white54),
                title: const Text('Accessibility Service', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Background clipboard watcher', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: health.isAccessibilityEnabled
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : OutlinedButton(
                        onPressed: () => health.fixAccessibility(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          foregroundColor: Colors.redAccent,
                        ),
                        child: const Text('Fix'),
                      ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.layers, color: Colors.white54),
                title: const Text('Display Over Other Apps', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Required for Quick Paste overlay', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: health.canDrawOverlays
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : OutlinedButton(
                        onPressed: () => health.openOverlaySettings(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.amber),
                          foregroundColor: Colors.amber,
                        ),
                        child: const Text('Grant'),
                      ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.battery_alert, color: Colors.white54),
                title: const Text('Power Management', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Prevents OS from killing sync engine', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: !health.isBatteryOptimized
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : OutlinedButton(
                        onPressed: () => showBatteryOptimizationDialog(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.amber),
                          foregroundColor: Colors.amber,
                        ),
                        child: const Text('Disable'),
                      ),
              ),
            ],

            // ── Windows-specific health ──
            if (isWindows) ...[
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.keyboard, color: Colors.white54),
                title: const Text('Global Hotkey', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Overlay shortcut status', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: health.isHotkeyRegistered
                    ? const Icon(Icons.check_circle, color: Color(0xFF43A047))
                    : const Icon(Icons.error_outline, color: Colors.redAccent),
              ),
            ],
          ]),

          const SizedBox(height: 24),

          // ── GLOBAL CONTROLS ───────────────────────────────────────────────
          _sectionHeader('GLOBAL CONTROLS'),
          _card(children: [
            ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.white54),
              title: const Text('Local Device Name', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Broadcast identity in Mesh (Tap to edit)', style: TextStyle(color: Colors.white38, fontSize: 12)),
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
                  
                  // Persist the name
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('custom_device_name', newName);
                  if (context.mounted) {
                    context.read<KeyService>().deviceLabel = newName;
                    await context.read<DatabaseService>().updateSourceDeviceName(oldName, newName);
                  }

                  await provider.broadcastDeviceNameChange(oldName, newName);
                  if (mounted) setState(() {});
                }
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.image, color: Colors.white54),
              title: const Text('Sync Images', style: TextStyle(color: Colors.white)),
              subtitle: const Text('High-bandwidth ecosystem feature', style: TextStyle(color: Colors.white38, fontSize: 12)),
              value: _syncImages,
              activeColor: const Color(0xFF00E5FF),
              onChanged: (v) {
                setState(() => _syncImages = v);
                _savePref('syncImages', v);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              title: const Text('Clear All History', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Wipes SQL on ALL connected devices', style: TextStyle(color: Colors.white38, fontSize: 12)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Clear Grid?', style: TextStyle(color: Colors.redAccent)),
                    content: const Text('This will delete all unpinned clips from this device AND broadcast a wipe command to all peers.', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('WIPE MESH', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await context.read<ClipProvider>().clearAllHistory(broadcast: true);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ecosystem history wiped.')));
                }
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.deepOrangeAccent),
              title: const Text('Reset All Local Data', style: TextStyle(color: Colors.deepOrangeAccent)),
              subtitle: const Text('Clears device key, paired peers, clips & preferences — fresh start', style: TextStyle(color: Colors.white38, fontSize: 12)),
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
                      '  • Reset your device identity (new ID)\n'
                      '  • Clear all settings\n\n'
                      'The app will restart. This is irreversible.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('RESET', style: TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  final db = context.read<DatabaseService>();
                  await db.deleteAllClips();
                  await db.setConfig('private_key', '');
                  await db.setConfig('public_key', '');
                  // Remove all peers
                  final peers = await db.getPeers();
                  for (final p in peers) { await db.removePeer(p.peerId); }
                  // Clear SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All data cleared. Please restart the app.')),
                    );
                  }
                }
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── WINDOWS SPECIFIC ─────────────────────────────────────────────
          if (isWindows) ...[
            _sectionHeader('WINDOWS SPECIFIC'),
            _card(children: [
              if (_loadingBoot)
                const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              else
                ListTile(
                  leading: const Icon(Icons.rocket_launch, color: Colors.white54),
                  title: const Text('Launch on Startup', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Automatic background sync utility layer', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: Switch(
                    value: _startOnBoot,
                    activeColor: const Color(0xFF00E5FF),
                    onChanged: (v) async {
                      if (isWindows) {
                        final bridge = context.read<WindowsBridge>();
                        final ok = await bridge.setStartOnBoot(v);
                        if (ok) setState(() => _startOnBoot = v);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? '${v ? "Added to" : "Removed from"} Windows startup.' : 'Registry write failed.')),
                          );
                        }
                      }
                    },
                  ),
                ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.keyboard, color: Colors.white54),
                title: const Text('Hotkey Configuration', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Active binding: Alt + Shift + V (default)', style: TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: OutlinedButton(
                  onPressed: () async {
                    HotKey? newHotKey;
                    await showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          backgroundColor: const Color(0xFF252528),
                          title: const Text('Record New Hotkey', style: TextStyle(color: Colors.white)),
                          content: SizedBox(
                            width: 300,
                            child: HotKeyRecorder(
                              onHotKeyRecorded: (hotKey) {
                                newHotKey = hotKey;
                              },
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Save', style: TextStyle(color: Color(0xFF00E5FF))),
                            ),
                          ],
                        );
                      },
                    );

                    if (newHotKey != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('custom_hotkey', jsonEncode(newHotKey!.toJson()));
                      
                      if (context.mounted) {
                        final clipProvider = context.read<ClipProvider>();
                        final windowsBridge = context.read<WindowsBridge>();
                        final healthService = context.read<HealthService>();
                        final trayService = TrayService(); 
                        await registerGlobalHotkey(clipProvider, windowsBridge, trayService, healthService);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Hotkey updated!')),
                        );
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    foregroundColor: const Color(0xFF00E5FF),
                  ),
                  child: const Text('Remap'),
                ),
              ),
            ]),
          ],

          // ── ANDROID SETUP ────────────────────────────────────────────────
          if (isAndroid) ...[
            _sectionHeader('QUICK PASTE SETUP'),
            _card(children: [
              ListTile(
                leading: const Icon(Icons.dashboard_customize, color: Colors.white54),
                title: const Text('Quick Settings Tile', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Swipe down → Edit tiles (✏️) → Drag "ClipSync" to the top row',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: const Icon(Icons.info_outline, color: Color(0xFF00E5FF), size: 20),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.white54),
                title: const Text('Re-run Setup Wizard', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Walks through permissions and Quick Settings setup', style: TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('onboarding_complete_v2', false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Wizard will show on next app restart.')),
                    );
                  }
                },
              ),
            ]),
          ],

          const SizedBox(height: 60),
          const Center(
            child: Text('ClipSync Ecosystem\nSECURE MESH VERIFIED',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Row(children: [
      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    ]),
  );

  Widget _card({required List<Widget> children}) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
      ],
    ),
    child: Column(children: children),
  );

  Widget _statusTile({required IconData icon, required String title, required String subtitle, required Widget trailing}) =>
    ListTile(
      leading: Icon(icon, color: Colors.white54),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: trailing,
    );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
  );
}
