// lib/helpers/battery_whitelist_prompt.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class BatteryWhitelistPrompt {
  static Future<void> show(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Battery Optimization"),
        content: const Text(
          "To prevent trip from stopping, please disable battery optimization.",
        ),
        actions: [
          ElevatedButton(
            child: const Text("Open Settings"),
            onPressed: () async {
              await Permission.ignoreBatteryOptimizations.request();
              await openAppSettings();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
