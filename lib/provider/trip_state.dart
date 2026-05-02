// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';

// class TripState extends ChangeNotifier {
//   bool _tripStarted = false;
//   bool _tripCompleted = false;

//   DateTime? _startTime;
//   Duration _elapsedTime = Duration.zero;
//   double _distanceTraveled = 0.0;

//   LatLng? _lastPosition;

//   // Getters
//   bool get tripStarted => _tripStarted;
//   bool get tripCompleted => _tripCompleted;
//   Duration get elapsedTime => _elapsedTime;
//   double get distanceTraveled => _distanceTraveled;
//   LatLng? get lastPosition => _lastPosition;

//   // Setters
//   set lastPosition(LatLng? pos) {
//     _lastPosition = pos;
//     notifyListeners();
//   }

//   void startTrip() {
//     _tripStarted = true;
//     _tripCompleted = false;
//     _startTime = DateTime.now();
//     _elapsedTime = Duration.zero;
//     _distanceTraveled = 0.0;
//     notifyListeners();
//   }

//   void updateElapsedTime() {
//     if (_startTime != null) {
//       _elapsedTime = DateTime.now().difference(_startTime!);
//       notifyListeners();
//     }
//   }

//   void addDistance(double meters) {
//     _distanceTraveled += meters / 1000; // convert to km
//     notifyListeners();
//   }

//   void endTrip() {
//     _tripStarted = false;
//     _tripCompleted = true;
//     notifyListeners();
//   }

//   void resetTrip() {
//     _tripStarted = false;
//     _tripCompleted = false;
//     _startTime = null;
//     _elapsedTime = Duration.zero;
//     _distanceTraveled = 0.0;
//     _lastPosition = null;
//     notifyListeners();
//   }
// }
