// lib/helpers/permissions_handler.dart

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class AppPermissions {
  /// Foreground + background location
  static Future<bool> ensureLocationPermissions(BuildContext context) async {
    final fg = await Permission.locationWhenInUse.request();
    if (!fg.isGranted) return false;

    if (Platform.isAndroid) {
      final bg = await Permission.locationAlways.request();
      return bg.isGranted;
    }

    // iOS "Always" must be enabled manually
    return true;
  }

  /// Battery optimization bypass (Android only)
  static Future<void> openBatteryOptimizationSettings() async {
    if (Platform.isAndroid) {
      await Permission.ignoreBatteryOptimizations.request();
      await openAppSettings();
    }
  }
}
