// lib/widgets/trip_screen_resume.dart

import 'package:flutter/material.dart';

class TripResumeDialog {
  static Future<void> show(BuildContext context, String startTime) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text("Resume Trip"),
          content: Text("A trip started at $startTime is still running."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, "finish"),
              child: const Text("Finish Trip"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, "resume"),
              child: const Text("Resume"),
            ),
          ],
        );
      },
    );
  }
}
