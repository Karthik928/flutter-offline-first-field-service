// import 'dart:async';
// import 'package:flutter/foundation.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'package:FieldService_app/main.dart';

// import '../offline/request_envelope.dart';

// /// LocationTrackingService handles periodic location updates to the backend.
// ///
// /// Features:
// /// - Starts background location tracking when employee punches in
// /// - Sends GPS coordinates to API every 1 minute
// /// - Handles location permissions gracefully
// /// - Properly cleans up timers to prevent memory leaks
// /// - Manages single timer instance to avoid concurrent updates
// class LocationTrackingService {
//   // Singleton pattern to ensure only one instance
//   static final LocationTrackingService _instance =
//       LocationTrackingService._internal();

//   factory LocationTrackingService() {
//     return _instance;
//   }

//   LocationTrackingService._internal();

//   // Timer for periodic location updates
//   Timer? _locationTimer;

//   // HTTP client for API calls
//   final http.Client _httpClient = http.Client();

//   // Flag to track if currently tracking
//   bool get isTracking => _locationTimer != null;
//   bool isSending = false;

//   // Constants
//   static const Duration _updateInterval = Duration(minutes: 1);
//   static const Duration _locationTimeout = Duration(seconds: 10);
//   static const String _locationEndpoint = '/api/employee/update-location';

//   /// Start periodic location tracking.
//   ///
//   /// This method:
//   /// - Checks for location permissions
//   /// - Starts a 1-minute periodic timer
//   /// - Immediately sends the first location update
//   /// - Handles permission denials gracefully
//   ///
//   /// Returns true if tracking started successfully, false otherwise.
//   Future<bool> startTracking() async {
//     // Avoid starting multiple timers
//     if (isTracking) {
//       debugPrint('🟡 Location tracking already active');
//       return true;
//     }

//     // Check and request location permission
//     final hasPermission = await _checkAndRequestLocationPermission();
//     if (!hasPermission) {
//       debugPrint('❌ Location permission denied - tracking not started');
//       return false;
//     }

//     debugPrint('✅ Starting location tracking...');

//     // Send first location update immediately
//     await sendLocation();

//     // Start periodic timer for subsequent updates

//     _locationTimer = Timer.periodic(_updateInterval, (_) async {
//       if (isSending) return;

//       isSending = true;
//       await sendLocation();
//       isSending = false;
//     });

//     debugPrint('✅ Location tracking started (1 minute interval)');
//     return true;
//   }

//   /// Stop periodic location tracking.
//   ///
//   /// Cancels the timer and prevents further location updates.
//   void stopTracking() {
//     if (!isTracking) {
//       debugPrint('🟡 Location tracking not active');
//       return;
//     }

//     _locationTimer?.cancel();
//     _locationTimer = null;

//     debugPrint('✅ Location tracking stopped');
//   }

//   /// Send current location to the backend.
//   ///
//   /// This method:
//   /// - Gets the current GPS position
//   /// - Calls the location update API endpoint
//   /// - Handles errors gracefully without interrupting tracking
//   Future<void> sendLocation() async {
//     try {
//       // Get current position
//       final position = await _getCurrentPosition();
//       if (position == null) {
//         debugPrint('⚠️ Could not obtain location');
//         return;
//       }

//       debugPrint(
//         '📍 Sending location: ${position.latitude}, ${position.longitude}',
//       );

//       // Prepare request body
//       final body = {
//         'latitude': position.latitude,
//         'longitude': position.longitude,
//       };

//       // Send to API
//       await _sendLocationToAPI(body);
//     } catch (e) {
//       // Log error but don't interrupt tracking
//       debugPrint('❌ Error sending location: $e');
//     }
//   }

//   /// Check location permission status and request if necessary.
//   ///
//   /// Returns true if permission is granted, false otherwise.
//   Future<bool> _checkAndRequestLocationPermission() async {
//     try {
//       // Check current permission status
//       LocationPermission permission = await Geolocator.checkPermission();

//       if (permission == LocationPermission.denied) {
//         // Request permission
//         permission = await Geolocator.requestPermission();

//         if (permission == LocationPermission.denied) {
//           debugPrint('❌ Location permission denied by user');
//           return false;
//         }
//       }

//       // Check for permanently denied permission
//       if (permission == LocationPermission.deniedForever) {
//         debugPrint('❌ Location permission permanently denied');
//         return false;
//       }

//       // Check if location services are enabled on the device
//       final serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         debugPrint('❌ Location services are disabled on device');
//         return false;
//       }

//       debugPrint('✅ Location permission granted');
//       return true;
//     } catch (e) {
//       debugPrint('❌ Error checking location permission: $e');
//       return false;
//     }
//   }

//   /// Get current GPS position with timeout.
//   ///
//   /// Tries to get cached position first, then requests fresh position.
//   /// Uses medium accuracy for a balance between speed and accuracy.
//   ///
//   /// Returns null if position cannot be obtained.
//   Future<Position?> _getCurrentPosition() async {
//     try {
//       // Try cached position first (faster, acceptable for 1-min intervals)
//       try {
//         final lastKnown = await Geolocator.getLastKnownPosition();
//         if (lastKnown != null) {
//           return lastKnown;
//         }
//       } catch (e) {
//         debugPrint('⚠️ Could not get cached position: $e');
//       }

//       // Get fresh position with timeout
//       final position = await Geolocator.getCurrentPosition(
//         locationSettings: const LocationSettings(
//           accuracy: LocationAccuracy.low,
//           timeLimit: _locationTimeout,
//         ),
//       );

//       return position;
//     } on TimeoutException {
//       debugPrint('⚠️ Location request timeout');
//       return null;
//     } catch (e) {
//       debugPrint('❌ Error getting current position: $e');
//       return null;
//     }
//   }

//   /// Send location data to the backend API.
//   ///
//   /// Uses the existing apiClient from main.dart.
//   /// Handles 401 responses (token expiration) separately.
//   Future<void> _sendLocationToAPI(Map<String, dynamic> body) async {
//     try {
//       final response = await apiClient
//           .sendOrQueue(
//             method: HttpVerb.post,
//             path: _locationEndpoint,
//             jsonBody: body,
//           )
//           .timeout(const Duration(seconds: 15));

//       if (response == null) {
//         debugPrint('⚠️ API response is null (may be queued offline)');
//         return;
//       }

//       if (response.statusCode == 401) {
//         debugPrint('❌ API returned 401 - Token expired');
//         stopTracking();
//         return;
//       }

//       if (response.statusCode == 200 || response.statusCode == 201) {
//         debugPrint('✅ Location update sent successfully');
//         return;
//       }

//       debugPrint('⚠️ API returned status ${response.statusCode}');
//     } on TimeoutException {
//       debugPrint('⚠️ Location API request timeout');
//     } catch (e) {
//       debugPrint('❌ Error sending location to API: $e');
//       rethrow;
//     }
//   }

//   /// Clean up resources.
//   /// Call this when the app is closing or when user logs out.
//   void dispose() {
//     stopTracking();
//     _httpClient.close();
//   }
// }
