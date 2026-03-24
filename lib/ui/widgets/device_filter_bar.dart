import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/clip_provider.dart';
import '../shared/gesture_helpers.dart';

class DeviceFilterBar extends StatelessWidget {
  const DeviceFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClipProvider>();
    return DeviceFilterChipRow(
      devices: provider.availableDevices,
      activeDevice: provider.activeDeviceFilter,
      onSelected: provider.setDeviceFilter,
    );
  }
}
