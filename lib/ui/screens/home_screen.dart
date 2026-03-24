import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/health_service.dart';
import '../widgets/onboarding_wizard.dart';
import 'vault_page.dart';
import 'devices_screen.dart';
import '../settings_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _showOnboarding = false;

  final List<Widget> _pages = const [
    VaultPage(),
    DevicesScreen(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOnboarding();
    });
  }

  Future<void> _checkOnboarding() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_complete_v2') ?? false;

    if (!completed && mounted) {
      setState(() => _showOnboarding = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: Stack(
        children: [
          _pages[_currentIndex],
          if (_showOnboarding)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: SingleChildScrollView(
                  child: OnboardingWizard(
                    onComplete: () {
                      setState(() => _showOnboarding = false);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF202020), width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF1A1A1A),
          selectedItemColor: const Color(0xFF00E5FF),
          unselectedItemColor: Colors.grey,
          currentIndex: _currentIndex,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'VAULT'),
            BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'DEVICES'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'SETTINGS'),
          ],
        ),
      ),
    );
  }
}
