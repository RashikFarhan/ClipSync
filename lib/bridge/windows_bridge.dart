import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side bridge to the Win32 clipboard injector,
/// Windows registry startup toggle, and Ctrl+V simulation.
class WindowsBridge {
  static const MethodChannel _channel =
      MethodChannel('com.antigravity.clipsync/windows');

  /// Writes [text] directly into the Windows OS clipboard.
  Future<bool> setClipboard(String text) async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('setWindowsClipboard', {'text': text});
      return result ?? false;
    } catch (e) {
      debugPrint('[WindowsBridge] setClipboard error: $e');
      return false;
    }
  }

  /// Forces the Windows C++ side to start the clipboard format listener.
  Future<bool> startClipboardListener() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod<bool>('startClipboardListener');
      return result ?? false;
    } catch (e) {
      debugPrint('[WindowsBridge] startClipboardListener error: $e');
      return false;
    }
  }

  /// Reads from Windows Registry to check if auto-start is enabled.
  Future<bool> getStartOnBoot() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod<bool>('getStartOnBoot');
      return result ?? false;
    } catch (e) {
      debugPrint('[WindowsBridge] getStartOnBoot error: $e');
      return false;
    }
  }

  /// Adds or removes the app EXE path from HKCU\\...\\Run.
  Future<bool> setStartOnBoot(bool enable) async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
          'setStartOnBoot', {'enable': enable});
      return result ?? false;
    } catch (e) {
      debugPrint('[WindowsBridge] setStartOnBoot error: $e');
      return false;
    }
  }

  /// Simulates a Ctrl+V keystroke to paste clipboard content
  /// into the currently focused window.
  Future<bool> simulatePaste() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod<bool>('simulatePaste');
      return result ?? false;
    } catch (e) {
      debugPrint('[WindowsBridge] simulatePaste error: $e');
      return false;
    }
  }
}
