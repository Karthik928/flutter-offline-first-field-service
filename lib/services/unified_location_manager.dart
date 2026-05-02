import 'dart:async';
import 'package:flutter/foundation.dart';
//import 'package:geolocator/geolocator.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/services/trip_service_bridge.dart';

enum LocationMode { idle, punchTracking, tripTracking }

class UnifiedLocationManager {
  static final UnifiedLocationManager _instance =
      UnifiedLocationManager._internal();

  factory UnifiedLocationManager() => _instance;

  UnifiedLocationManager._internal();

  Timer? _pollTimer;
  bool _nativeTripActive = false;

  LocationMode _mode = LocationMode.idle;

  //static const Duration _timeout = Duration(seconds: 10);

  LocationMode get mode => _mode;

  /// ----------------------------------------------------------
  /// PUBLIC CONTROL METHODS
  /// ----------------------------------------------------------

  Future<void> startPunchTracking() async {
    if (_nativeTripActive) {
      debugPrint("⚠️ Trip active — punch polling not started");
      return;
    }

    // Always refresh the native service state (and token) even if Flutter thinks punch tracking is already active.
    // This prevents missing authToken propagation after an app restart while the native service is still running.
    final token = await SecureStorageService.getToken();
    debugPrint("🧩 startPunchTracking token present=${token != null}");

    if (_mode == LocationMode.punchTracking) {
      debugPrint(
        "🟢 Punch tracking already active — refreshing native service state",
      );
      await TripServiceBridge.startPunchTracking(authToken: token);
      return;
    }

    debugPrint("🟢 Punch tracking started");

    _mode = LocationMode.punchTracking;
    await TripServiceBridge.startPunchTracking(authToken: token);
  }

  Future<void> stopPunchTracking() async {
    debugPrint("🛑 Punch tracking stopped");

    await TripServiceBridge.stopPunchTracking();

    if (_mode == LocationMode.punchTracking) {
      _mode = LocationMode.idle;
    }
  }

  /// Call when trip starts
  void onTripStarted() {
    debugPrint("🚗 Trip started — switching to native service");

    _nativeTripActive = true;
    _mode = LocationMode.tripTracking;

    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Call when trip ends
  void onTripStopped() {
    debugPrint("🏁 Trip ended");

    _nativeTripActive = false;

    if (_mode == LocationMode.tripTracking) {
      _mode = LocationMode.idle;
    }
  }

  /// ----------------------------------------------------------
  /// LOCATION
  /// ----------------------------------------------------------

  // Future<Position?> _getPosition() async {
  //   try {
  //     final last = await Geolocator.getLastKnownPosition();

  //     if (last != null) {
  //       return last;
  //     }

  //     final pos = await Geolocator.getCurrentPosition(
  //       locationSettings: const LocationSettings(
  //         accuracy: LocationAccuracy.low,
  //       ),
  //     ).timeout(_timeout);

  //     return pos;
  //   } catch (e) {
  //     debugPrint("⚠️ Location error: $e");
  //     return null;
  //   }
  // }

  /// ----------------------------------------------------------
  /// API
  /// ----------------------------------------------------------

  // Future<void> _sendLocation(Position pos) async {
  //   try {
  //     final body = {"latitude": pos.latitude, "longitude": pos.longitude};

  //     final res = await apiClient.sendOrQueue(
  //       method: HttpVerb.post,
  //       path: AppConfig.sendLocation,
  //       jsonBody: body,
  //     );

  //     if (res == null) {
  //       debugPrint("📦 Location queued offline");
  //       return;
  //     }

  //     if (res.statusCode == 200 || res.statusCode == 201) {
  //       debugPrint("📍 Location sent");
  //     } else {
  //       debugPrint("⚠️ Location API returned ${res.statusCode}");
  //     }
  //   } catch (e) {
  //     debugPrint("❌ Location send error: $e");
  //   }
  // }

  /// ----------------------------------------------------------
  /// CLEANUP
  /// ----------------------------------------------------------

  void dispose() {
    _pollTimer?.cancel();
  }
}
