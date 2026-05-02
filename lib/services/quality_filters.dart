// lib/core/quality_filters.dart
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class QualityFilters {
  static const double maxAccuracyM = 70;   // discard very noisy fixes
  static const double maxSpeedMps  = 60;   // ~216 km/h hard cap

  static bool isValidSample({
    required double accuracyM,
    required double speedMps,
    required bool isMocked,
  }) {
    if (isMocked) return false;
    if (accuracyM > maxAccuracyM) return false;
    if (speedMps.isFinite && speedMps > maxSpeedMps) return false;
    return true;
  }

  /// Returns meters; returns 0 for tiny jitter < 1.5m
  static double safeDistance(LatLng a, LatLng b) {
    final d = Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
    return d < 1.5 ? 0.0 : d;
  }
}
