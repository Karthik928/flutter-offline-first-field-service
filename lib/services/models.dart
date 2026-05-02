// lib/core/models.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationSample {
  final DateTime ts;           // UTC
  final double lat;
  final double lng;
  final double accuracyM;      // meters
  final double speedMps;       // from OS (may be -1 if unknown)
  final bool isMocked;         // Android only

  LocationSample({
    required this.ts,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.speedMps,
    required this.isMocked,
  });

  Null get speed => null;
}

class TripSession {
  final String id;             // UUID
  final DateTime startUtc;
  DateTime? endUtc;
  double distanceM = 0;        // accumulated
  int durationSec = 0;         // accumulated

  // Optional references
  LatLng? origin;
  LatLng? destination;

  TripSession({
    required this.id,
    required this.startUtc,
    this.origin,
    this.destination,
  });
}
