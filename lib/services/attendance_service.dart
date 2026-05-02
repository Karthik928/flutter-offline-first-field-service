import 'dart:convert';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';
import 'package:FieldService_app/services/trip_manager.dart';
import 'package:FieldService_app/services/unified_location_manager.dart';

/// Result returned from every AttendanceService operation.
/// The caller is fully responsible for UI — this class is pure data.
class AttendanceResult {
  final bool isOnDuty;
  final bool forceLogout;

  /// Non-null means something went wrong.
  /// '__NO_INTERNET__' → show offline dialog.
  /// Any other value  → show as a user-visible error message.
  final String? errorMessage;

  /// True when the request was queued for later sync (offline-first success).
  final bool wasQueued;

  const AttendanceResult({
    required this.isOnDuty,
    this.forceLogout = false,
    this.errorMessage,
    this.wasQueued = false,
  });

  bool get isSuccess => errorMessage == null && !forceLogout;
}

/// All attendance business logic in one reusable, testable service.
class AttendanceService {
  final http.Client _client;
  final bool _ownsClient;

  static const _kDutyKey = 'isOnDuty';
  static const _kDutyDateKey =
      'dutyStateDate'; // date the local flag was written
  static const _kCheckInTime = 'checkInTime';
  static const _kAttendanceDate = 'attendanceDate';

  AttendanceService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  void _debug(String message) {
    if (kDebugMode) debugPrint(message);
  }

  static Future<bool> isOnDutyCachedForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _isoDateStatic(_nowISTStatic());

