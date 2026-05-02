// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

//import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/services/attendance_service.dart';
import 'package:FieldService_app/services/models.dart';
import 'package:FieldService_app/services/trip_manager.dart';
import 'package:FieldService_app/services/quality_filters.dart';
import 'package:FieldService_app/platform/trip_service_native.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:FieldService_app/services/unified_location_manager.dart';
//import 'package:top_snackbar_flutter/custom_snack_bar.dart';
//import 'package:top_snackbar_flutter/top_snack_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;

import '../services/trip_services.dart';
import '../widgets/trip_map_widget.dart';
import '../widgets/trip_controls_widget.dart';

import 'package:FieldService_app/offline/failed_record_model.dart';
import 'package:FieldService_app/offline/failed_record_store.dart';

enum StartTripSyncState { idle, localStarted, backendPending, backendConfirmed }

Future<void> _setStartState(StartTripSyncState state) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('startTripSyncState', state.name);
}

Future<StartTripSyncState> _getStartState() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('startTripSyncState');
  return StartTripSyncState.values.firstWhere(
    (e) => e.name == raw,
    orElse: () => StartTripSyncState.idle,
  );
}

class TripScreen extends StatefulWidget {
  final String? initialSearchQuery;

  const TripScreen({super.key, this.initialSearchQuery});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

// Tunables
const double _kStickinessFraction = 0.02; // 2% improvement required

// ---------- ADD: Kalman filter and spoof detector helpers ----------

/// Simple 1D Kalman filter (fast & tiny) — use one per coordinate/speed.
class KalmanFilter1D {
  final double q; // process noise
  final double r; // measurement noise
  double x; // state
  double p; // estimation error

  KalmanFilter1D({this.q = 0.0001, this.r = 0.1, double? init})
    : x = init ?? 0.0,
      p = 1.0;

  double filter(double measurement) {
    // predict
    p += q;
    // update
    final k = p / (p + r);
    x = x + k * (measurement - x);
    p = (1 - k) * p;
    return x;
  }

  void set(double v) {
    x = v;
    p = 1.0;
  }
}

/// Lightweight spoof detector with simple heuristics and a score.
/// This intentionally only flags / scores suspicious behaviour and does not
/// immediately break the trip — suspicious samples are ignored.
class SpoofDetector {
  int _consecutiveSpoofFlags = 0;
  int _totalFlags = 0;
  final int flagThreshold;
  final int lockoutThreshold;

  SpoofDetector({this.flagThreshold = 3, this.lockoutThreshold = 6});

  void reset() {
    _consecutiveSpoofFlags = 0;
  }

  void markFlag() {
    _consecutiveSpoofFlags++;
    _totalFlags++;
  }

  void clearFlag() {
    _consecutiveSpoofFlags = 0;
  }

  bool isSuspicious() => _consecutiveSpoofFlags >= flagThreshold;

  bool isLockout() => _totalFlags >= lockoutThreshold;

  // NEW: expose simple diagnostics for HUD
  int get consecutiveFlags => _consecutiveSpoofFlags;
  int get totalFlags => _totalFlags;
}

class _TripScreenState extends State<TripScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  // Trip flags
  bool _isTripStarted = false;
  bool _tripCompleted = false;
  Duration _elapsedTime = Duration.zero;

