// lib/services/foreground_service.dart
//
// Foreground service wrapper compatible with your installed flutter_foreground_task.
// Uses Geolocator inside the background task to stream locations and persist
// them via TripManager.onLocation(...).

import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;

import 'package:FieldService_app/services/models.dart';
import 'package:FieldService_app/services/trip_manager.dart';
import 'package:FieldService_app/services/local_store.dart';
import 'package:FieldService_app/services/quality_filters.dart';
import 'package:FieldService_app/platform/trip_service_native.dart';

class TripForegroundService {
  /// Initialize plugin (call; do not await because some plugin variants return void)
  static Future<void> init() async {
    FlutterForegroundTask.init(
      // 🚫 Disable plugin notifications
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'disabled_channel',
        channelName: 'Disabled',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        showWhen: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),

      // ✅ REQUIRED by your plugin version
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
  }

  /// Start service
  /// Start service
  static Future<void> start(String tripId) async {
    // Ensure init completes (some plugin versions need awaited init).
    await init();

    // Defensive: if native service is running, do NOT start plugin foreground service
    try {
      final nativeRunning = await TripServiceNative.isServiceRunning();
      if (nativeRunning) {
        debugPrint(
          'TripForegroundService.start: native service running — skip plugin start',
        );
        return;
      }
    } catch (e) {
      debugPrint(
        'TripForegroundService.start: native isServiceRunning check failed: $e',
      );
      // proceed cautiously — fall through to plugin start attempt
    }

    // Save active id so background isolate can read it.
    await FlutterForegroundTask.saveData(key: "activeTripId", value: tripId);

    // On Android ensure location permission is present before starting service.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission required to start foreground service',
        );
      }
    }

    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        final currentId = await FlutterForegroundTask.getData<String>(
          key: 'activeTripId',
        );
        if (currentId == tripId) {
          debugPrint(
            'TripForegroundService.start: service already running for id=$tripId',
          );
          return;
        } else {
          debugPrint(
            'TripForegroundService.start: service running for different id=$currentId; stopping previous then starting new id=$tripId',
          );

          // Try to stop previous instance cleanly to avoid multiple engines.
          try {
            await FlutterForegroundTask.stopService();
            await FlutterForegroundTask.clearAllData();
            debugPrint(
              'TripForegroundService.start: stopped previous service (id=$currentId)',
            );
          } catch (e) {
            debugPrint(
              '⚠️ TripForegroundService.start: failed to stop existing service: $e',
            );
          }
        }
      }

      // final nativeRunning = await TripServiceNative.isServiceRunning();
      // if (!nativeRunning) {
      //   await FlutterForegroundTask.startService(
      //     notificationTitle: 'Trip Running',
      //     notificationText: 'Tap to return',
      //     callback: startCallback,
      //   );
      // }
    } catch (e) {
      // Log and annotate common permission/security errors
      try {
        final s = e.toString();
        if (s.contains('SecurityException') ||
            s.contains('requires permissions') ||
            s.contains('eligible')) {}
      } catch (_) {}
      rethrow;
    }
  }

  /// Stop service
  static Future<void> stop() async {
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        await FlutterForegroundTask.stopService();
      } else {
        debugPrint(
          'TripForegroundService.stop: service not running — skip stop()',
        );
      }
    } catch (e) {
      debugPrint('⚠️ TripForegroundService.stop: stopService error: $e');
    }

    try {
      await FlutterForegroundTask.clearAllData();
    } catch (e) {
      debugPrint('⚠️ TripForegroundService.stop: clearAllData error: $e');
    }
  }
}

/// Simple numerically-stable 1D Kalman filter used per-coordinate/speed.
/// We intentionally keep it lightweight and expose Q/R as tunables.
class Kalman1D {
  double x; // state (value)
  double p; // covariance
  final double q; // process noise
  final double r; // measurement noise

  Kalman1D({this.x = 0.0, this.p = 1.0, required this.q, required this.r});

  // Predict step (increase uncertainty)
  void predict() {
    p += q;
  }

  // Update with measurement z and return new state
  double update(double z) {
    predict();
    final k = p / (p + r);
    x = x + k * (z - x);
    p = (1 - k) * p;
    return x;
  }

