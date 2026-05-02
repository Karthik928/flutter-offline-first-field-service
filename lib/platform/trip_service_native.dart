// lib/platform/trip_service_native.dart
import 'dart:async';
import 'package:flutter/services.dart';

class TripServiceNative {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.myapp.trip/native_service',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.myapp.trip/native_service/events',
  );

  static Stream<Map<String, dynamic>>? _eventStream;

  /// Get event stream for trip updates (ISSUE 2 FIX: Use this for EventChannel subscription)
  /// This stream emits snapshots on start, throttled updates, and stop
  static Stream<Map<String, dynamic>> getEventStream() {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map<Map<String, dynamic>>((event) {
          if (event is Map) {
            return Map<String, dynamic>.from(event);
          }
          return <String, dynamic>{};
        })
        .handleError((error) {});

    return _eventStream!;
  }

  /// Convenience getter alias for getEventStream()
  static Stream<Map<String, dynamic>> get tripUpdates => getEventStream();

  /// Start trip with native service
  /// Returns true if successful
  static Future<bool> startTrip({
    required String tripId,
    required String tripStartUtc,
    double? initialDistanceMeters,
    String? authToken,
    String? apiBaseUrl, // ← ADD
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'startTrip',
        {
          'tripId': tripId,
          'tripStartUtc': tripStartUtc,
          'initialDistanceMeters': initialDistanceMeters,
          'authToken': authToken,
          'apiBaseUrl': apiBaseUrl, // ← ADD
        },
      );
      return result?['ok'] == true;
    } catch (e) {
      throw Exception('Failed to start trip: $e');
    }
  }

  /// Stop active trip
  /// Returns true if successful
  static Future<bool> stopTrip() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'stopTrip',
      );
      return result?['ok'] == true;
    } catch (e) {
      throw Exception('Failed to stop trip: $e');
    }
  }

  /// Get current active trip snapshot (null if no active trip)
  static Future<Map<String, dynamic>?> getActiveTripSnapshot() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getActiveTripSnapshot',
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      throw Exception('Failed to get trip snapshot: $e');
    }
  }

  /// Check if service is running
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'isServiceRunning',
      );
      return result?['running'] == true;
    } catch (e) {
      return false;
    }
  }
}