  Future<void> _persistTripCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tripCompleted', value);
  }

  Future<void> _clearTripSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tripCompleted', false);
    // await prefs.remove('currentTripId');
    // await prefs.remove('currentTripStartTime');
    // await prefs.remove('currentTripDate');
    // await prefs.remove('currentTripStartLat');
    // await prefs.remove('currentTripStartLng');
    // await prefs.remove('currentTripStartKm');
    // await prefs.remove('currentTripLocalId');
    // await prefs.remove('totalKm');
  }

  // Trip stats
  Duration _tripDuration = Duration.zero;
  double _kmCovered = 0.0;
  DateTime? _tripStartTime;
  double _distanceTraveled = 0.0;
  LatLng? _lastPosition;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<Map<String, dynamic>>? _nativeTripSubscription;

  // Map and location
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  LatLng? _currentLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = [];
  List<LatLng> _routePointsFull = []; // full path for preview
  double? _routeDistance;
  double? _routeDuration;
  bool _isEditing = false;
  bool _isMapLoading = true;
  Timer? _tripTimer;
  Timer? _etaRefreshTimer; // NEW: 1-min auto-refresh timer
  int _recenterTick = 0;

  // Search UI
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchField = false;
  Timer? _searchDebounce;
  List<PlacePrediction> _predictions = [];
  Set<Polyline> _polylines = <Polyline>{};

  // Follow/camera
  bool _followMe = true;
  Timer? _followResumeTimer;
  double _followZoom = 16.0;
  DateTime _lastCamAnim = DateTime.fromMillisecondsSinceEpoch(0);
  static const _followMinMeters = 8.0;
  static const _followMinMs = 600;

  String? _pendingInitialSearchQuery;

  // ---------- Smooth navigation camera ----------
  double _smoothedBearing = 0.0;
  final double _bearingAlpha = 0.18; // smoothing factor (0.1–0.25 recommended)
  double _lastSpeedMps = 0.0;

  // dynamic tilt
  final double _navMinTilt = 35.0;
  final double _navMaxTilt = 55.0;

  // Remaining & ETA
  double? _distanceRemainingKm;
  double? _durationRemainingMin;
  DateTime? _lastEtaRefreshAt;
  double? _lastValidDurationMin; // NEW: preserve last valid ETA
  double? _lastValidDistanceKm; // NEW: preserve last valid distance
  bool _etaRefreshing = false; // NEW: changed to non-final for tracking

  // Mode
  bool _isFreeRide = false; // false => Navigated

  // ADD: loader state
  String? _loadingMessage;
  bool get _isBusy => _loadingMessage != null;

  DateTime? _lastFixAt; // track timestamp of last accepted fix

  // Tunables for sanity checks
  static const double _gpsAccuracyCutoffM = 65.0; // ignore very noisy fixes
  static const double _maxSpeedMps = 22.0; // ~80 km/h hard cap (2-wheeler)
  static const double _maxJumpMeters = 120.0; // discard absurd 1-tick jumps
  // Minimum speed (m/s) to force-accept small steps (helpful for slow riding/walking)
  static const double _minAcceptSpeedMps = 0.4; // ~1.4 km/h

  // Use Free-Ride style card when trip is running WITHOUT destination
  bool get _useFreeRideProgressCard => _isTripStarted && _destination == null;

  // UI-only getters for the card (controls widget)
  double? get _uiRouteDistance =>
      _useFreeRideProgressCard ? null : _routeDistance;
  double? get _uiRouteDuration =>
      _useFreeRideProgressCard ? null : _routeDuration;
  double? get _uiRemainKm =>
      _useFreeRideProgressCard ? null : _distanceRemainingKm;
  double? get _uiRemainMin =>
      _useFreeRideProgressCard ? null : _durationRemainingMin;
  DateTime? get _uiEtaUpdatedAt =>
      _useFreeRideProgressCard ? null : _lastEtaRefreshAt;

  bool _isStartingTrip = false;
  bool _isEndingTrip = false;

  // ← add this variable so the analyzer can see `session` later in this function
  TripSession? session;

  // ---------- HUD / Debug overlay ----------
  List<String> _hudLines = [];
  final int _hudMaxLines = 7;

  StreamSubscription? _tripHiveSub;

  final FailedRecordStore _failedRecordStore = FailedRecordStore();

  final List<String> _countries = [
    'India',
    'United Arab Emirates',
    'Nepal',
    'Vietnam',
    'Australia',
  ];
  final Map<String, String> _countryCodes = const {
    'India': 'in',
    'United Arab Emirates': 'ae',
    'Nepal': 'np',
    'Vietnam': 'vn',
    'Australia': 'au',
  };

  //bool _startBackendCompleted = false; // true when start API success OR queued

  void _hudLog(String msg) {
    final time = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .substring(0, 12);
    final line = '$time  $msg';
    // insert newest at top
    _hudLines.insert(0, line);
    if (_hudLines.length > _hudMaxLines) {
      _hudLines = _hudLines.sublist(0, _hudMaxLines);
    }
    // update UI
    if (mounted) setState(() {});
  }

  Future<void> _persistTripFailedRecord({
    required String method,
    required String path,
    required Map<String, dynamic>? jsonBody,
    required int statusCode,
    required FailureReason reason,
    String? errorDetail,
  }) async {
    try {
      final id = '${DateTime.now().millisecondsSinceEpoch}';
      final record = FailedRecord(
        id: id,
        envelopeId: id,
        method: method,
        path: path,
        jsonBody: jsonBody,
        headers: const {},
        attachedFileNames: const [],
        lastStatusCode: statusCode,
        failureReason: reason,
        errorDetail: errorDetail,
        enqueuedAt: DateTime.now().toUtc(),
        failedAt: DateTime.now().toUtc(),
        attemptCount: 1,
        recordType: FailedRecord.typeFromPath(path, method),
      );
      await _failedRecordStore.add(record);
    } catch (e) {
      debugPrint('⚠️ Could not persist trip failed record: $e');
    }
  }

  /// Flush pending meters to the UI in a throttled/batched manner.
  ///
  /// - `force: true` forces an immediate flush (used when ending a trip).
  /// - Otherwise it flushes when pending >= `_uiBatchMeters` or when
  ///   `_uiFlushMs` has elapsed since last UI update.
  Future<void> _flushPendingDistanceIfDue({bool force = false}) async {
    final now = DateTime.now();
    final shouldFlush =
        force ||
        _pendingMeters >= _uiBatchMeters ||
        (_lastUiFlushAt == null) ||
        now.difference(_lastUiFlushAt!).inMilliseconds >= _uiFlushMs;

    debugPrint(
      'FLUSH check shouldFlush=$shouldFlush pending=${_pendingMeters.toStringAsFixed(1)} lastFlush=$_lastUiFlushAt',
    );

    if (!shouldFlush || _pendingMeters <= 0.0) return;

    // Move pending meters into TripManager (persist) and sync UI from canonical source
    _pendingMeters = 0.0;
    _lastUiFlushAt = now;

    // ISSUE 4 FIX: Native service is authoritative - DO NOT calculate distance in Flutter
    // Distance comes ONLY from native snapshot via EventChannel
    // This method should NOT accumulate distance when native service is active
    try {
      // Try to get distance from native snapshot (authoritative)
      final snapshot = await TripServiceNative.getActiveTripSnapshot();
      if (snapshot != null && snapshot['distanceMeters'] != null) {
        final nativeDistanceKm =
            (snapshot['distanceMeters'] as num).toDouble() / 1000.0;
        if (mounted) {
          setState(() {
            _distanceTraveled = nativeDistanceKm; // Use native distance only
            // Keep for ETA calculation only
          });
        } else {
          _distanceTraveled = nativeDistanceKm;
        }
        debugPrint(
          'UI FLUSH: Using native distance=${nativeDistanceKm.toStringAsFixed(3)} km',
        );
        _hudLog('UI FLUSH: native distance');
      } else {
        // Fallback: Try TripManager (only if native unavailable)
        final activeKm = TripManager.active?.distanceM;
        if (activeKm != null) {
          if (mounted) {
            setState(() {
              _distanceTraveled = activeKm / 1000.0;
            });
          } else {
            _distanceTraveled = activeKm / 1000.0;
          }
          debugPrint(
            'UI FLUSH: Using TripManager distance=${_distanceTraveled.toStringAsFixed(3)} km (native unavailable)',
          );
        } else {
          debugPrint(
            '⚠️ UI FLUSH: No distance source available (native or TripManager)',
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ UI FLUSH: Error getting native snapshot: $e');
      // Last resort: use TripManager if available
      final activeKm = TripManager.active?.distanceM;
      if (activeKm != null) {
        if (mounted) {
          setState(() {
            _distanceTraveled = activeKm / 1000.0;
          });
        }
      }
    }

    // Ensure immediate UI redraw
    if (mounted) setState(() {});
  }

  void _setLoading(String? msg) {
    if (!mounted) return;
    setState(() => _loadingMessage = msg);
  }

  // Add near other helper methods
  void _timeLog(String label, int ms) {
    _hudLog('$label — ${ms}ms');
    debugPrint('$label — ${ms}ms');
  }

  Future<T> _time<T>(String label, Future<T> Function() fn) async {
    final sw = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      sw.stop();
      _timeLog(label, sw.elapsedMilliseconds);
    }
  }

  double _smoothBearing(double prev, double next, double alpha) {
    // shortest angular distance
    double delta = ((next - prev + 540) % 360) - 180;
    return (prev + delta * alpha + 360) % 360;
  }

  double _tiltForSpeed(double speedMps) {
    if (!speedMps.isFinite) return _navMinTilt;

    // 0–12 m/s ≈ walking → city riding
    final t = (speedMps / 12.0).clamp(0.0, 1.0);
    return _navMinTilt + (t * (_navMaxTilt - _navMinTilt));
  }

  // ADD: loader overlay widget
  Widget _buildLoaderOverlay() {
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF1AB69C),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    _loadingMessage ?? 'Please wait…',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restoreForegroundLink() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;

    final activeId = await FlutterForegroundTask.getData<String>(
      key: 'activeTripId',
    );

    if (activeId != null) {
      // Optional: rebuild UI
      setState(() => _isTripStarted = true);
      debugPrint(
        "🔗 Rebound UI to active foreground service (tripId=$activeId)",
      );
    }
  }

  // ---- Lifecycle ----
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this); // ✅ REQUIRED

    _pendingInitialSearchQuery = widget.initialSearchQuery?.trim();

    _restoreForegroundLink();

    // ISSUE 2 FIX: Subscribe to EventChannel immediately (survives lifecycle)
    _subscribeToNativeTripUpdates();

    _restoreIfTripActive().then((restored) async {
      // ISSUE 1 FIX: Immediately restore map from native snapshot before waiting for GPS
      await _restoreMapFromNativeSnapshot();

      // ISSUE 2 FIX: Hydrate UI from native snapshot on start/resume
      await _hydrateUiFromNativeSnapshot();

      await _getCurrentLocation();
      await _executeInitialSearchQueryIfNeeded();

      // Set tripCompleted to false if trip is not running on app restart/open
      if (!restored) {
        await _persistTripCompleted(false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeInitialSearchQueryIfNeeded();
    });
  }

  Future<void> _executeInitialSearchQueryIfNeeded() async {
    final query = _pendingInitialSearchQuery?.trim();
    if (query == null || query.isEmpty) return;
    _pendingInitialSearchQuery = null;
    if (!mounted || _isTripStarted || _tripCompleted) return;

    setState(() {
      _searchController.text = query;
      _showSearchField = true;
      _isEditing = true;
      _predictions = [];
    });

    _startSearchSession();
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }

    await _searchPlace(query);
  }

  /// ISSUE 2 FIX: Hydrate UI from native snapshot on app start/resume
  Future<void> _hydrateUiFromNativeSnapshot() async {
    try {
      final snapshot = await TripServiceNative.getActiveTripSnapshot();
      if (snapshot != null) {
        if (snapshot['distanceMeters'] != null) {
          final distanceKm =
              (snapshot['distanceMeters'] as num).toDouble() / 1000.0;
          if (mounted) {
            setState(() {
              _distanceTraveled = distanceKm;
            });
            debugPrint(
              '📊 [Hydrate] UI hydrated with native distance: ${distanceKm.toStringAsFixed(3)} km',
            );
          }
        }

        if (snapshot['lastLat'] != null && snapshot['lastLng'] != null) {
          final lat = (snapshot['lastLat'] as num).toDouble();
          final lng = (snapshot['lastLng'] as num).toDouble();
          if (mounted) {
            setState(() {
              _lastPosition = LatLng(lat, lng);
              _currentLocation ??= LatLng(lat, lng);
            });
            debugPrint(
              '📍 [Hydrate] UI hydrated with native position: $lat, $lng',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Hydrate] Failed to hydrate UI from native snapshot: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // ISSUE 2 FIX: Re-hydrate UI when app resumes
    if (state == AppLifecycleState.resumed) {
      _hydrateUiFromNativeSnapshot();
    }
  }

  /// ISSUE 1 FIX: Restore map immediately from native service snapshot
  Future<void> _restoreMapFromNativeSnapshot() async {
    try {
      final snapshot = await TripServiceNative.getActiveTripSnapshot();
      if (snapshot != null &&
          snapshot['lastLat'] != null &&
          snapshot['lastLng'] != null) {
        final lat = (snapshot['lastLat'] as num).toDouble();
        final lng = (snapshot['lastLng'] as num).toDouble();
        final lastLocation = LatLng(lat, lng);

        debugPrint(
          '🗺️ [MapRestore] Restoring map to native snapshot: $lat, $lng',
        );

        setState(() {
          _currentLocation = lastLocation;
          _lastPosition = lastLocation;
          _recenterTick++; // Trigger map recenter
        });

        // Immediately center map if controller is ready
        _mapController.future.then((controller) {
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: lastLocation, zoom: 16),
            ),
          );
        });
        return;
      }
    } catch (e) {
      debugPrint('⚠️ [MapRestore] Failed to get native snapshot: $e');
    }

    // Fallback: Try getLastLocation if snapshot is null
    try {
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        final lastLocation = LatLng(lastPos.latitude, lastPos.longitude);
        debugPrint(
          '🗺️ [MapRestore] Using getLastKnownPosition fallback: ${lastPos.latitude}, ${lastPos.longitude}',
        );
        setState(() {
          _currentLocation = lastLocation;
          _lastPosition = lastLocation;
          _recenterTick++;
        });
        _mapController.future.then((controller) {
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: lastLocation, zoom: 16),
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('⚠️ [MapRestore] getLastKnownPosition also failed: $e');
    }
  }

  /// ISSUE 2 FIX: Subscribe to native EventChannel for live trip updates
  /// This subscription survives lifecycle changes and updates UI in real-time
  void _subscribeToNativeTripUpdates() {
    _nativeTripSubscription?.cancel();
    _nativeTripSubscription = TripServiceNative.getEventStream().listen(
      (snapshot) {
        if (!mounted) return;

        try {
          // ISSUE 4 FIX: Update distance ONLY from native snapshot (authoritative)
          if (snapshot['distanceMeters'] != null) {
            final distanceM = (snapshot['distanceMeters'] as num).toDouble();
            setState(() {
              _distanceTraveled =
                  distanceM / 1000.0; // Convert to km - native is authoritative
            });
            debugPrint(
              '📊 [NativeUpdate] Distance updated from EventChannel: ${_distanceTraveled.toStringAsFixed(3)} km',
            );
          }

          // Update last position if available
          if (snapshot['lastLat'] != null && snapshot['lastLng'] != null) {
            final lat = (snapshot['lastLat'] as num).toDouble();
            final lng = (snapshot['lastLng'] as num).toDouble();
            setState(() {
              _lastPosition = LatLng(lat, lng);
              _currentLocation ??= LatLng(lat, lng);
            });
          }

          // Handle API status events (success/failure/skipped)
          // if (snapshot['type'] == 'tracking_api') {
          //   final status = snapshot['status'] as String?;
          //   final overlay = Overlay.of(context);

          //   if (status == 'success') {
          //     showTopSnackBar(
          //       overlay,
          //       CustomSnackBar.success(
          //         message: 'Tracking API sent successfully',
          //       ),
          //     );
          //   } else if (status == 'failed') {
          //     showTopSnackBar(
          //       overlay,
          //       CustomSnackBar.error(message: 'Tracking API failed'),
          //     );
          //   }
          // }

          // Handle error snapshots
          if (snapshot['error'] != null) {
            debugPrint('⚠️ [NativeUpdate] Service error: ${snapshot['error']}');
          }
        } catch (e) {
          debugPrint('⚠️ [NativeUpdate] Error processing snapshot: $e');
        }
      },
      onError: (e) {
        debugPrint('⚠️ [NativeUpdate] EventChannel stream error: $e');
        // Re-subscribe on error to maintain connection
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _subscribeToNativeTripUpdates();
          }
        });
      },
      cancelOnError: false, // Keep subscription alive even on errors
    );
    debugPrint('✅ [NativeUpdate] EventChannel subscription established');
  }

  // @override
  // void didChangeAppLifecycleState(AppLifecycleState state) {
  //   if (state == AppLifecycleState.resumed) {
  //     _syncUiFromTripManager();
  //   }
  // }

  // Future<void> _startHiveTripWatcher() async {
  //   final box = await Hive.openBox('current_trip');

  //   _tripHiveSub?.cancel();
  //   _tripHiveSub = box.watch(key: 'active').listen((event) {
  //     final data = event.value;
  //     if (data is! Map) return;
  //     if (!mounted) return;

  //     final dm = data['distance_m'];
  //     final ds = data['duration_sec'];

  //     setState(() {
  //       if (dm is num) {
  //         _distanceTraveled = dm.toDouble() / 1000.0;
  //       }
  //       if (ds is int) {
  //         _elapsedTime = Duration(seconds: ds);
  //       }
  //     });
  //   });
  // }

  /// STEP 5 — Restore UI when TripManager reports an unfinished trip
  /// STEP 5 — Restore UI when TripManager reports an unfinished trip
  Future<bool> _restoreIfTripActive() async {
    // assign to the class field so other methods can read it
    session = TripManager.active; // static getter from your Step 1–3 patches
    if (session == null) return false;

    // ISSUE 4 FIX: Get distance from native snapshot first (authoritative source)
    double restoredDistance = 0.0;

    final state = await _getStartState();
    if (state == StartTripSyncState.backendPending) {
      debugPrint("🔁 Retrying StartTrip sync...");
      _sendTripStartApi(startKmReading: 0, skipLocalGuard: true);
    }

    try {
      final snapshot = await TripServiceNative.getActiveTripSnapshot();
      if (snapshot != null && snapshot['distanceMeters'] != null) {
        restoredDistance =
            (snapshot['distanceMeters'] as num).toDouble() / 1000.0;
        debugPrint(
          '📊 [Restore] Using native distance: ${restoredDistance.toStringAsFixed(3)} km',
        );
      } else {
        // Fallback to TripManager if native snapshot unavailable
        restoredDistance = (session!.distanceM / 1000.0);
        debugPrint(
          '📊 [Restore] Using TripManager distance: ${restoredDistance.toStringAsFixed(3)} km',
        );
      }
    } catch (e) {
      debugPrint(
        '⚠️ [Restore] Failed to get native snapshot, using TripManager: $e',
      );
      restoredDistance = (session!.distanceM / 1000.0);
    }

    // --------------------------------------------------
    // 1. Restore UI flags
    // --------------------------------------------------
    setState(() {
      _isTripStarted = true;
      _tripCompleted = false;

      _tripStartTime = session!.startUtc.toLocal();
      _elapsedTime = DateTime.now().difference(_tripStartTime!);

      _distanceTraveled = restoredDistance; // Use native distance
      _lastPosition = session!.origin;

      _destination = session!.destination;
      _isFreeRide = (session!.destination == null);
    });

    await _persistTripCompleted(false);

    // --------------------------------------------------
    // 2. Resume the trip timer
    // --------------------------------------------------
    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _tripStartTime == null) return;
      setState(() {
        _elapsedTime = DateTime.now().difference(_tripStartTime!);
      });
    });

    // --------------------------------------------------
    // 3. Recreate your Geolocator stream (reuse your existing logic)
    // --------------------------------------------------
    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) async {
          await _handlePosition(pos, fromRestore: true);
        });

    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ REQUIRED
    _positionStream?.cancel();
    _nativeTripSubscription?.cancel();
    _tripTimer?.cancel();
    _etaRefreshTimer?.cancel();
    _followResumeTimer?.cancel();
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _tripHiveSub?.cancel();
    super.dispose();
  }

  LatLng? _tryParseLatLng(String raw) {
    // Normalize separators
    final s = raw
        .trim()
        .replaceAll(RegExp(r'[;|]'), ',')
        .replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(
      r'^([+-]?\d{1,2}(?:\.\d+)?)[,\s]+([+-]?\d{1,3}(?:\.\d+)?)$',
    ).firstMatch(s);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lon = double.tryParse(m.group(2)!);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  // ---- Location ----
  Future<void> _getCurrentLocation() async {
    try {
      if (!mounted) return;
      setState(() => _isMapLoading = true);

      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _isMapLoading = false);
        return;
      }

      // Try last known position first for faster loading
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          final currentPosition = position;
          if (!mounted) return;
          setState(() {
            _currentLocation = LatLng(
              currentPosition.latitude,
              currentPosition.longitude,
            );
            _isMapLoading = false;
            _recenterTick++; // nudge map
          });
          return; // Use last known, no need for fresh
        }
      } catch (e) {
        debugPrint("Last known position failed: $e");
      }

      // Get fresh position with shorter timeout
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5), // Reduced from 10 to 5 seconds
        ),
      );
      if (!mounted) return;
      final currentPosition = position;
      setState(() {
        _currentLocation = LatLng(
          currentPosition.latitude,
          currentPosition.longitude,
        );
        _isMapLoading = false;
        _recenterTick++; // nudge map
      });
    } catch (e) {
      debugPrint("Error getting location: $e");
      if (!mounted) return;
      setState(() => _isMapLoading = false);
    }
  }

  Future<void> _centerOn(LatLng target, {double zoom = 16}) async {
    if (!_mapController.isCompleted) return;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  // ---- Search ----
  void _startSearchSession() => TripServices.startSearchSession();
  void _endSearchSession() {
    TripServices.endSearchSession();
    _searchDebounce?.cancel();
    _predictions = [];
  }

  void _onSearchChanged(String value) {
    if (_isTripStarted || _tripCompleted) return;

    // clear destination/route while typing
    setState(() {
      _isEditing = true;
      _routePoints.clear();
      _polylines = <Polyline>{};
      _routePointsFull = [];
      _destination = null;
    });

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (value.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _predictions = []);
        return;
      }
      try {
        final preds = await TripServices.autocomplete(
          value,
          biasCenter: _currentLocation,
          countryCodes: _countries
              .map((country) => _countryCodes[country])
              .whereType<String>()
              .toList(growable: false),
        );
        if (!mounted) return;
        setState(() => _predictions = preds);
      } catch (_) {}
    });
  }

  void _clearSearchField() {
    _searchController.clear();
    setState(() {
      _predictions = [];
      // keep existing destination/route untouched
    });
    _onSearchChanged("");
    // Keep focus so the keyboard stays up (remove if you prefer to close it)
    // FocusScope.of(context).unfocus();
  }

  Future<void> _searchPlace(String query) async {
    if (_isTripStarted || _tripCompleted) return;
    if (query.isEmpty) return;

    setState(() => _isMapLoading = true);

    // 0) Coordinate search (decimal degrees)
    final coord = _tryParseLatLng(query);
    if (coord != null) {
      if (_isTripStarted || _tripCompleted) return; // keep your guardrails
      setState(() {
        _destination = coord;
        _isEditing = false;
        _isMapLoading = false;
        _predictions = [];
      });

      if (_currentLocation != null) {
        await _getRoute(_currentLocation!, _destination!);
      } else {
        await _centerOn(_destination!);
      }
      return; // ✅ done (skip Places)
    }

    try {
      final places = await TripServices.searchPlaces(
        query,
        countryFilters: {
          for (final country in _countries)
            if (_countryCodes[country] != null)
              _countryCodes[country]!: country,
        },
      );

      if (places.isNotEmpty) {
        final place = places.first;
        setState(() {
          _destination = place.location;
          _isEditing = false;
          _isMapLoading = false;
        });
        if (_currentLocation != null) {
          await _getRoute(_currentLocation!, _destination!);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No places found"),
              duration: Duration(seconds: 2),
            ),
          );
        }
        setState(() => _isMapLoading = false);
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Search failed: $e"),
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() => _isMapLoading = false);
    }
  }

  Future<void> _onPredictionTap(PlacePrediction p) async {
    if (_isTripStarted || _tripCompleted) return;

    final fullLabel = (p.secondaryText.isNotEmpty)
        ? '${p.mainText}, ${p.secondaryText}'
        : p.mainText;
    _searchController.value = TextEditingValue(
      text: fullLabel,
      selection: TextSelection.collapsed(offset: fullLabel.length),
    );
    _searchFocusNode.unfocus();

    setState(() {
      _predictions = [];
      _showSearchField = false;
      _isEditing = false;
      _isMapLoading = true;
    });

    try {
      final details = await TripServices.fetchPlaceDetails(p.placeId);
      setState(() {
        _destination = details.location;
        _isMapLoading = false;
      });

      if (_currentLocation != null) {
        await _getRoute(_currentLocation!, _destination!);
      } else {
        await _centerOn(_destination!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isMapLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t fetch place details: $e'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      _endSearchSession();
    }
  }

  // ---- Routes & Polylines ----
  Future<void> _getRoute(LatLng start, LatLng end) async {
    try {
      final routes = await TripServices.getDirections(start, end);
      if (routes.isEmpty) return;

      // fastest
      final primary = routes.reduce(
        (a, b) => a.durationSeconds <= b.durationSeconds ? a : b,
      );

      setState(() {
        _routePointsFull = primary.polylinePoints; // preview geometry
        _routePoints = List<LatLng>.from(_routePointsFull); // active list
        _routeDistance = primary.distanceMeters / 1000.0;
        _routeDuration = primary.durationSeconds / 60.0;
        _polylines = _buildPolylines();
      });
    } catch (e) {
      debugPrint("Route error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Route calculation failed: $e"),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Set<Polyline> _buildPolylines() {
    final set = <Polyline>{};
    final pointsToDraw = (_isTripStarted && !_isFreeRide)
        ? _routePoints
        : _routePointsFull;
    if (pointsToDraw.isNotEmpty) {
      set.add(
        Polyline(
          polylineId: PolylineId(
            (_isTripStarted && !_isFreeRide) ? 'active_route' : 'preview_route',
          ),
          points: pointsToDraw,
          width: 7,
          color: Colors.blue,
        ),
      );
    }
    return set;
  }

  // ---- External maps ----
  Future<void> _openInGoogleMaps() async {
    if (_currentLocation == null || _destination == null) return;
    final url =
        "https://www.google.com/maps/dir/?api=1"
        "&origin=${_currentLocation!.latitude},${_currentLocation!.longitude}"
        "&destination=${_destination!.latitude},${_destination!.longitude}"
        "&travelmode=driving";
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // add near other state fields
  int _acceptedSampleCounter = 0;
  double _smallMovementBufferMeters = 0.0;
  // Add to class fields if missing:

  // Pending UI batching (meters)
  double _pendingMeters = 0.0; // meters not yet flushed to UI
  DateTime? _lastUiFlushAt;
  static const int _uiFlushMs = 800; // throttle interval in ms
  static const double _uiBatchMeters = 5.0; // flush when >= 5m

  // minimum single-tick movement to accept (in meters)
  static const double _minAcceptMeters = 5.0;

  // degrees, 0 means unknown

  Future<void> _handlePosition(Position pos, {bool fromRestore = false}) async {
    try {
      if (!mounted) return;

      // Use device timestamp if present, otherwise now (in UTC)
      final now = pos.timestamp.toUtc();

      // Accuracy (meters) — reject non-finite or too-poor accuracy
      final acc = pos.accuracy;
      if (!acc.isFinite || acc > _gpsAccuracyCutoffM) {
        debugPrint('Rejecting fix: bad accuracy ($acc m).');
        return;
      }

      // Optional: reject mocked locations outright (or handle differently)
      if (pos.isMocked == true) {
        debugPrint('Rejecting mocked location.');
        return;
      }

      final newPos = LatLng(pos.latitude, pos.longitude);
      final prevPos = _lastPosition;

      // ISSUE 3 FIX: When the native foreground service is active, it is the
      // authoritative source of distance. Avoid noise/duplicate accumulation
      // in Flutter by not writing to _pendingMeters / TripManager when native is running.
      final nativeRunning = await TripServiceNative.isServiceRunning();
      if (nativeRunning) {
        _pendingMeters = 0.0;
        _lastPosition = newPos;
        _lastFixAt = now;

        if (_isTripStarted && _followMe && _lastPosition != null) {
          _lastSpeedMps = pos.speed.isFinite ? pos.speed : _lastSpeedMps;
          await _followCameraTo(
            _lastPosition!,
            prev: prevPos,
            speedMps: _lastSpeedMps,
          );
        }

        return;
      }

      double? dtSec = _lastFixAt != null
          ? now.difference(_lastFixAt!).inMilliseconds / 1000.0
          : null;

      double dMeters = 0.0;
      if (prevPos != null) {
        dMeters = Geolocator.distanceBetween(
          prevPos.latitude,
          prevPos.longitude,
          newPos.latitude,
          newPos.longitude,
        );

        // Spike/jump rejection (REJECT but DO NOT advance baseline)
        if (dtSec != null && dtSec > 0) {
          final measuredSpeed = dMeters / dtSec;
          final reportedSpeed = pos.speed.isFinite ? pos.speed : measuredSpeed;

          final maxAllowed =
              (_maxSpeedMps * dtSec) + (acc.isFinite ? acc : 0.0);
          final exceed = dMeters > math.max(_maxJumpMeters, maxAllowed);

          if (exceed) {
            debugPrint(
              'Rejecting large GPS jump: d=${dMeters.toStringAsFixed(1)} m, dt=${dtSec.toStringAsFixed(2)} s, reportedSpeed=${reportedSpeed.toStringAsFixed(2)} m/s',
            );

            // keep timestamp so next tick dt is correct, but do not advance baseline
            _lastFixAt = now;
            return;
          }
        }
      }

      // If no previous baseline, seed and forward sample (don't count distance yet)
      if (prevPos == null) {
        _lastPosition = newPos;
        _lastFixAt = now;
        // call directly (fire-and-forget) so in-memory TripManager state is updated synchronously
        TripManager.onLocation(
          LocationSample(
            ts: now,
            lat: pos.latitude,
            lng: pos.longitude,
            accuracyM: pos.accuracy,
            speedMps: pos.speed.isFinite ? pos.speed : -1,
            isMocked: pos.isMocked,
          ),
        ).catchError(
          (e, st) => debugPrint('TripManager.onLocation error (seed): $e\n$st'),
        );
        return; // seed tick — no distance yet
      }

      // Reject tiny noise (< _minAcceptMeters) but accumulate it into a small buffer
      if (dMeters <= 0.0) return;

      if (dMeters < _minAcceptMeters) {
        _smallMovementBufferMeters += dMeters;

        // Speed-based override: if the device reports movement above
        // `_minAcceptSpeedMps`, accept smaller steps sooner to avoid
        // suppressing legitimate slow movement (walking / slow riding).
        final shouldForceAcceptBySpeed =
            pos.speed.isFinite &&
            pos.speed >= _minAcceptSpeedMps &&
            dMeters > 0.0;

        // Promote when buffer reaches minAccept threshold or when speed override triggers
        if (_smallMovementBufferMeters >= _minAcceptMeters ||
            shouldForceAcceptBySpeed) {
          // Keep a record of the buffered sum (for diagnostics); do not clear it
          // until we confirm TripManager would accept a non-zero canonical delta.
          final double bufferedPromoted = _smallMovementBufferMeters;

          // Compute the canonical straight-line delta between TripManager.lastPoint
          // and this sample — use QualityFilters.safeDistance so that tiny
          // jitter (e.g., <1.5m) is treated as 0. This prevents promoting a
          // small non-zero number that TripManager would filter to 0.
          final double canonicalPromoted = TripManager.lastPoint != null
              ? QualityFilters.safeDistance(TripManager.lastPoint!, newPos)
              : 0.0;

          if (canonicalPromoted <= 0.0) {
            // Defer promotion — keep buffer for future ticks and log for diagnostics
            _hudLog(
              'PROMOTE DEFERRED ${bufferedPromoted.toStringAsFixed(2)}m (canonical filtered)',
            );
            debugPrint(
              'PROMOTE DEFERRED: buffered=${bufferedPromoted.toStringAsFixed(2)}m canonical=${canonicalPromoted.toStringAsFixed(2)}m (filtered by QualityFilters)',
            );

            // Leave _smallMovementBufferMeters as-is and wait for a later sample
            return;
          }

          // canonicalPromoted > 0 => TripManager would accept this delta, so promote
          final double promoted = canonicalPromoted;
          _smallMovementBufferMeters = 0.0;

          // Accept promotion and advance baseline
          _pendingMeters += promoted;
          _lastPosition = newPos;
          _lastFixAt = now;

          _hudLog('PROMOTED ${promoted.toStringAsFixed(2)}m (canonical)');
          debugPrint(
            'PROMOTED ACCEPT Δ: buffered=${bufferedPromoted.toStringAsFixed(2)}m canonical=${canonicalPromoted.toStringAsFixed(2)}m promoted=${promoted.toStringAsFixed(2)}m pending=${_pendingMeters.toStringAsFixed(1)}m lastPos=${_lastPosition?.latitude},${_lastPosition?.longitude} acc=${pos.accuracy} speed=${pos.speed} (speedOverride=$shouldForceAcceptBySpeed)',
          );

          // Mark sample & log caller context
          _acceptedSampleCounter += 1;
          debugPrint(
            'CALL onLocation #$_acceptedSampleCounter PROMOTED ts=${now.toIso8601String()} TripManager.lastPoint=${TripManager.lastPoint?.latitude},${TripManager.lastPoint?.longitude}',
          );

          // Fire-and-forget: call TripManager.onLocation synchronously enough
          // that in-memory metrics are updated immediately (onLocation mutates
          // _active.distanceM synchronously before async persistence).
          TripManager.onLocation(
            LocationSample(
              ts: now,
              lat: pos.latitude,
              lng: pos.longitude,
              accuracyM: pos.accuracy,
              speedMps: pos.speed.isFinite ? pos.speed : -1,
              isMocked: pos.isMocked,
            ),
          ).catchError(
            (e, st) =>
                debugPrint('TripManager.onLocation error (promote): $e\n$st'),
          );
        } else {
          // still below noise threshold — ignore this tick for distance/UI
          return;
        }
      } else {
        // Normal accept — add to pending buffer and advance baseline
        _pendingMeters += dMeters;
        _lastPosition = newPos;
        _lastFixAt = now;
        if (_isTripStarted && _followMe && _lastPosition != null) {
          _lastSpeedMps = pos.speed.isFinite ? pos.speed : _lastSpeedMps;

          await _followCameraTo(
            _lastPosition!,
            prev: prevPos,
            speedMps: _lastSpeedMps,
          );
        }

        _hudLog('ACCEPTED ${dMeters.toStringAsFixed(1)}m');
        debugPrint(
          'ACCEPT RAW Δ: raw=${dMeters.toStringAsFixed(1)}m pending=${_pendingMeters.toStringAsFixed(1)}m measuredSpeed=${pos.speed} acc=${pos.accuracy}',
        );

        // Mark sample & log caller context
        _acceptedSampleCounter += 1;
        debugPrint(
          'CALL onLocation #$_acceptedSampleCounter RAW ts=${now.toIso8601String()} TripManager.lastPoint=${TripManager.lastPoint?.latitude},${TripManager.lastPoint?.longitude}',
        );

        // Fire-and-forget — call directly so in-memory distance updates happen synchronously
        TripManager.onLocation(
          LocationSample(
            ts: now,
            lat: pos.latitude,
            lng: pos.longitude,
            accuracyM: pos.accuracy,
            speedMps: pos.speed.isFinite ? pos.speed : -1,
            isMocked: pos.isMocked,
          ),
        ).catchError(
          (e, st) => debugPrint('TripManager.onLocation error: $e\n$st'),
        );
      }

      // Flush pending meters to UI in batches / throttled
      _flushPendingDistanceIfDue();
    } catch (e, st) {
      debugPrint('❌ _handlePosition (buffered) crash: $e\n$st');
    }
  }

  /// ISSUE 5 FIX: Request foreground and background location permissions
  Future<bool> _ensureStartTripPermissions() async {
    if (!Platform.isAndroid) {
      // iOS: Use Geolocator permission flow
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied ||
            req == LocationPermission.deniedForever) {
          await _showPermissionDialog(
            "Location Permission Required",
            "We cannot start a trip without live GPS location.\n"
                "Please enable location permission in Settings.",
          );
          return false;
        }
      }
      return true;
    }

    // ================= ANDROID =================

    // STEP 1: Foreground location permission (ACCESS_FINE_LOCATION)
    final fgStatus = await Permission.locationWhenInUse.status;
    if (!fgStatus.isGranted) {
      final fgResult = await Permission.locationWhenInUse.request();
      if (!fgResult.isGranted) {
        await _showPermissionDialog(
          "Location Permission Required",
          "We cannot start a trip without live GPS location.\n"
              "Please allow location access to continue.",
        );
        return false;
      }
    }

    // STEP 2: Notification permission (Android 13+)
    final notifStatus = await Permission.notification.status;
    if (notifStatus.isDenied) {
      await Permission.notification.request();
    }

    debugPrint('✅ [Permissions] Foreground location & notifications granted');
    return true;
  }

  Future<void> _showPermissionDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_off,
                  size: 58,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    AppSettings.openAppSettings();
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  child: const Text(
                    "Open Settings",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _ensureBatteryWhitelist() async {
    // Step 1: Standard Android battery optimization (all devices)
    final isIgnoring =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (isIgnoring != true) {
      final allowed = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          title: const Text(
            'Battery Optimization Required',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'To ensure accurate trip tracking, please disable battery '
            'optimization for this app.\n\n'
            'Tap "Open Settings" and select "Don\'t optimize".',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text(
                'Open Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      if (allowed != true) return false;
      await Future.delayed(const Duration(seconds: 1));

      // Re-check after returning from settings
      final nowIgnoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (nowIgnoring != true) return false;
    }

    // Step 2: Oppo/Realme/OnePlus — their own second battery kill layer
    // Standard Android setting does NOT cover this. Without this step,
    // Oppo will still kill the foreground service after ~2 minutes.
    // if (await _isOppoDevice()) {
    //   await _showOppoSettingsDialog();
    // }

    return true;
  }

  // Future<bool> _isOppoDevice() async {
  //   final manufacturer = (await _getManufacturer()).toLowerCase();
  //   return manufacturer.contains('oppo') ||
  //       manufacturer.contains('realme') ||
  //       manufacturer.contains('oneplus') ||
  //       manufacturer.contains('vivo') ||
  //       manufacturer.contains('iqoo');
  // }

  // Future<String> _getManufacturer() async {
  //   try {
  //     // android.os.Build.MANUFACTURER via platform channel or device_info_plus
  //     final info = await DeviceInfoPlugin().androidInfo;
  //     return info.manufacturer;
  //   } catch (_) {
  //     return '';
  //   }
  // }

  // Future<void> _showOppoSettingsDialog() async {
  //   if (!mounted) return;
  //   await showDialog<void>(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (_) => AlertDialog(
  //       title: const Text(
  //         'One More Step (Oppo/Realme)',
  //         style: TextStyle(fontWeight: FontWeight.bold),
  //       ),
  //       content: const Text(
  //         'Your device has additional battery restrictions that will stop '
  //         'trip tracking when you leave the app.\n\n'
  //         'Please go to:\n'
  //         'Settings → Battery → App Quick Freeze / Background Freeze\n'
  //         '→ Find this app → Disable\n\n'
  //         'Also check:\n'
  //         'Settings → Battery → Power Saving → Exceptions → Add this app.',
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () async {
  //             // Try to open Oppo-specific battery settings directly
  //             // Falls back to general settings if not available
  //             try {
  //               const platform = MethodChannel(
  //                 'com.FieldServiceBioRemedies.FieldService_app/settings',
  //               );
  //               await platform.invokeMethod('openOppoBatterySettings');
  //             } catch (_) {
  //               // Fallback: open general app settings where user can find battery
  //               await openAppSettings();
  //             }
  //             if (context.mounted) Navigator.pop(context);
  //           },
  //           child: const Text('Open Settings'),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('Skip'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Future<void> openOEMAutoStartSettings() async {
    // The plugin does not support OEM-specific settings.
    // We only show a message to the user.
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 4),
        content: Text(
          "Please enable Auto-Start / Background Run in your phone settings "
          "(Battery / App Management).",
        ),
      ),
    );
  }

  Future<void> _startTripWithoutDestination() async {
    if (_isStartingTrip || _isTripStarted) return;

    // HARD GATE – block free-ride start when location permission is missing
    final permOK = await _ensureStartTripPermissions();
    if (!permOK) return;

    final batteryOK = await _ensureBatteryWhitelist();
    if (!batteryOK) return;

    // Close search UI & reset preview
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    final isOnDuty = await AttendanceService.isOnDutyCachedForToday();

    if (!isOnDuty) {
      showGlobalToast("You must be ON DUTY to start a trip", error: true);
      return;
    }

    setState(() {
      _isFreeRide = true;
      _destination = null;

      _polylines = <Polyline>{};
      _routePoints.clear();
      _routeDistance = null;
      _routeDuration = null;
      _distanceRemainingKm = null;
      _durationRemainingMin = null;
      _lastEtaRefreshAt = null;

      _searchController.clear();
      _predictions = [];
      _showSearchField = false;
      _isEditing = false;
    });

    // Delegate to the unified guarded starter (handles queuing when offline)
    await _startTrip(skipGuards: true);
  }

  Future<void> _startTrip({bool skipGuards = false}) async {
    if (_isStartingTrip || _isTripStarted || _isEndingTrip) return;

    // HARD GATE for START TRIP — Block progress until permission granted
    if (!skipGuards) {
      final permOK = await _ensureStartTripPermissions();
      if (!permOK) return;

      final batteryOK = await _ensureBatteryWhitelist();
      if (!batteryOK) return;
    }

    final prefs = await SharedPreferences.getInstance();
    final isOnDuty = await AttendanceService.isOnDutyCachedForToday();

    if (!isOnDuty) {
      showGlobalToast("Go ON DUTY first", error: true);
      return;
    }

    _isStartingTrip = true;
    await _setStartState(StartTripSyncState.localStarted);
    //await prefs.setBool('_startBackendCompleted', false);
    //_startBackendCompleted = false;

    // Watchdog: if start makes no progress for a while, show a non-fatal warning.
    // NOTE: do NOT flip start flags here — let the real flow decide. Timeout bumped for slow devices.
    Timer? startWatch = Timer(const Duration(seconds: 45), () {
      if (!mounted) return;

      // If start already succeeded, nothing to do.
      if (_isTripStarted || !_isStartingTrip) return;

      _hudLog('Start trip watchdog fired — no progress detected');

      try {
        _setLoading(null);
      } catch (_) {}

      // Don't mutate _isStartingTrip here to avoid races; only notify user.
      showGlobalToast(
        'Trip start is taking longer than expected. Please wait or try again.',
        error: true,
      );

      _hudLog('Start trip watchdog warning shown');
    });

    await prefs.remove("currentTripStartTime");
    await prefs.remove("currentTripDate");
    await prefs.remove("currentTripStartLat");
    await prefs.remove("currentTripStartLng");
    await prefs.remove("currentTripStartKm");

    try {
      final bool isNavigated = (_destination != null);
      _isFreeRide = !isNavigated;

      // SHOW LOADER
      _setLoading(isNavigated ? 'Starting trip…' : 'Starting trip…');

      bool success = false;
      DateTime? startStamp;
      LatLng? originForRoute = _currentLocation;

      DirectionsRoute? preparedRoute;
      double? prepDistanceRemainingKm;
      double? prepDurationRemainingMin;

      try {
        // Start local trip and persist localTripId so queued requests can reference it.
        session = await _time(
          'trip:start:TripManager.start',
          () => TripManager.start(
            origin: _currentLocation,
            destination: _destination,
          ),
        );

        // Start foreground service so OS is less likely to kill us during the trip.
        // NOTE: Native `TripForegroundService` is authoritative and will be started via
        // MethodChannel; avoid starting a plugin-managed foreground service to prevent
        // duplicate notifications.
        // (Removed redundant `TripForegroundService.start(session!.id)` call.)

        // persist localTripId immediately so end can reference it even if start is queued
        try {
          await prefs.setString("currentTripLocalId", session!.id);

          // --- NEW: persist UI-friendly start metadata immediately so duplicate
          // starts are blocked across process restarts and before network attempts. ---
          final nowIST = DateTime.now().toUtc().add(
            const Duration(hours: 5, minutes: 30),
          );
          final todayDate =
              "${nowIST.year}-${nowIST.month.toString().padLeft(2, '0')}-${nowIST.day.toString().padLeft(2, '0')}";
          await prefs.setString(
            "currentTripStartTime",
            nowIST.toIso8601String(),
          );
          await prefs.setString("currentTripDate", todayDate);
          // best-effort start lat/lng from last-known location (may be null)
          if (_currentLocation != null) {
            await prefs.setString(
              "currentTripStartLat",
              _currentLocation!.latitude.toString(),
            );
            await prefs.setString(
              "currentTripStartLng",
              _currentLocation!.longitude.toString(),
            );
          } else {
            await prefs.setString("currentTripStartLat", '');
            await prefs.setString("currentTripStartLng", '');
          }
          await prefs.setString("currentTripStartKm", '0');
        } catch (e) {
          debugPrint(
            "⚠️ Could not persist currentTripLocalId/start-metadata: $e",
          );
        }

        startStamp = DateTime.now();
        // Fire-and-forget: this will queue if offline/retriable
        Future.microtask(
          () => _time(
            'trip:start:_sendTripStartApi',
            () => _sendTripStartApi(startKmReading: 0, skipLocalGuard: true),
          ),
        );

        // Route prep (best effort; may fail if offline)
        // Route prep (best-effort). Launch async so a slow routing API does not delay UI start.
        // When route arrives we update UI if the trip is still active.
        if (!_isFreeRide && originForRoute != null) {
          TripServices.getTwoWheelerRoute(originForRoute, _destination!)
              .then((r) {
                try {
                  final route = r;
                  final distKm = route.distanceMeters / 1000.0;
                  final durMin = route.durationSeconds / 60.0;

                  // Apply results only if trip still active
                  if (mounted && _isTripStarted) {
                    setState(() {
                      _routePoints = route.polylinePoints;
                      _routeDistance = distKm;
                      _routeDuration = durMin;

                      _distanceRemainingKm = distKm;
                      _durationRemainingMin = durMin;
                      _lastValidDistanceKm = distKm;
                      _lastValidDurationMin = durMin;
                      _lastEtaRefreshAt = DateTime.now();
                      _polylines = _buildPolylines();
                    });
                  } else {
                    // store prepared values for potential later use
                    preparedRoute = route;
                    prepDistanceRemainingKm = distKm;
                    prepDurationRemainingMin = durMin;
                  }
                } catch (e) {
                  debugPrint('🗺️ Route prep then-handler error: $e');
                }
              })
              .catchError((e) {
                debugPrint('🗺️ Route prep failed (async): $e');
              });
        }

        success = true;
        //await _startHiveTripWatcher();
      } catch (e) {
        debugPrint('StartTrip failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not start trip: $e'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } finally {
        //_setLoading(null);
        try {
          await WidgetsBinding.instance.endOfFrame;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
      }

      if (!mounted || !success) return;

      // Future.delayed(Duration(seconds: 2), () {
      //   _showOEMHintSnackbar();
      // });

      // Get a fresh fix (best-effort) — bounded so start isn't delayed by a cold GPS fix.
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 20));
        // Use unified handler to accept/ignore and initialize filters
        await _handlePosition(fresh);
      } catch (e) {
        debugPrint(
          'Could not obtain fresh GPS fix after start (timed out or failed): $e',
        );
      }

      // compute authoritative start time (prefer TripManager's session if available)
      final DateTime authoritativeStartLocal = (session != null)
          ? session!.startUtc.toLocal()
          : (startStamp ?? DateTime.now());

      // compute elapsed up to "now" (to include loader latency)
      final Duration initialElapsed = DateTime.now().difference(
        authoritativeStartLocal,
      );

      // Cancel watchdog now that start succeeded
      try {
        startWatch.cancel();
        startWatch = null;
      } catch (_) {}

      setState(() {
        _isTripStarted = true;
        _tripCompleted = false;
        _tripStartTime = startStamp ?? DateTime.now();
        _distanceTraveled = 0.0;
        _elapsedTime = initialElapsed;
        // remove assignment — start with null baseline so first accepted sample seeds it
        //_lastPosition = null;

        if (!_isFreeRide && preparedRoute != null) {
          _routePoints = preparedRoute!.polylinePoints;
          _routeDistance = preparedRoute!.distanceMeters / 1000.0;
          _routeDuration = preparedRoute!.durationSeconds / 60.0;
          _polylines = _buildPolylines();

          _distanceRemainingKm = prepDistanceRemainingKm;
          _durationRemainingMin = prepDurationRemainingMin;
          // Store as last valid ETA for fallback purposes
          _lastValidDistanceKm = prepDistanceRemainingKm;
          _lastValidDurationMin = prepDurationRemainingMin;
          _lastEtaRefreshAt = DateTime.now();
        }
      });

      // Persist tripCompleted state
      await _persistTripCompleted(false);

      // Tick elapsed time locally
      _tripTimer?.cancel();
      _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _tripStartTime == null) return;
        setState(() {
          _elapsedTime = DateTime.now().difference(_tripStartTime!);
        });
      });

      // Auto-refresh ETA every 1 minute
      _etaRefreshTimer?.cancel();
      _etaRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
        if (!mounted || !_isTripStarted || _destination == null) {
          debugPrint(
            'ETA Timer: Skipped (mounted=$mounted, started=$_isTripStarted, dest=$_destination)',
          );
          return;
        }
        debugPrint('ETA Timer: Firing refresh...');
        await _refreshETAWithFallback('periodic');
      });

      // Initial ETA refresh right after trip starts
      if (!_isFreeRide && _destination != null) {
        debugPrint('Initial ETA refresh after trip start');
        _refreshETAWithFallback('initial');
      }

      // Location stream
      _positionStream?.cancel();
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0, // <-- ALWAYS FIRE
              timeLimit: null,
            ),
          ).listen((pos) async {
            await _handlePosition(pos);
          });

      _setLoading(null);
    } finally {
      // Cancel watchdog if still present (defensive)
      try {
        startWatch?.cancel();
        startWatch = null;
      } catch (_) {}

      _isStartingTrip = false; // ✅ always release guard
    }
  }

  Future<bool> _sendTripStartApi({
    required int startKmReading,
    bool skipLocalGuard =
        false, // NEW: allow caller to bypass the simple prefs-guard
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? '';
      final companyId = prefs.getString('companyId') ?? '';

      if (userId.isEmpty) {
        debugPrint("❌ No userId found. Cannot start trip.");
        return false;
      }
      if (companyId.isEmpty) {
        debugPrint("❌ No companyId found. Cannot mark ON DUTY.");
        return false;
      }

      // Prevent accidental double-start when not explicitly bypassed.
      // When called from _startTrip() we now pass skipLocalGuard: true,
      // because _startTrip has already persisted the start markers and intends to send.
      if (!skipLocalGuard &&
          (prefs.getString("currentTripStartTime") != null)) {
        final existingLocal =
            prefs.getString("currentTripLocalId") ?? '<unknown>';
        debugPrint(
          "⚠️ Trip already started locally (localTripId=$existingLocal) — ignoring duplicate start.",
        );
        return false;
      }

      // Capture a GPS fix (works offline)
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentLocation = LatLng(position.latitude, position.longitude);

      // Reverse geocode best-effort
      // Reverse geocode hybrid (Google → fallback to placemark → offline string)
      String area = "Unknown area";

      try {
        // --- 1) GOOGLE GEOCODING API ---
        final key = AppConfig.googleMapsApiKey;
        final url =
            "https://maps.googleapis.com/maps/api/geocode/json"
            "?latlng=${position.latitude},${position.longitude}"
            "&key=$key";

        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);

          if (json["status"] == "OK" && json["results"].isNotEmpty) {
            area = json["results"][0]["formatted_address"];
          } else {
            throw Exception("Google returned no results");
          }
        } else {
          throw Exception("Google code ${resp.statusCode}");
        }
      } catch (googleErr) {
        debugPrint("⚠️ Google geocoding failed: $googleErr");

        // --- 2) FALLBACK: placemarkFromCoordinates ---
        try {
          final placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );

          if (placemarks.isNotEmpty) {
            final p = placemarks.first;

            area = [
              p.name,
              p.street,
              p.thoroughfare,
              p.subLocality,
              p.locality,
              p.subAdministrativeArea,
              p.administrativeArea,
              p.postalCode,
              p.country,
            ].where((s) => s != null && s.trim().isNotEmpty).join(", ");
          } else {
            throw Exception("Placemark empty");
          }
        } catch (localErr) {
          debugPrint("⚠️ Local reverse-geocode failed: $localErr");

          // --- 3) LAST RESORT (Offline) ---
          area = "(Offline — address unavailable)";
        }
      }

      // IST timestamp + tripDate
      final nowIST = DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 30),
      );
      final todayDate =
          "${nowIST.year}-${nowIST.month.toString().padLeft(2, '0')}-${nowIST.day.toString().padLeft(2, '0')}";

      // Use existing localTripId or create new stable local id
      final localTripId =
          prefs.getString("currentTripLocalId") ??
          '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 32).toRadixString(16)}';
      await prefs.setString("currentTripLocalId", localTripId);

      final body = {
        "employeeId": userId,
        "companyId": companyId,
        "tripDate": todayDate,
        "startTime": nowIST.toIso8601String(),
        "endTime": "",
        "startLocation": {
          "longitude": position.longitude.toString(),
          "latitude": position.latitude.toString(),
        },
        "endLocation": {"longitude": "", "latitude": ""},
        "startLocationName": area,
        "startKmReading": startKmReading,
        "endKmReading": "",
        // crucial: carry stable local id so SyncService can reconcile later
        "localTripId": localTripId,
      };

      debugPrint("📤 [TripStart] POST /api/trips body: $body");

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.trips,
        jsonBody: body,
        headers: {'X-Idempotency-Key': localTripId},
        optimisticOk: true,
      );

      // Persist UI-friendly start metadata
      await prefs.setString("currentTripStartTime", nowIST.toIso8601String());
      await prefs.setString("currentTripDate", todayDate);
      await prefs.setString(
        "currentTripStartLat",
        position.latitude.toString(),
      );
      await prefs.setString(
        "currentTripStartLng",
        position.longitude.toString(),
      );
      await prefs.setString("currentTripStartKm", startKmReading.toString());
      // keep currentTripLocalId stored (already set above)

      if (resp == null) {
        // queued by apiClient/SyncService — UI is optimistic
        debugPrint(
          "🟡 [TripStart] queued by apiClient (localTripId=$localTripId)",
        );

        //await prefs.setBool('_startBackendCompleted', true);
        await _setStartState(StartTripSyncState.backendConfirmed);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip start queued — will sync automatically'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        UnifiedLocationManager().onTripStarted();
        return true;
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint("✅ [TripStart] server OK: ${resp.body}");
        try {
          final decoded = jsonDecode(resp.body);
          final serverTripId = decoded['data']?['_id'];
          if (serverTripId != null &&
              serverTripId is String &&
              serverTripId.isNotEmpty) {
            // persist server id and mapping
            await prefs.setString("currentTripId", serverTripId);
            final mapRaw = prefs.getString('tripMapping_v1') ?? '{}';
            final Map<String, dynamic> mapping = jsonDecode(mapRaw);
            mapping[localTripId] = serverTripId;
            await prefs.setString('tripMapping_v1', jsonEncode(mapping));
            debugPrint('🔁 mapping saved: $localTripId -> $serverTripId');
            await _setStartState(StartTripSyncState.backendConfirmed);
          }
        } catch (e) {
          debugPrint('⚠️ Could not parse TripStart response: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip started successfully'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
        UnifiedLocationManager().onTripStarted();
        return true;
      } else {
        debugPrint(
          "⚠️ [TripStart] server error: ${resp.statusCode} - ${resp.body}",
        );
        await _persistTripFailedRecord(
          method: 'POST',
          path: AppConfig.trips,
          jsonBody: body,
          statusCode: resp.statusCode,
          reason: resp.statusCode >= 500
              ? FailureReason.maxAttemptsReached
              : FailureReason.permanentClientError,
          errorDetail:
              'HTTP ${resp.statusCode}: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}',
        );
        await _setStartState(StartTripSyncState.backendPending);
        return false;
        // Leave local markers for SyncService to retry
      }

      // IMPORTANT: do NOT clear currentTripId here. Keeping local ids allows reconciliation.
    } catch (e) {
      debugPrint("❌ [TripStart] exception: $e");
      await _persistTripFailedRecord(
        method: 'POST',
        path: AppConfig.trips,
        jsonBody: null,
        statusCode: 0,
        reason: FailureReason.maxAttemptsReached,
        errorDetail: e.toString(),
      );
      await _setStartState(StartTripSyncState.backendPending);
      return false;
    }
  }

  /// Refresh ETA with fallback to last valid values on error
  Future<void> _refreshETAWithFallback(String reason) async {
    if (_etaRefreshing ||
        !_isTripStarted ||
        _destination == null ||
        _lastPosition == null) {
      debugPrint(
        'ETA refresh skipped ($reason): etaRefreshing=$_etaRefreshing, started=$_isTripStarted, dest=$_destination, lastPos=$_lastPosition',
      );
      return;
    }
    debugPrint('ETA refresh starting ($reason)...');

    _etaRefreshing = true;
    try {
      final origin = _lastPosition!;
      debugPrint(
        'ETA: Calling getTwoWheelerRoute from (${origin.latitude}, ${origin.longitude}) to (${_destination!.latitude}, ${_destination!.longitude})',
      );
      final r = await TripServices.getTwoWheelerRoute(origin, _destination!);
      debugPrint(
        'ETA: API returned route with duration ${r.durationSeconds}s, distance ${r.distanceMeters}m',
      );
      final newDurationMin = r.durationSeconds / 60.0;

      // "Stickiness" check: don't update if new ETA is too close to old one
      if (reason == 'periodic' &&
          _durationRemainingMin != null &&
          newDurationMin >=
              _durationRemainingMin! * (1.0 - _kStickinessFraction)) {
        debugPrint(
          'ETA: Skipped update (stickiness check): new=${newDurationMin.toStringAsFixed(1)}min, current=${_durationRemainingMin!.toStringAsFixed(1)}min',
        );
        return;
      }

      // Clamp to zero to avoid negative times
      final distance = (r.distanceMeters / 1000.0).clamp(0.0, double.infinity);
      final duration = newDurationMin.clamp(0.0, double.infinity);

      // Update successful — store as last valid
      setState(() {
        _routePoints = r.polylinePoints;
        _routeDistance = r.distanceMeters / 1000.0;
        _routeDuration = r.durationSeconds / 60.0;
        _polylines = _buildPolylines();

        _distanceRemainingKm = distance;
        _durationRemainingMin = duration;
        _lastValidDistanceKm = distance;
        _lastValidDurationMin = duration;
        _lastEtaRefreshAt = DateTime.now();

        debugPrint(
          '[STATE SET] _distanceRemainingKm = $distance, _durationRemainingMin = $duration',
        );
      });

      debugPrint(
        'ETA refreshed ($reason): ${duration.toStringAsFixed(1)} min, ${distance.toStringAsFixed(1)} km',
      );
      debugPrint(
        'STATE: _useFreeRideProgressCard=$_useFreeRideProgressCard, _destination=$_destination, _isTripStarted=$_isTripStarted',
      );
    } catch (e, st) {
      // Error occurred — use last valid ETA as fallback
      debugPrint('ETA refresh failed ($reason): Exception=$e');
      debugPrint('ETA Stack Trace: $st');
      if (_lastValidDurationMin != null && _lastValidDistanceKm != null) {
        setState(() {
          _durationRemainingMin = _lastValidDurationMin;
          _distanceRemainingKm = _lastValidDistanceKm;
          _lastEtaRefreshAt =
              DateTime.now(); // Update timestamp even with fallback
        });
        debugPrint(
          'ETA: Using last valid fallback: ${_lastValidDurationMin!.toStringAsFixed(1)} min, ${_lastValidDistanceKm!.toStringAsFixed(1)} km',
        );
      } else {
        debugPrint('ETA: No last valid fallback available');
      }
    } finally {
      _etaRefreshing = false;
    }
  }

  double _bearing(LatLng from, LatLng to) {
    final d2r = math.pi / 180.0, r2d = 180.0 / math.pi;
    final lat1 = from.latitude * d2r, lat2 = to.latitude * d2r;
    final dLon = (to.longitude - from.longitude) * d2r;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * r2d + 360.0) % 360.0;
  }

  Future<void> _followCameraTo(
    LatLng pos, {
    LatLng? prev,
    double? speedMps,
  }) async {
    if (!_mapController.isCompleted) return;
    if (!_followMe) return;

    final now = DateTime.now();
    if (now.difference(_lastCamAnim).inMilliseconds < _followMinMs) return;

    // distance guard
    if (prev != null) {
      final moved = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (moved < _followMinMeters) return;
    }

    // bearing
    double targetBearing = _smoothedBearing;
    if (prev != null) {
      targetBearing = _bearing(prev, pos);
    }

    // smooth bearing
    _smoothedBearing = _smoothBearing(
      _smoothedBearing,
      targetBearing,
      _bearingAlpha,
    );

    // tilt based on speed
    final tilt = _tiltForSpeed(speedMps ?? _lastSpeedMps);

    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos,
          zoom: _followZoom,
          bearing: _smoothedBearing,
          tilt: tilt,
        ),
      ),
    );

    _lastCamAnim = now;
  }

  Future<bool> _ensureEndTripPermissions() async {
    final perm = await Geolocator.checkPermission();

    final isDenied =
        perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever;

    if (!isDenied) return true; // already OK

    // SHOW BLOCKING DIALOG — Option B
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_off,
                  size: 58,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Location Permission Required",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  "We need location permission to capture the final trip end location.\n"
                  "Please enable it to end this trip.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          AppSettings.openAppSettings();
                          Navigator.of(context).pop(false);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          "Open Settings",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _endTrip() async {
    if (_isEndingTrip || !_isTripStarted) return;

    final prefs = await SharedPreferences.getInstance();

    final state = await _getStartState();
    if (state == StartTripSyncState.localStarted ||
        state == StartTripSyncState.backendPending) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ending trip locally — will sync when possible'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    // Permission gate
    final ok = await _ensureEndTripPermissions();
    if (!ok) return;

    _isEndingTrip = true;
    _setLoading('Ending trip…');

    DateTime endStamp = DateTime.now();
    Duration computedDuration = Duration.zero;
    double finalDistanceKm = 0.0;

    try {
      // Stop streams first
      _positionStream?.cancel();
      _positionStream = null;
      _tripTimer?.cancel();
      _tripTimer = null;
      _etaRefreshTimer?.cancel();
      _etaRefreshTimer = null;

      // Flush pending meters
      await _flushPendingDistanceIfDue(force: true);

      // Compute duration
      computedDuration = (_tripStartTime != null)
          ? endStamp.difference(_tripStartTime!)
          : Duration.zero;

      // ✅ Get authoritative distance BEFORE stopping native service
      try {
        final snapshot = await TripServiceNative.getActiveTripSnapshot();
        if (snapshot != null && snapshot['distanceMeters'] != null) {
          finalDistanceKm =
              (snapshot['distanceMeters'] as num).toDouble() / 1000.0;
          debugPrint(
            'TripEnd: using native distance = ${finalDistanceKm.toStringAsFixed(3)} km',
          );
        } else if (TripManager.active != null) {
          finalDistanceKm = TripManager.active!.distanceM / 1000.0;
          debugPrint(
            'TripEnd: using TripManager distance = ${finalDistanceKm.toStringAsFixed(3)} km',
          );
        } else {
          finalDistanceKm = _distanceTraveled;
          debugPrint(
            'TripEnd: using UI distance = ${finalDistanceKm.toStringAsFixed(3)} km',
          );
        }
      } catch (e) {
        finalDistanceKm = _distanceTraveled;
        debugPrint('TripEnd: snapshot failed, fallback UI distance: $e');
      }

      // Persist locally
      await prefs.setDouble("totalKm", finalDistanceKm);

      // Fire API (queue if offline)
      Future.microtask(() {
        _sendTripEndApi(endKmReading: finalDistanceKm);
      });

      // Stop native + TripManager (NO microtask race)
      try {
        await TripServiceNative.stopTrip();
        await TripManager.end();
      } catch (e) {
        debugPrint('TripEnd stop services error: $e');
        try {
          await TripManager.end();
        } catch (_) {}
      }

      await _setStartState(StartTripSyncState.idle);

      // Update UI
      if (!mounted) return;
      setState(() {
        _isTripStarted = false;
        _tripCompleted = true;
        _tripDuration = computedDuration;
        _kmCovered = finalDistanceKm;
      });

      // Persist tripCompleted state
      await _persistTripCompleted(true);

      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(
      //       content: Text('Trip ended successfully'),
      //       duration: Duration(seconds: 2),
      //       backgroundColor: Colors.green,
      //     ),
      //   );
      // }
    } catch (e, st) {
      debugPrint('❌ EndTrip fatal error: $e\n$st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trip ended locally (sync pending): $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // UI must still unwind
      if (mounted) {
        setState(() {
          _isTripStarted = false;
          _tripCompleted = true;
          _tripDuration = computedDuration;
          _kmCovered = finalDistanceKm;
        });
      }

      // Persist tripCompleted state even on error
      await _persistTripCompleted(true);
    } finally {
      _setLoading(null);
      _isEndingTrip = false; // ✅ always release guard
    }
  }

  Future<bool> _sendTripEndApi({required double endKmReading}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final userId = prefs.getString('userId') ?? '';
      final localTripId = prefs.getString('currentTripLocalId') ?? '';

      final tripDate = prefs.getString('currentTripDate');
      final startTimePref = prefs.getString('currentTripStartTime');
      final startLatPref = prefs.getString('currentTripStartLat');
      final startLngPref = prefs.getString('currentTripStartLng');
      final startKmPref = prefs.getString('currentTripStartKm');
      final totalKmPref = prefs.getDouble('totalKm');

      if (userId.isEmpty) {
        debugPrint("❌ No userId found. Cannot end trip.");
        return false;
      }

      if (localTripId.isEmpty) {
        debugPrint("❌ No localTripId found. Cannot end trip.");
        return false;
      }

      // ✅ Fallback to TripManager session if prefs missing
      final session = TripManager.active;

      final startTime = startTimePref ?? session?.startUtc.toIso8601String();
      final startLat = startLatPref ?? session!.origin?.latitude.toString();
      final startLng = startLngPref ?? session!.origin?.longitude.toString();
      final startKm = startKmPref ?? "0";

      if (startTime == null || startLat == null || startLng == null) {
        debugPrint("❌ Missing start trip data (prefs + session).");
        return false;
      }

      final totalKm = totalKmPref ?? endKmReading;

      // Capture current location (best effort)
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _currentLocation = LatLng(position.latitude, position.longitude);
      } catch (e) {
        debugPrint('⚠️ Final GPS fix failed (non-fatal): $e');
        position = null;
      }

      // Reverse geocode best-effort
      String area = "(Offline — address unavailable)";
      if (position != null) {
        try {
          final key = AppConfig.googleMapsApiKey;
          final url =
              "https://maps.googleapis.com/maps/api/geocode/json"
              "?latlng=${position.latitude},${position.longitude}"
              "&key=$key";

          final resp = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));

          if (resp.statusCode == 200) {
            final json = jsonDecode(resp.body);
            if (json["status"] == "OK" && json["results"].isNotEmpty) {
              area = json["results"][0]["formatted_address"];
            }
          }
        } catch (_) {
          try {
            final placemarks = await placemarkFromCoordinates(
              position.latitude,
              position.longitude,
            );
            if (placemarks.isNotEmpty) {
              final p = placemarks.first;
              area = [
                p.name,
                p.street,
                p.locality,
                p.administrativeArea,
                p.country,
              ].whereType<String>().where((s) => s.isNotEmpty).join(", ");
            }
          } catch (_) {}
        }
      }

      final nowIST = DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 30),
      );

      final body = {
        "employeeId": userId,
        "companyId": prefs.getString('companyId') ?? '',
        "tripDate": tripDate,
        "startTime": startTime,
        "endTime": nowIST.toIso8601String(),
        "startLocation": {"longitude": startLng, "latitude": startLat},
        "endLocation": {
          "longitude": position?.longitude.toString() ?? "",
          "latitude": position?.latitude.toString() ?? "",
        },
        "endLocationName": area,
        "startKmReading": startKm,
        "endKmReading": endKmReading.toString(),
        "totalKm": totalKm,
        "localTripId": localTripId,
        "__deferUntilMapped": true,
      };

      debugPrint("📤 Trip End Payload: $body");

      final path = AppConfig.tripById.replaceAll('{id}', localTripId);

      try {
        final resp = await apiClient.sendOrQueue(
          method: HttpVerb.put,
          path: path,
          jsonBody: body,
          optimisticOk: true,
        );

        if (resp == null) {
          debugPrint("🟡 Trip end queued (offline/timeout)");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Trip ended queued'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
          await _setStartState(StartTripSyncState.idle);
          UnifiedLocationManager().onTripStopped();
          return true;
        }

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          debugPrint("✅ Trip End Success: ${resp.body}");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Trip ended successfully'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
          await _setStartState(StartTripSyncState.idle);
          // ✅ CLEAR all trip-related prefs
          await prefs.remove('currentTripStartTime');
          await prefs.remove('currentTripDate');
          await prefs.remove('currentTripStartLat');
          await prefs.remove('currentTripStartLng');
          await prefs.remove('currentTripStartKm');
          await prefs.remove('currentTripLocalId');
          await prefs.remove('totalKm');
          UnifiedLocationManager().onTripStopped();
          return true;
        }

        debugPrint("⚠️ Trip End HTTP error: ${resp.statusCode}");
        // ✅ CLEAR all trip-related prefs on error too
        try {
          await prefs.remove('currentTripStartTime');
          await prefs.remove('currentTripDate');
          await prefs.remove('currentTripStartLat');
          await prefs.remove('currentTripStartLng');
          await prefs.remove('currentTripStartKm');
          await prefs.remove('currentTripLocalId');
          await prefs.remove('totalKm');
        } catch (_) {}

        await _persistTripFailedRecord(
          method: 'PUT',
          path: path,
          jsonBody: body,
          statusCode: resp.statusCode,
          reason: resp.statusCode >= 500
              ? FailureReason.maxAttemptsReached
              : FailureReason.permanentClientError,
          errorDetail:
              'HTTP ${resp.statusCode}: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}',
        );

        try {
          final decoded = jsonDecode(resp.body);

          String message = '';

          if (decoded is Map<String, dynamic>) {
            message =
                decoded['message']?.toString() ??
                decoded['error']?.toString() ??
                decoded['msg']?.toString() ??
                resp.body;
          } else {
            message = resp.body;
          }

          debugPrint("❌ Error Message => $message");

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), backgroundColor: Colors.red),
            );
          }
        } catch (e) {
          debugPrint("❌ Raw Error Body => ${resp.body}");
        }
        return true;
      } on TimeoutException catch (e) {
        debugPrint("⚠️ Trip End timeout → queued: $e");
        // ✅ Clear trip state even on timeout
        try {
          await prefs.remove('currentTripStartTime');
          await prefs.remove('currentTripDate');
          await prefs.remove('currentTripStartLat');
          await prefs.remove('currentTripStartLng');
          await prefs.remove('currentTripStartKm');
          await prefs.remove('currentTripLocalId');
          await prefs.remove('totalKm');
        } catch (_) {}
        return true;
      } catch (e) {
        debugPrint("❌ Trip End sendOrQueue error: $e");
        // ✅ Clear trip state on exception too
        try {
          await prefs.remove('currentTripStartTime');
          await prefs.remove('currentTripDate');
          await prefs.remove('currentTripStartLat');
          await prefs.remove('currentTripStartLng');
          await prefs.remove('currentTripStartKm');
          await prefs.remove('currentTripLocalId');
          await prefs.remove('totalKm');
        } catch (_) {}
        return true; // treat as queued
      }
    } catch (e, st) {
      debugPrint("❌ Trip End fatal error: $e\n$st");
      await _persistTripFailedRecord(
        method: 'PUT',
        path: AppConfig.tripById.replaceAll('{id}', ''),
        jsonBody: null,
        statusCode: 0,
        reason: FailureReason.maxAttemptsReached,
        errorDetail: e.toString(),
      );
      return false;
    }
  }

  Future<void> _confirmStartNewTrip() async {
    // avoid double taps while a start is already running
    if (_isStartingTrip) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: Color.fromARGB(255, 255, 0, 0),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Reset Trip?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This will reset the current trip data (timer, distance, route, destination). Are you sure?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color.fromARGB(150, 255, 0, 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'No',
                          style: TextStyle(
                            color: Color.fromARGB(221, 255, 255, 255),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Color(0xFF1AB69C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (ok == true) {
      await _resetTrip(); // clear current data
      //await _startTripWithoutDestination(); // start fresh free-ride (guarded)
    }
  }

  Future<void> _resetTrip() async {
    _tripTimer?.cancel();
    _positionStream?.cancel();
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();

    await _clearTripSessionData();

    setState(() {
      _destination = null;
      _routePoints = [];
      _routePointsFull = [];
      _routeDistance = null;
      _routeDuration = null;

      _polylines = <Polyline>{};

      _isTripStarted = false;
      _tripCompleted = false;
      _isEditing = false;

      _tripDuration = Duration.zero;
      _elapsedTime = Duration.zero;
      _kmCovered = 0.0;
      _tripStartTime = null;

      _predictions = [];
      _showSearchField = false;
      _searchController.clear();
      _recenterTick++;
      _isStartingTrip = false; // ✅ release
      _distanceRemainingKm = null;
      _durationRemainingMin = null;
      _lastEtaRefreshAt = null;
      _lastValidDistanceKm = null;
      _lastValidDurationMin = null;
    });
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),

          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF52D494), // top gradient color
                    Color((0xFF1AB69C)), // bottom gradient color
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: AppBar(
                backgroundColor: Colors.transparent, // must be transparent
                elevation: 0,
                automaticallyImplyLeading: false,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                title: const Text(
                  'Trip',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
                centerTitle: true,

                // shape: const RoundedRectangleBorder(
                //   borderRadius: BorderRadius.vertical(
                //     bottom: Radius.circular(16),
                //   ),
                // ),
                actions: [
                  if (!_isTripStarted && !_tripCompleted)
                    Container(
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.search,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () {
                          if (!mounted) return;
                          setState(() => _showSearchField = true);
                          _startSearchSession();
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) {
                              FocusScope.of(
                                context,
                              ).requestFocus(_searchFocusNode);
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                if (_showSearchField) ...[
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFF1AB69C),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      enabled: !_isTripStarted && !_tripCompleted,
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      cursorColor: Color(0xFF1AB69C),
                      decoration: InputDecoration(
                        hintText:
                            "Search destination (e.g., Mumbai, Delhi, Bangalore)...",
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: const Icon(
                          Icons.location_on,
                          color: Color(0xFF1AB69C),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(
                            color: Color(0xFF1AB69C),
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (context, value, _) {
                            final hasText = value.text.trim().isNotEmpty;
                            if (!hasText) {
                              return const SizedBox(width: 0, height: 0);
                            }
                            return Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(
                                  Icons.close,
                                  color: Color(0xFF1AB69C),
                                  size: 20,
                                ),
                                onPressed: _clearSearchField,
                              ),
                            );
                          },
                        ),
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: (value) async {
                        if (_predictions.isNotEmpty) {
                          await _onPredictionTap(_predictions.first);
                        } else {
                          await _searchPlace(value);
                          setState(() => _showSearchField = false);
                          _endSearchSession();
                        }
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  if (_predictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _predictions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _predictions[i];
                          return ListTile(
                            leading: const Icon(
                              Icons.place,
                              color: Color(0xFF2E7D32),
                            ),
                            title: Text(
                              p.mainText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              p.secondaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _onPredictionTap(p),
                          );
                        },
                      ),
                    ),
                ],

                // Map
                TripMapWidget(
                  // mapControllerCompleter: _mapController, // if your widget supports it
                  currentLocation: _currentLocation,
                  destination: _destination,
                  routePoints: _routePoints,
                  isMapLoading: _isMapLoading,
                  onMapTapped: (_) {},
                  onLocationChanged: (_) {},
                  recenterTrigger: _recenterTick,
                  polylines: _polylines,
                  onCameraMove: (cam) => _followZoom = cam.zoom,
                  trafficEnabled: _isTripStarted && !_isFreeRide,
                  showMarkers: !_isTripStarted,
                  followCamera: _isTripStarted,
                  courseUp: true,
                  followSuspendMs: 5000,
                  onUserGesture: () {
                    if (!_isTripStarted) return;
                    setState(() => _followMe = false);
                    _followResumeTimer?.cancel();
                    _followResumeTimer = Timer(const Duration(seconds: 15), () {
                      if (!mounted) return;
                      setState(() {
                        _followMe = true;
                        _recenterTick++;
                      });
                    });
                  },
                  // 👇 NEW: show Google’s blue “my location” dot & button
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),

                // Controls
                TripControlsWidget(
                  isTripStarted: _isTripStarted,
                  tripCompleted: _tripCompleted,
                  elapsedTime: _elapsedTime,
                  distanceTraveled: _distanceTraveled,
                  tripDuration: _tripDuration,
                  kmCovered: _kmCovered,

                  // 👇 Card will behave like Free-Ride during a running trip
                  routeDistance: _uiRouteDistance,
                  routeDuration: _uiRouteDuration,
                  distanceRemainingKm: _uiRemainKm,
                  durationRemainingMin: _uiRemainMin,
                  etaLastUpdatedAt: _uiEtaUpdatedAt,

                  isEditing: _isEditing,
                  onStartTrip: (_isBusy || _destination == null)
                      ? null
                      : _startTrip,
                  onEndTrip: _isBusy ? null : _endTrip,
                  onStartTripWithoutDestination: _isBusy
                      ? null
                      : _startTripWithoutDestination,
                  onResetTrip: (_isStartingTrip) ? null : _confirmStartNewTrip,
                  onOpenInGoogleMaps: _openInGoogleMaps,
                ),
              ],
            ),
          ),
        ),
        //if (_showHud || _hudLines.isNotEmpty) _buildHud(),
        // ADD: loader overlay when busy
        if (_isBusy) _buildLoaderOverlay(),
      ],
    );
  }
}