      final dutyDate = prefs.getString(_kDutyDateKey);
      return dutyDate == today && (prefs.getBool(_kDutyKey) ?? false);
    } catch (e) {
      debugPrint('[Attendance] isOnDutyCachedForToday: error=$e');
      return false;
    }
  }

  /// Call this in the owning widget's dispose().
  /// Only closes the client if this service created it.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────────

  /// Load today's attendance status from server and sync local state.
  /// NEVER uses local state to override server truth — only as fallback if API fails.
  /// On API success (200/201), server is source of truth and local state is synced.
  /// On API failure or no internet, local state is used as fallback only.
  /// Never throws — always returns an [AttendanceResult].
  /// Load today's attendance status from server and sync local state.
  Future<AttendanceResult> loadTodayAttendance() async {
    _debug('[Attendance] loadTodayAttendance() start');
    try {
      // ── Bug 6: Proactively clear any stale attendance ID from a previous day.
      // This runs before the API call so checkout on a new day never uses
      // yesterday's ID even if the server is unreachable.
      await _validAttendanceIdForToday();

      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) {
        _debug('[Attendance] ⚠️ No token → using local state as fallback');
        final local = await _localDutyForToday();
        return AttendanceResult(isOnDuty: local);
      }

      final uri = AppConfig.u(AppConfig.attendanceToday);
      final resp = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 12));

      _debug('[Attendance] API response status=${resp.statusCode}');

      if (resp.statusCode == 401) {
        _debug('[Attendance] 🔴 401 Unauthorized → force logout');
        return const AttendanceResult(isOnDuty: false, forceLogout: true);
      }

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        _debug(
          '[Attendance] ⚠️ API error ${resp.statusCode} → falling back to local state',
        );
        final local = await _localDutyForToday();
        return AttendanceResult(isOnDuty: local);
      }

      final decoded = _decodeBody(resp.body);
      final attendanceMap = decoded['data'] as Map<String, dynamic>?;

      if (attendanceMap == null) {
        _debug(
          '[Attendance] ⚠️ API success but no data → falling back to local state',
        );
        final local = await _localDutyForToday();
        return AttendanceResult(isOnDuty: local);
      }

      final isOnline = attendanceMap['isOnline'] as bool? ?? false;
      final attendanceId =
          attendanceMap['_id']?.toString() ?? attendanceMap['id']?.toString();
      _debug('[Attendance] ✅ Server source of truth: isOnline=$isOnline');

      final prefs = await SharedPreferences.getInstance();
      await _persistDutyState(isOnline);
      if (isOnline) {
        await prefs.setString(_kAttendanceDate, _isoDate(_nowIST()));
        if (attendanceId != null && attendanceId.isNotEmpty) {
          await SecureStorageService.saveAttendanceId(attendanceId);
          _debug(
            '[Attendance] loadTodayAttendance: saved attendanceId=$attendanceId',
          );
        } else {
          await SecureStorageService.deleteAttendanceId();
        }
      } else {
        await SecureStorageService.deleteAttendanceId();
        await prefs.remove(_kAttendanceDate);
        await prefs.remove(_kCheckInTime);
      }
      await _syncLocationManager(isOnline);

      return AttendanceResult(isOnDuty: isOnline);
    } on TimeoutException {
      _debug('[Attendance] ⚠️ Timeout → falling back to local state');
      final local = await _localDutyForToday();
      return AttendanceResult(isOnDuty: local);
    } on Exception catch (e) {
      _debug('[Attendance] ⚠️ Exception: $e → falling back to local state');
      final local = await _localDutyForToday();
      return AttendanceResult(isOnDuty: local);
    }
  }

  /// Check-in (ON DUTY). Works offline — queues the request if necessary.
  /// Returns successful result even if queued offline (optimistic).
  Future<AttendanceResult> checkIn({required bool currentDutyState}) async {
    if (currentDutyState) {
      _debug('[Attendance] checkIn: already on duty → no-op');
      return const AttendanceResult(isOnDuty: true);
    }

    // ── Internet check ────────────────────────────────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      final companyId = prefs.getString('companyId');

      if (userId == null || companyId == null) {
        _debug('[Attendance] checkIn: missing userId or companyId');
        return const AttendanceResult(
          isOnDuty: false,
          errorMessage: 'User session is invalid. Please log in again.',
        );
      }

      final pos = await _getPositionFast();
      final loginLocation = pos != null
          ? await _reverseGeocodeFast(pos)
          : 'Unknown area';
      final nowIST = _nowIST();
      final todayStr = _isoDate(nowIST);

      final body = {
        'employee': userId,
        'companyId': companyId,
        'date': todayStr,
        'checkInTime': nowIST.toIso8601String(),
        'loginLocation': loginLocation,
        'isOnline': true,
        'status': 'Present',
      };

      _debug('[Attendance] checkIn: sending request to API');
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: AppConfig.attendance,
        jsonBody: body,
        optimisticOk: true, // ← returns null when queued offline
      );

      // ── Offline / queued ──────────────────────────────────────────────────
      if (resp == null) {
        _debug(
          '[Attendance] checkIn: queued offline — optimistically persisting local state',
        );
        await _persistDutyState(true, date: todayStr);
        await prefs.setString(_kAttendanceDate, todayStr);
        await prefs.setString(_kCheckInTime, nowIST.toIso8601String());
        await UnifiedLocationManager().startPunchTracking();
        return const AttendanceResult(isOnDuty: true, wasQueued: true);
      }

      // ── 401 ───────────────────────────────────────────────────────────────
      if (resp.statusCode == 401) {
        _debug('[Attendance] checkIn: 401 Unauthorized');
        return const AttendanceResult(isOnDuty: false, forceLogout: true);
      }

      // ── Success ───────────────────────────────────────────────────────────
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        _debug('[Attendance] checkIn: ✅ success (${resp.statusCode})');
        final decoded = _decodeBody(resp.body);
        final attendanceId =
            decoded['_id'] ?? decoded['data']?['_id'] ?? decoded['data']?['id'];

        await _persistDutyState(true, date: todayStr);
        await prefs.setString(_kAttendanceDate, todayStr);
        await prefs.setString(_kCheckInTime, nowIST.toIso8601String());
        if (attendanceId != null) {
          await SecureStorageService.saveAttendanceId(attendanceId.toString());
          _debug('[Attendance] checkIn: stored attendanceId=$attendanceId');
        }
        await UnifiedLocationManager().startPunchTracking();
        return const AttendanceResult(isOnDuty: true);
      }

      // ── Server error ──────────────────────────────────────────────────────
      _debug(
        '[Attendance] checkIn: ❌ server error ${resp.statusCode}: ${resp.body}',
      );
      final serverMsg = _extractMessage(resp.body);
      return AttendanceResult(
        isOnDuty: false,
        errorMessage:
            serverMsg ??
            'Check-in failed (${resp.statusCode}). Please try again.',
      );
    } on Exception catch (e) {
      _debug('[Attendance] checkIn: ❌ exception: $e');
      return AttendanceResult(
        isOnDuty: false,
        errorMessage:
            'Check-in failed. Please check your connection and try again.',
      );
    }
  }

  /// Check-out (OFF DUTY). Works offline — queues the request if necessary.
  Future<AttendanceResult> checkOut({required bool currentDutyState}) async {
    _debug('[Attendance] checkOut: entry currentDutyState=$currentDutyState');
    if (!currentDutyState) {
      _debug('[Attendance] checkOut: already off duty → no-op');
      return const AttendanceResult(isOnDuty: false);
    }

    // ── Block if a trip is running ────────────────────────────────────────────
    final tripRunning = await isTripRunning();
    _debug('[Attendance] checkOut: tripRunning=$tripRunning');
    if (tripRunning) {
      _debug('[Attendance] checkOut: trip running → blocked');
      return const AttendanceResult(
        isOnDuty: true,
        errorMessage: 'Please end your current trip before going Off Duty.',
      );
    }

    // ── Internet check ────────────────────────────────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      var attendanceId = await _validAttendanceIdForToday();
      _debug('[Attendance] checkOut: resolved attendanceId=$attendanceId');

      // Resolve missing attendance ID from server before giving up.
      // doc10 — the block in question:
      // ✅ Replace the entire attendanceId-null block with this:
      if (attendanceId == null) {
        // Single internet check — result reused for both the fetch decision
        // and the error message, eliminating the duplicate 4-second ping.
        final hasInternet = await _hasInternet();
        _debug('[Attendance] checkOut: hasInternet=$hasInternet');

        if (hasInternet) {
          final record = await _fetchTodayAttendanceRecord();
          if (record != null) {
            attendanceId = record['_id']?.toString();
            _debug(
              '[Attendance] checkOut: fetched record id=$attendanceId '
              'isOnline=${record['isOnline']}',
            );
            if (attendanceId != null && attendanceId.isNotEmpty) {
              await SecureStorageService.saveAttendanceId(attendanceId);
              await prefs.setString(_kAttendanceDate, _isoDate(_nowIST()));
            }
          }
        }

        // If STILL null — reuse the already-known connectivity result.
        // No second ping. Ever.
        if (attendanceId == null || attendanceId.isEmpty) {
          _debug(
            '[Attendance] checkOut: unable to determine attendanceId, aborting.',
          );
          return AttendanceResult(
            isOnDuty: true,
            errorMessage: hasInternet
                ? 'Attendance ID is missing. You cannot punch out. '
                      'Please contact your administrator.'
                : 'Attendance record is unavailable offline on this device. '
                      'Please reconnect and try again.',
          );
        }
      }

      final pos = await _getPositionFast();
      final logoutLocation = pos != null
          ? await _reverseGeocodeFast(pos)
          : 'Unknown area';
      final nowIST = _nowIST();
      final checkInStr = prefs.getString(_kCheckInTime);

      Duration worked = Duration.zero;
      if (checkInStr != null) {
        try {
          worked = nowIST.difference(DateTime.parse(checkInStr));
        } catch (_) {}
      }
      final workedHours =
          '${worked.inHours}h ${(worked.inMinutes % 60).toString().padLeft(2, '0')}m';

      final body = {
        'checkOutTime': nowIST.toIso8601String(),
        'logoutLocation': logoutLocation,
        'isOnline': false,
        'remarks': 'NO',
        'workedHours': workedHours,
      };

      _debug(
        '[Attendance] checkOut: sending request to API (attendanceId=$attendanceId)',
      );
      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.put,
        path: '${AppConfig.attendance}/$attendanceId',
        jsonBody: body,
        optimisticOk: true,
      );

      // ── Offline / queued ──────────────────────────────────────────────────
      if (resp == null) {
        _debug(
          '[Attendance] checkOut: queued offline — optimistically persisting local state',
        );
        await _persistDutyState(false);
        await SecureStorageService.deleteAttendanceId();
        await prefs.remove(_kCheckInTime);
        UnifiedLocationManager().stopPunchTracking();
        return const AttendanceResult(isOnDuty: false, wasQueued: true);
      }

      _debug(
        '[Attendance] checkOut: API response status=${resp.statusCode} body=${resp.body}',
      );

      // ── 401 ───────────────────────────────────────────────────────────────
      if (resp.statusCode == 401) {
        _debug('[Attendance] checkOut: 401 Unauthorized');
        return const AttendanceResult(isOnDuty: true, forceLogout: true);
      }

      // ── Success ───────────────────────────────────────────────────────────
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        _debug('[Attendance] checkOut: ✅ success (${resp.statusCode})');
        await _persistDutyState(false);
        await SecureStorageService.deleteAttendanceId();
        await prefs.remove(_kCheckInTime);
        UnifiedLocationManager().stopPunchTracking();
        return const AttendanceResult(isOnDuty: false);
      }

      // ── Server error ──────────────────────────────────────────────────────
      _debug(
        '[Attendance] checkOut: ❌ server error ${resp.statusCode}: ${resp.body}',
      );
      final serverMsg = _extractMessage(resp.body);
      return AttendanceResult(
        isOnDuty: true,
        errorMessage:
            serverMsg ??
            'Check-out failed (${resp.statusCode}). Please try again.',
      );
    } on Exception catch (e) {
      _debug('[Attendance] checkOut: ❌ exception: $e');
      return AttendanceResult(
        isOnDuty: true,
        errorMessage:
            'Check-out failed. Please check your connection and try again.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // HELPERS — all non-throwing (return safe defaults on failure)
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns `true` when the device has a working internet connection.
  /// Uses multi-candidate check to avoid false negatives from blocked hosts.
  Future<bool> _hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) return false;
    } catch (_) {}

    // Try external connectivity endpoints only. App server reachability
    // is not a reliable indicator of internet availability.
    final candidates = <String>[
      'https://clients3.google.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
    ];

    for (final url in candidates) {
      try {
        final uri = Uri.parse(url);
        final resp = await http.get(uri).timeout(const Duration(seconds: 4));
        if (resp.statusCode < 500) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  /// Returns the local duty flag **only if it was written for today**.
  /// Stale flags from previous days (or after logout) are treated as false.
  /// This is safe because server is the source of truth; local cache is temporary.
  Future<bool> _localDutyForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final flagDate = prefs.getString(_kDutyDateKey);
      final today = _isoDate(_nowIST());

      if (flagDate == null) {
        _debug(
          '[Attendance] _localDutyForToday: no cached duty flag (fresh/logged-out) → false',
        );
        return false;
      }

      if (flagDate != today) {
        _debug(
          '[Attendance] _localDutyForToday: stale flag from $flagDate (today=$today) → false',
        );
        return false;
      }

      final cached = prefs.getBool(_kDutyKey) ?? false;
      _debug(
        '[Attendance] _localDutyForToday: using cached flag=$cached from today',
      );
      return cached;
    } catch (e) {
      _debug(
        '[Attendance] _localDutyForToday: error reading cache: $e → false',
      );
      return false;
    }
  }

  /// Persists the duty state along with today's date so stale flags can be detected.
  Future<void> _persistDutyState(bool isOnDuty, {String? date}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = date ?? _isoDate(_nowIST());
      await prefs.setBool(_kDutyKey, isOnDuty);
      await prefs.setString(_kDutyDateKey, today);
    } catch (e) {
      _debug('[Attendance] _persistDutyState failed: $e');
    }
  }

  /// Returns the stored attendance ID only if it was created today; null otherwise.
  Future<String?> _validAttendanceIdForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = await SecureStorageService.getAttendanceId();
      var storedDate = prefs.getString(_kAttendanceDate);
      final today = _isoDate(_nowIST());

      _debug(
        '[Attendance] _validAttendanceIdForToday: storedId=$storedId storedDate=$storedDate today=$today',
      );

      if (storedId == null || storedId.isEmpty) return null;

      // If we have a date stamp, validate it
      if (storedDate == null || storedDate.isEmpty) {
        final checkInTime = prefs.getString(_kCheckInTime);
        if (checkInTime != null && checkInTime.length >= 10) {
          storedDate = checkInTime.substring(0, 10);
        }

        storedDate ??= prefs.getString(_kDutyDateKey);
        if (storedDate != null && storedDate.isNotEmpty) {
          await prefs.setString(_kAttendanceDate, storedDate);
          _debug(
            '[Attendance] _validAttendanceIdForToday: backfilled attendanceDate=$storedDate',
          );
        }
      }

      if (storedDate == null || storedDate != today) {
        _debug(
          '[Attendance] Stale attendance ID (date=$storedDate) → clearing',
        );
        await SecureStorageService.deleteAttendanceId();
        await prefs.remove(_kAttendanceDate);
        await prefs.remove(_kCheckInTime);
        return null;
      }

      return storedId;
    } catch (e) {
      _debug('[Attendance] _validAttendanceIdForToday: exception $e');
      return null;
    }
  }

  /// Checks whether a trip is currently active.
  Future<bool> isTripRunning() async {
    // Primary: TripManager in-memory (fastest, most reliable)
    try {
      if (TripManager.active != null) return true;
    } catch (_) {}

    // Secondary: Hive bootstrap marker restored on app start.
    try {
      final Box tripBox = await Hive.openBox('current_trip');
      final dynamic active = tripBox.get('active');
      if (active is Map && active['status']?.toString() == 'started') {
        return true;
      }
    } catch (_) {}

    // Fallback: SharedPreferences start markers
    try {
      final prefs = await SharedPreferences.getInstance();
      final startTime = prefs.getString('currentTripStartTime');
      final localTripId = prefs.getString('currentTripLocalId');
      return startTime != null &&
          startTime.isNotEmpty &&
          localTripId != null &&
          localTripId.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchTodayAttendanceRecord() async {
    try {
      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) {
        _debug('[Attendance] _fetchTodayAttendanceRecord: no token');
        return null;
      }

      final uri = AppConfig.u(AppConfig.attendanceToday);
      final resp = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 12));

      _debug(
        '[Attendance] _fetchTodayAttendanceRecord: status=${resp.statusCode}',
      );
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        _debug(
          '[Attendance] _fetchTodayAttendanceRecord: failed status=${resp.statusCode}',
        );
        return null;
      }

      final decoded = _decodeBody(resp.body);
      final attendanceMap = decoded['data'] as Map<String, dynamic>?;
      if (attendanceMap == null) {
        _debug('[Attendance] _fetchTodayAttendanceRecord: no data in response');
        return null;
      }
      return attendanceMap;
    } catch (e) {
      _debug('[Attendance] _fetchTodayAttendanceRecord: error=$e');
      return null;
    }
  }

  Future<void> _syncLocationManager(bool isOnline) async {
    try {
      final mgr = UnifiedLocationManager();
      if (isOnline && mgr.mode != LocationMode.punchTracking) {
        await mgr.startPunchTracking();
      } else if (!isOnline && mgr.mode == LocationMode.punchTracking) {
        mgr.stopPunchTracking();
      }
    } catch (e) {
      _debug('[Attendance] _syncLocationManager error: $e');
    }
  }

  /// Returns current IST time.
  DateTime _nowIST() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  static DateTime _nowISTStatic() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  /// "yyyy-MM-dd" in IST.
  String _isoDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _isoDateStatic(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// GPS position with fast last-known fallback.
  Future<Position?> _getPositionFast({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (_) {}
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocodes with Google API → placemark fallback → offline string.
  Future<String> _reverseGeocodeFast(
    Position p, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final lat = p.latitude;
    final lng = p.longitude;

    try {
      final url = AppConfig.googleMapsApiKey.isNotEmpty
          ? "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=${AppConfig.googleMapsApiKey}"
          : "";
      if (url.isNotEmpty) {
        final resp = await http.get(Uri.parse(url)).timeout(timeout);
        if (resp.statusCode == 200) {
          final json = _decodeBody(resp.body);
          if (json['status'] == 'OK' &&
              (json['results'] as List?)?.isNotEmpty == true) {
            return json['results'][0]['formatted_address'] as String;
          }
        }
      }
    } catch (_) {}

    try {
      final marks = await placemarkFromCoordinates(
        lat,
        lng,
      ).timeout(timeout, onTimeout: () => []);
      if (marks.isNotEmpty) {
        final p2 = marks.first;
        final parts = [
          p2.subLocality,
          p2.locality,
          p2.administrativeArea,
        ].where((s) => s != null && s.trim().isNotEmpty);
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}

    return 'Offline — address unavailable';
  }

  Map<String, dynamic> _decodeBody(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  String? _extractMessage(String body) {
    try {
      final decoded = _decodeBody(body);
      final msg = decoded['message'] ?? decoded['error'] ?? decoded['msg'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
    } catch (_) {}
    return null;
  }
}
