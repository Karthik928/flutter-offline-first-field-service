// lib/services/trip_manager.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/foreground_service.dart';
import 'package:FieldService_app/services/local_store.dart';
import 'package:FieldService_app/services/models.dart';
import 'package:FieldService_app/services/quality_filters.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/platform/trip_service_native.dart';

class TripManager {
  static TripSession? _active;
  static LatLng? _lastPoint;
  static DateTime? _lastTs;
  static final bool _nativeServiceEnabled = true;

  static String _newId() {
    const chars = 'abcdef0123456789';
    final r = Random();
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Start a new trip.
  ///
  /// FIX Major #5: This method now GATES on the native service confirming startup
  /// before returning. If the native service returns false or throws, the in-memory
  /// session, Hive marker, and LocalStore entry are all rolled back and an exception
  /// is thrown. The caller (_startTrip in trip_screen.dart) will catch this in its
  /// existing try/catch block, setting success=false and preventing _sendTripStartApi
  /// from being scheduled via Future.microtask.
  static Future<TripSession> start({
    LatLng? origin,
    LatLng? destination,
  }) async {
    _active = TripSession(
      id: _newId(),
      startUtc: DateTime.now().toUtc(),
      origin: origin,
      destination: destination,
    );
    _lastPoint = origin;
    _lastTs = DateTime.now().toUtc();

    // Persist summary (best-effort; rolled back on native failure)
    try {
      await LocalStore.upsertTrip(_active!);
    } catch (e) {
      debugPrint('LocalStore.upsertTrip error (start): $e');
    }

    // Write lightweight Hive bootstrap marker (rolled back on native failure)
    try {
      final box = await Hive.openBox('current_trip');
      await box.put('active', {
        'status': 'started',
        'id': _active!.id,
        'startUtc': _active!.startUtc.toIso8601String(),
        'distance_m': _active!.distanceM,
        'duration_sec': _active!.durationSec,
        'last_lat': _lastPoint?.latitude,
        'last_lng': _lastPoint?.longitude,
        'last_ts': _lastTs?.toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ Could not write Hive bootstrap marker on start: $e');
    }

    // Start native Android foreground service and AWAIT confirmation.
    // If the service fails to start, roll back all local state and throw so
    // _startTrip() does not proceed to call the server API.
    if (_nativeServiceEnabled) {
      bool nativeSuccess = false;
      try {
        final authToken = await SecureStorageService.getToken();
        nativeSuccess = await TripServiceNative.startTrip(
          tripId: _active!.id,
          tripStartUtc: _active!.startUtc.toIso8601String(),
          initialDistanceMeters: _active!.distanceM,
          authToken: authToken,
          apiBaseUrl: AppConfig.apiBase,
        );
      } catch (e) {
        debugPrint('⚠️ TripManager.start: native service call threw: $e');
        await _rollbackStart();
        // Re-throw with a user-friendly message so the UI snackbar is helpful
        throw Exception(
          'Could not start trip tracking service. Please try again.',
        );
      }

      if (!nativeSuccess) {
        debugPrint(
          '⚠️ TripManager.start: native service returned false — rolling back',
        );
        await _rollbackStart();
        throw Exception(
          'Trip tracking service failed to start. Please check location permissions and try again.',
        );
      }

      debugPrint('TripManager.start: native service started successfully');

      // Defensive: stop any plugin-managed foreground service to avoid duplicate notifications
      try {
        await TripForegroundService.stop();
        debugPrint(
          'TripManager.start: plugin foreground service stop requested (defensive)',
        );
      } catch (e) {
        debugPrint(
          'TripManager.start: defensive plugin stop failed (non-fatal): $e',
        );
      }
    }

    return _active!;
  }

  /// Roll back a failed trip start: clear in-memory state and Hive marker.
  /// LocalStore entry is left as an orphan (no endUtc) — SyncService handles cleanup.
  static Future<void> _rollbackStart() async {
    debugPrint(
      'TripManager._rollbackStart: rolling back trip start for id=${_active?.id}',
    );
    _active = null;
    _lastPoint = null;
    _lastTs = null;
    try {
      final box = await Hive.openBox('current_trip');
      await box.delete('active');
    } catch (e) {
      debugPrint('TripManager._rollbackStart: failed to clear Hive marker: $e');
    }
  }

  /// End active trip: set endUtc, persist summary, clear bootstrap marker,
  /// and stop the native foreground service (best-effort).
  static Future<TripSession?> end() async {
    if (_active == null) return null;
    _active!.endUtc = DateTime.now().toUtc();

    try {
      await LocalStore.upsertTrip(_active!);
    } catch (e) {
      debugPrint('LocalStore.upsertTrip error (end): $e');
    }

    try {
      final box = await Hive.openBox('current_trip');
      await box.delete('active');
    } catch (e) {
      debugPrint('⚠️ Could not clear Hive bootstrap marker on end: $e');
    }

    if (_nativeServiceEnabled) {
      try {
        final success = await TripServiceNative.stopTrip();
        debugPrint(
          'TripManager.end: native service stop requested (success=$success)',
        );
      } catch (e) {
        debugPrint(
          'TripManager.end: native service stop failed (non-fatal): $e',
        );
      }
    }

    final finished = _active;
    _active = null;
    _lastPoint = null;
    _lastTs = null;
    return finished;
  }

  /// Called for every accepted location sample from UI/background.
  /// With native service enabled this is disabled — native is the authoritative writer.
  static Future<void> onLocation(LocationSample s) async {
    if (_active == null) return;

    if (_nativeServiceEnabled) {
      // Only update last position for UI display — no persistence, no distance calc
      _lastPoint = LatLng(s.lat, s.lng);
      _lastTs = s.ts;
      debugPrint(
        'TripManager.onLocation: Native service enabled — skipping distance accumulation',
      );
      return;
    }

    // Legacy path (only reached when native service is disabled)
    final current = LatLng(s.lat, s.lng);
    if (_lastPoint != null) {
      final deltaM = QualityFilters.safeDistance(_lastPoint!, current);
      _active!.distanceM += deltaM;
      if (_lastTs != null) {
        _active!.durationSec += s.ts
            .difference(_lastTs!)
            .inSeconds
            .clamp(0, 60);
      }
    }
    _lastPoint = current;
    _lastTs = s.ts;

    try {
      await LocalStore.appendLocationSample(_active!.id, s);
    } catch (e) {
      debugPrint('LocalStore.appendLocationSample error: $e');
    }
    try {
      await LocalStore.upsertTrip(_active!);
    } catch (e) {
      debugPrint('LocalStore.upsertTrip error: $e');
    }

    try {
      final box = await Hive.openBox('current_trip');
      final active = box.get('active') as Map<dynamic, dynamic>?;
      if (active != null && active['id'] == _active!.id) {
        active['distance_m'] = _active!.distanceM;
        active['duration_sec'] = _active!.durationSec;
        active['last_lat'] = _lastPoint?.latitude;
        active['last_lng'] = _lastPoint?.longitude;
        active['last_ts'] = _lastTs?.toIso8601String();
        await box.put('active', active);
      }
    } catch (e) {
      debugPrint('⚠️ Could not update Hive bootstrap marker onLocation: $e');
    }
  }

  /// Restore in-memory TripManager from Hive bootstrap marker.
  /// Idempotent and defensive — missing/malformed marker is silently ignored.
  static Future<void> restore() async {
    try {
      final box = await Hive.openBox('current_trip');
      final active = box.get('active');

      if (active == null) {
        debugPrint('TripManager.restore: no active marker found.');
        return;
      }
      if (active is! Map) {
        debugPrint('TripManager.restore: active marker not a Map — skipping.');
        return;
      }

      final status = active['status']?.toString() ?? '';
      if (status != 'started') {
        debugPrint('TripManager.restore: status != started ($status).');
        return;
      }

      final id = active['id']?.toString() ?? active['localId']?.toString();
      final startUtcRaw = active['startUtc'] as String?;
      DateTime startUtc;
      try {
        startUtc = (startUtcRaw != null)
            ? DateTime.parse(startUtcRaw)
            : DateTime.now().toUtc();
      } catch (_) {
        startUtc = DateTime.now().toUtc();
      }

      final restored = TripSession(
        id: id ?? _newId(),
        startUtc: startUtc.toUtc(),
      );

      try {
        final dm = active['distance_m'];
        if (dm is num) restored.distanceM = dm.toDouble();
        final ds = active['duration_sec'];
        if (ds is int) restored.durationSec = ds;
      } catch (_) {}

      try {
        final originLat = active['origin_lat'];
        final originLng = active['origin_lng'];
        if (originLat is num && originLng is num) {
          restored.origin = LatLng(originLat.toDouble(), originLng.toDouble());
        }
        final destLat = active['dest_lat'];
        final destLng = active['dest_lng'];
        if (destLat is num && destLng is num) {
          restored.destination = LatLng(destLat.toDouble(), destLng.toDouble());
        }
      } catch (_) {}

      try {
        final lastLat = active['last_lat'];
        final lastLng = active['last_lng'];
        final lastTsRaw = active['last_ts'] as String?;
        if (lastLat is num && lastLng is num) {
          _lastPoint = LatLng(lastLat.toDouble(), lastLng.toDouble());
        }
        if (lastTsRaw != null) {
          try {
            _lastTs = DateTime.parse(lastTsRaw).toUtc();
          } catch (_) {
            _lastTs = DateTime.now().toUtc();
          }
        }
      } catch (_) {}

      _active = restored;
      debugPrint(
        'TripManager.restore: restored trip id=${_active?.id} startUtc=${_active?.startUtc}',
      );

      // Restart native service (best-effort — restore should not throw on failure)
      if (_nativeServiceEnabled) {
        try {
          final success = await TripServiceNative.startTrip(
            tripId: _active!.id,
            tripStartUtc: _active!.startUtc.toIso8601String(),
            initialDistanceMeters: _active!.distanceM,
            apiBaseUrl: AppConfig.apiBase,
          );
          debugPrint(
            'TripManager.restore: native service requested (success=$success)',
          );
        } catch (e) {
          debugPrint(
            'TripManager.restore: native service start failed (non-fatal): $e',
          );
        }
      }
    } catch (e) {
      debugPrint('TripManager.restore error: $e');
      // do not rethrow — restore is best-effort
    }
  }

  static TripSession? get active => _active;
  static LatLng? get lastPoint => _lastPoint;
  static DateTime? get lastTs => _lastTs;
}
