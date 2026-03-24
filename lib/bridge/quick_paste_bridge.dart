import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/services/database_service.dart';

/// Bridge between the native Android QuickPasteActivity and the Dart clip database.
/// The QuickPasteActivity calls 'getRecentClips' via MethodChannel and we respond
/// with the latest 50 clips serialized as List<Map>.
class QuickPasteBridge {
  static const MethodChannel _channel =
      MethodChannel('com.antigravity.clipsync/quickpaste');
  final DatabaseService _dbService;

  QuickPasteBridge(this._dbService) {
    if (!kIsWeb && Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'getRecentClips') {
      final clips = await _dbService.getClips();
      final serialized = clips
          .take(50)
          .map((c) => <String, dynamic>{
                'id': c.id,
                'content': c.content,
                'type': c.type,
                'deviceName': c.deviceName,
                'isPinned': c.isPinned,
                'timestamp': c.timestamp.millisecondsSinceEpoch,
              })
          .toList();
      // Return the data as a result — but since this is setMethodCallHandler,
      // we need to respond. The handler returns the value automatically.
      return serialized;
    } else if (call.method == 'performPaste') {
      // The native side handles the paste via AccessibilityService.
      // This is called from the native side, nothing to do on Dart side.
      debugPrint('[QuickPasteBridge] Paste performed natively for: ${call.arguments}');
    }
  }
}
