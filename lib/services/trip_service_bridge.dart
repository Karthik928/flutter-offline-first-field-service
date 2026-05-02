import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TripServiceBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.myapp.trip/native_service',
  );

  /// Internal retry helper: handles SERVICE_ERROR with exponential backoff.
  /// Retries up to 5 times with delays: 500ms, 1s, 2s, 4s, 8s.
  /// All operations have a 15-second timeout.
  static Future<void> _invokeMethodWithRetry(
    String method, {
    dynamic arguments,
    int retryCount = 0,
  }) async {
    try {
      await _channel
          .invokeMethod(method, arguments)
          .timeout(const Duration(seconds: 15));
    } on PlatformException catch (e) {
      // SERVICE_ERROR means service binding is still in progress. Retry with backoff.
      if (e.code == 'SERVICE_ERROR' && retryCount < 5) {
        final backoffMs = 500 * (1 << retryCount); // 500, 1000, 2000, 4000, 8000
        debugPrint(
            'TripServiceBridge.$method: Attempt ${retryCount + 1}/5 failed ($e), '
            'retrying in ${backoffMs}ms');
        await Future.delayed(Duration(milliseconds: backoffMs));
        return _invokeMethodWithRetry(method,
            arguments: arguments, retryCount: retryCount + 1);
      }
      // Not a transient error, or retries exhausted
      debugPrint("TripServiceBridge.$method: Failed after ${retryCount + 1} attempts: $e");
    } catch (e, s) {
      debugPrint("TripServiceBridge.$method: Unexpected error: $e");
      debugPrintStack(stackTrace: s);
    }
  }

  /// Start employee punch tracking
  ///
  /// `authToken` is optional and is passed to the native layer for
  /// tracking API authentication.
  static Future<void> startPunchTracking({String? authToken}) async {
    return _invokeMethodWithRetry(
      'startPunchTracking',
      arguments: {'authToken': authToken},
    );
  }

  /// Stop employee punch tracking
  static Future<void> stopPunchTracking() async {
    return _invokeMethodWithRetry('stopPunchTracking');
  }

  /// Notify native service that trip started
  static Future<void> tripStarted() async {
    return _invokeMethodWithRetry('tripStarted');
  }

  /// Notify native service that trip ended
  static Future<void> tripStopped() async {
    return _invokeMethodWithRetry('tripStopped');
  }
}