  // Soft-seed: set state but DO NOT reset covariance (per restore requirement)
  void softSeed(double z) {
    x = z;
    // keep p unchanged so uncertainty decays naturally
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(TripTaskHandler());
}

class TripTaskHandler extends TaskHandler {
  // --- Location processing pipeline state -------------------------------------------------
  StreamSubscription<Position>? _positionSub;

  // Bounded queue: holds raw LocationSample objects awaiting processing.
  final List<LocationSample> _queue = <LocationSample>[];
  final int _queueMax = 16; // bounded; drop oldest when full
  bool _drainRunning = false; // guard: single drain loop

  // Simple 1D Kalman filters (lat, lng, speed)
  late Kalman1D _kfLat;
  late Kalman1D _kfLng;
  late Kalman1D _kfSpeed;
  bool _kalmanInitialized = false; // soft-seeding vs hard reset

  // Small movement buffer (noise suppression)
  LocationSample? _bufferBaseline; // last sample used as baseline for buffer
  double _bufferAccumMeters = 0.0;

  // Baseline (last accepted filtered sample)
  LocationSample? _lastAccepted;

  // Spike guard cooldown (during cooldown we advance baseline but do NOT add distance)
  DateTime? _spikeCooldownUntil;

  // FGS-scoped aggregates (authoritative when this foreground task runs)
  double _fgsDistanceM = 0.0;
  int _fgsDurationSec = 0;

  // Metrics counters
  int acceptedSamples = 0;
  int rejectedAccuracy = 0;
  int rejectedSpike = 0;
  int rejectedMocked = 0;
  int droppedQueueOverflow = 0;

  // UI throttling (send UI updates only every N meters or every N seconds)
  double _lastUiUpdateDistance = 0.0;
  DateTime? _lastUiUpdateAt;
  final double uiUpdateMeters = 5.0;
  final int uiUpdateSeconds = 5;

  // Tunables
  final double gpsAccuracyCutoff = 100.0; // meters
  final double minAcceptMeters = 3.0; // canonical promotion threshold (meters)
  final double minAcceptSpeedMps = 0.7; // m/s to force promotion
  final double maxJumpMeters = 30.0; // absolute jump threshold
  final double maxSpeedMps = 40.0; // used in jump allowance
  final int spikeCooldownSeconds = 10; // cooldown after spike

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final id = await FlutterForegroundTask.getData<String>(key: "activeTripId");
    debugPrint("🔥 Trip Started: $id");

    // Ensure kalman filters exist with default Q/R (tunable via code)
    _kfLat = Kalman1D(
      q: 1e-6,
      r: 1e-2,
    ); // latitude in degrees; tuned small Q for stability
    _kfLng = Kalman1D(q: 1e-6, r: 1e-2);
    _kfSpeed = Kalman1D(q: 1e-3, r: 1e-1);

    // If TripManager already has a last point (restore path), softly seed Kalman
    try {
      final seedPoint = TripManager.lastPoint;
      final seedTs = TripManager.lastTs;
      if (seedPoint != null && seedTs != null) {
        // Soft re-seed without resetting covariance (per requirements)
        final s = LocationSample(
          ts: seedTs,
          lat: seedPoint.latitude,
          lng: seedPoint.longitude,
          accuracyM: 0.0,
          speedMps: -1,
          isMocked: false,
        );
        _softSeedFromRestore(s);
        // When service is running, do NOT persist restored sample (requirement)
        debugPrint(
          'TripTaskHandler: seeded Kalman from TripManager.restore() (soft seed)',
        );
      }
    } catch (_) {}

    // Small initial check for location services; proceed even if disabled.
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("⚠️ Location services disabled (foreground task).");
      }

      // Start listening to position updates and enqueue samples for serialized processing.
      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              timeLimit: null,
            ),
          ).listen(
            (pos) async {
              try {
                final sample = LocationSample(
                  ts: DateTime.now().toUtc(),
                  lat: pos.latitude,
                  lng: pos.longitude,
                  accuracyM: pos.accuracy,
                  speedMps: (pos.speed > 0 ? pos.speed : -1),
                  isMocked: pos.isMocked,
                );

                // Bounded enqueue (drop-oldest when full). Keep metrics.
                if (_queue.length >= _queueMax) {
                  _queue.removeAt(0);
                  droppedQueueOverflow++;
                  // expose metrics to UI via FGS metadata (best-effort)
                  unawaited(
                    FlutterForegroundTask.saveData(
                      key: 'fgs_dropped_overflow',
                      value: droppedQueueOverflow.toString(),
                    ).catchError((e) {
                      debugPrint(e.toString());
                      return false; // ✅ must return bool
                    }),
                  );
                }
                _queue.add(sample);

                // Drain queue (serially) — guard ensures single drain loop
                _drainQueue();
              } catch (e) {
                debugPrint('TripTaskHandler.onPosition error: $e');
              }
            },
            onError: (err) {
              debugPrint('TripTaskHandler position stream error: $err');
            },
            cancelOnError: false,
          );
    } catch (e) {
      debugPrint(
        'TripTaskHandler.onStart error (could not start location stream): $e',
      );
    }
  }

  // Drain loop: processes queued samples serially (never parallel).
  void _drainQueue() {
    if (_drainRunning) return;
    _drainRunning = true;

    // Run asynchronously but serialized
    Future<void>(() async {
      try {
        while (_queue.isNotEmpty) {
          final s = _queue.removeAt(0);
          await _processSample(s);
        }
      } catch (e, st) {
        debugPrint('TripTaskHandler._drainQueue error: $e\n$st');
      } finally {
        _drainRunning = false;
      }
    });
  }

  // Process a single queued sample end-to-end through filters and persist if accepted.
  Future<void> _processSample(LocationSample s) async {
    // 1) Accuracy & mock rejection
    if (!s.accuracyM.isFinite || s.accuracyM > gpsAccuracyCutoff) {
      rejectedAccuracy++;
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_rejected_accuracy',
          value: rejectedAccuracy.toString(),
        ).catchError((e) {
          debugPrint(e.toString());
          return false; // ✅ must return bool
        }),
      );
      return; // drop sample
    }

    if (s.isMocked) {
      rejectedMocked++;
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_rejected_mocked',
          value: rejectedMocked.toString(),
        ).catchError((e) {
          debugPrint(e.toString());
          return false; // ✅ must return bool
        }),
      );
      return;
    }

    // 2) Kalman filtering (soft seed if first sample)
    if (!_kalmanInitialized) {
      // Soft init without wiping covariance (per requirement): set x but keep p.
      _kfLat.softSeed(s.lat);
      _kfLng.softSeed(s.lng);
      if (s.speedMps >= 0) _kfSpeed.softSeed(s.speedMps);
      _kalmanInitialized = true;

      // This is effectively our baseline. Do not count distance on seed.
      _lastAccepted = LocationSample(
        ts: s.ts,
        lat: _kfLat.x,
        lng: _kfLng.x,
        accuracyM: s.accuracyM,
        speedMps: s.speedMps,
        isMocked: s.isMocked,
      );
      _spikeCooldownUntil = null; // clear cooldowns
      _bufferBaseline = null;
      _bufferAccumMeters = 0.0;

      // Do NOT persist seed when running inside FGS (requirement), but update UI state.
      try {
        unawaited(
          TripManager.onLocation(_lastAccepted!).catchError(
            (e) => debugPrint('TripManager.onLocation error (seed): $e'),
          ),
        );
      } catch (_) {}
      return;
    }

    // Apply measurement update
    final filteredLat = _kfLat.update(s.lat);
    final filteredLng = _kfLng.update(s.lng);
    final filteredSpeed = (s.speedMps >= 0)
        ? _kfSpeed.update(s.speedMps)
        : _kfSpeed.x;

    final f = LocationSample(
      ts: s.ts,
      lat: filteredLat,
      lng: filteredLng,
      accuracyM: s.accuracyM,
      speedMps: filteredSpeed,
      isMocked: s.isMocked,
    );

    // Compute dt (seconds) from last accepted filtered sample
    final lastTs = _lastAccepted?.ts ?? s.ts;
    final rawDtMs = s.ts.difference(lastTs).inMilliseconds;
    final dtSeconds = rawDtMs.clamp(50, 60000) / 1000.0;

    // Compute canonical distance from baseline (meters)
    double distancingMeters = 0.0;
    if (_lastAccepted != null) {
      distancingMeters = QualityFilters.safeDistance(
        LatLng(_lastAccepted!.lat, _lastAccepted!.lng),
        LatLng(f.lat, f.lng),
      );
    }

    // 3) Spike / teleport guard
    final allowedJump = math.max(
      maxJumpMeters,
      maxSpeedMps * dtSeconds + s.accuracyM,
    );
    final now = DateTime.now().toUtc();
    if (distancingMeters > allowedJump) {
      // Spike detected: enter cooldown; advance baseline but do NOT add distance
      rejectedSpike++;
      _spikeCooldownUntil = now.add(Duration(seconds: spikeCooldownSeconds));

      // Advance baseline so we stay responsive, but never count distance during cooldown
      _lastAccepted = f;

      // Update UI pointers but avoid persisting as trusted sample
      unawaited(
        TripManager.onLocation(f).catchError(
          (e) => debugPrint('TripManager.onLocation error (spike advance): $e'),
        ),
      );
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_rejected_spike',
          value: rejectedSpike.toString(),
        ).catchError((e) {
          debugPrint('saveData error: $e');
          return false;
        }),
      );
      return;
    }

    // If currently in a cooldown window, advance baseline but do NOT add distance per requirement
    if (_spikeCooldownUntil != null && now.isBefore(_spikeCooldownUntil!)) {
      _lastAccepted = f;
      unawaited(
        TripManager.onLocation(f).catchError(
          (e) =>
              debugPrint('TripManager.onLocation error (cooldown advance): $e'),
        ),
      );
      return;
    }

    // 4) Small-movement buffer (noise suppression)
    if (distancingMeters < minAcceptMeters) {
      // Accumulate small movements; baseline to compare against is last accepted sample
      _bufferBaseline ??= _lastAccepted ?? f;
      _bufferAccumMeters += distancingMeters;

      // Promote only when buffer reaches threshold OR speed indicates motion
      if (_bufferAccumMeters >= minAcceptMeters ||
          s.speedMps >= minAcceptSpeedMps) {
        // Compute canonical distance using TripManager.lastPoint (per requirement)
        double canonical = 0.0;
        if (TripManager.lastPoint != null) {
          canonical = QualityFilters.safeDistance(
            TripManager.lastPoint!,
            LatLng(f.lat, f.lng),
          );
        } else {
          canonical = distancingMeters;
        }

        if (canonical <= 0.0) {
          // if canonical distance == 0 → DO NOT promote
          _bufferBaseline = null;
          _bufferAccumMeters = 0.0;
          return;
        }

        // Promote buffered position as a single accepted sample
        await _acceptFiltered(f, canonical, dtSeconds);
        _bufferBaseline = null;
        _bufferAccumMeters = 0.0;
        return;
      }

      // Not ready to promote - just return (no UI updates while in buffer)
      return;
    }

    // 5) If movement >= minAcceptMeters, accept normally
    if (distancingMeters >= minAcceptMeters) {
      // Canonical distance is computed against TripManager.lastPoint (per requirement)
      double canonical = 0.0;
      if (TripManager.lastPoint != null) {
        canonical = QualityFilters.safeDistance(
          TripManager.lastPoint!,
          LatLng(f.lat, f.lng),
        );
      } else {
        canonical = distancingMeters;
      }

      if (canonical <= 0.0) {
        // Do not promote if canonical == 0
        return;
      }

      await _acceptFiltered(f, canonical, dtSeconds);
      return;
    }

    // Everything else: ignore sample (should be unreachable)
    return;
  }

  // Accept a filtered sample: update distance/duration, persist, update UI metadata and counters.
  Future<void> _acceptFiltered(
    LocationSample filtered,
    double canonicalMeters,
    double dtSeconds,
  ) async {
    acceptedSamples++;

    // Update in-FGS aggregates (FGS is authoritative while running)
    _fgsDistanceM += canonicalMeters;
    _fgsDurationSec += dtSeconds.floor();

    // Advance baseline last-accepted
    _lastAccepted = filtered;

    // Persist to LocalStore (fire-and-forget, safe-wrapped)
    try {
      final active = TripManager.active;
      if (active != null) {
        // Append filtered sample to DB and update trip summary as authoritative writer
        unawaited(
          LocalStore.appendLocationSample(active.id, filtered).catchError(
            (e) => debugPrint('LocalStore.appendLocationSample error: $e'),
          ),
        );

        // Update TripSession summary fields (local authoritative snapshot)
        try {
          active.distanceM = _fgsDistanceM;
          active.durationSec = _fgsDurationSec;
          unawaited(
            LocalStore.upsertTrip(
              active,
            ).catchError((e) => debugPrint('LocalStore.upsertTrip error: $e')),
          );
        } catch (e) {
          debugPrint('Error updating TripSession active snapshot: $e');
        }
      }
    } catch (e) {
      debugPrint('Error persisting accepted sample: $e');
    }

    // Update TripManager in-memory state for UI (non-authoritative while FGS running)
    try {
      final now = DateTime.now().toUtc();
      final shouldUpdateUi =
          (now
                  .difference(
                    _lastUiUpdateAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  )
                  .inSeconds >=
              uiUpdateSeconds) ||
          ((_fgsDistanceM - _lastUiUpdateDistance) >= uiUpdateMeters);
      if (shouldUpdateUi) {
        _lastUiUpdateAt = now;
        _lastUiUpdateDistance = _fgsDistanceM;
        unawaited(
          TripManager.onLocation(filtered).catchError(
            (e) => debugPrint('TripManager.onLocation error (accept): $e'),
          ),
        );
      }
    } catch (_) {}
    // Expose aggregates and counters to UI via FGS metadata (HUD / debugging)
    try {
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_distance_m',
          value: _fgsDistanceM.toStringAsFixed(1),
        ).catchError((e) {
          debugPrint('saveData error: $e');
          return false;
        }),
      );
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_duration_sec',
          value: _fgsDurationSec.toString(),
        ).catchError((e) {
          debugPrint('saveData error: $e');
          return false;
        }),
      );
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_accepted',
          value: acceptedSamples.toString(),
        ).catchError((e) {
          debugPrint('saveData error: $e');
          return false;
        }),
      );
    } catch (_) {}
  }

  // Soft-seed Kalman filters from a restored sample without resetting covariance (per requirement)
  void _softSeedFromRestore(LocationSample s) {
    _kfLat.softSeed(s.lat);
    _kfLng.softSeed(s.lng);
    if (s.speedMps >= 0) _kfSpeed.softSeed(s.speedMps);
    _kalmanInitialized = true;
    _lastAccepted = LocationSample(
      ts: s.ts,
      lat: _kfLat.x,
      lng: _kfLng.x,
      accuracyM: s.accuracyM,
      speedMps: s.speedMps,
      isMocked: s.isMocked,
    );
    _spikeCooldownUntil = null; // clear cooldowns
    _bufferBaseline = null;
    _bufferAccumMeters = 0.0;
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // periodically trigger location stream to stay alive
    try {
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
    } catch (_) {}

    // FlutterForegroundTask.updateService(
    //   notificationTitle: "Trip Running",
    //   notificationText: "Last updated: ${timestamp.toIso8601String()}",
    // );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool canceledByUser) async {
    debugPrint("🛑 Foreground destroyed (canceledByUser=$canceledByUser)");

    // Flush up to N queued samples synchronously to avoid losing too much data on destroy.
    const int maxDrainOnDestroy = 8;
    int drained = 0;
    while (_queue.isNotEmpty && drained < maxDrainOnDestroy) {
      final s = _queue.removeAt(0);
      try {
        await _processSample(s);
      } catch (e) {
        debugPrint('Error flushing queued sample on destroy: $e');
      }
      drained++;
    }

    // If there are still items left, account metrics and drop them (capped)
    if (_queue.isNotEmpty) {
      droppedQueueOverflow += _queue.length;
      unawaited(
        FlutterForegroundTask.saveData(
          key: 'fgs_dropped_overflow',
          value: droppedQueueOverflow.toString(),
        ).catchError((e) {
          debugPrint('saveData error: $e');
          return false;
        }),
      );
      _queue.clear();
    }

    try {
      await _positionSub?.cancel();
      _positionSub = null;
    } catch (e) {
      debugPrint('Error cancelling position subscription: $e');
    }

    await FlutterForegroundTask.clearAllData();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp("/");
  }
}
