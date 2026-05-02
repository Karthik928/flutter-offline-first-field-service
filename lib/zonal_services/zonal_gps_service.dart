import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

/// GPS snapshot — timestamp comes from [gps.updatedAt] in the API response,
/// NOT from when the HTTP call was made.
class EmployeeGpsSnapshot {
  final double latitude;
  final double longitude;
  final double? speed;
  final double? accuracy;

  /// The actual time the device last sent its location — from [gps.updatedAt].
  final DateTime gpsUpdatedAt;

  EmployeeGpsSnapshot({
    required this.latitude,
    required this.longitude,
    required this.gpsUpdatedAt,
    this.speed,
    this.accuracy,
  });

  /// Parses the [gps] object from the employee API:
  /// {
  ///   "latitude": 17.544101,
  ///   "longitude": 78.3642476,
  ///   "updatedAt": "2026-03-11T06:19:20.228Z"   ← used as the timestamp
  /// }
  factory EmployeeGpsSnapshot.fromJson(Map<String, dynamic> gps) {
    final rawAt = gps['updatedAt'];

    DateTime updatedAt;
    try {
      updatedAt = rawAt != null
          ? DateTime.parse(rawAt).toLocal()
          : DateTime.now();
    } catch (_) {
      updatedAt = DateTime.now();
    }

    return EmployeeGpsSnapshot(
      latitude: (gps['latitude'] as num).toDouble(),
      longitude: (gps['longitude'] as num).toDouble(),
      gpsUpdatedAt: updatedAt,
      speed: (gps['speed'] as num?)?.toDouble(),
      accuracy: (gps['accuracy'] as num?)?.toDouble(),
    );
  }
}

class _GpsResult {
  final bool success;
  final EmployeeGpsSnapshot? data;
  final String? error;
  _GpsResult({required this.success, this.data, this.error});
}

/// Polls the single-employee search endpoint:
///   GET /api/zonal-data/employees?search=`<empCode>`
///
/// every [pollInterval] (default 10 s) and exposes a
/// [Stream<EmployeeGpsSnapshot>] for [EmployeeTrackingScreen].
///
/// Usage:
///   final svc = ZonalGpsService(empCode: 'EMP0019');
///   svc.stream.listen((snap) { ... });
///   svc.start();
///   // later
///   svc.dispose();
class ZonalGpsService {
  /// The empCode of the employee to track, e.g. "EMP0019".
  final String empCode;
  final Duration pollInterval;

  ZonalGpsService({
    required this.empCode,
    this.pollInterval = const Duration(seconds: 10),
  });

  final _controller = StreamController<EmployeeGpsSnapshot>.broadcast();
  Timer? _timer;
  bool _active = false;

  Stream<EmployeeGpsSnapshot> get stream => _controller.stream;

  /// Start polling immediately then every [pollInterval].
  void start() {
    if (_active) return;
    _active = true;
    _fetch();
    _timer = Timer.periodic(pollInterval, (_) => _fetch());
  }

  /// Pause polling (e.g. user taps PAUSED).
  void pause() {
    _timer?.cancel();
    _timer = null;
    _active = false;
  }

  /// Resume after pause.
  void resume() => start();

  void dispose() {
    _timer?.cancel();
    if (!_controller.isClosed) _controller.close();
    _active = false;
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    final result = await _fetchFromApi();
    if (_controller.isClosed) return;

    if (result.success && result.data != null) {
      _controller.add(result.data!);
    } else {
      _controller.addError(result.error ?? 'Unknown GPS error');
    }
  }

  Future<_GpsResult> _fetchFromApi() async {
    try {
      final token = await SecureStorageService.getToken();
      if (token == null || token.isEmpty) {
        return _GpsResult(success: false, error: 'UNAUTHORIZED');
      }

      // ── Single-employee search endpoint ──────────────────────────────────
      // GET /api/zonal-data/employees?search=EMP0019
      final uri = Uri.parse(
        '${AppConfig.apiBase}${AppConfig.zonalEmployees}',
      ).replace(queryParameters: {'search': empCode});

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        return _GpsResult(success: false, error: 'UNAUTHORIZED');
      }
      if (response.statusCode != 200) {
        return _GpsResult(success: false, error: 'HTTP ${response.statusCode}');
      }

      final body = json.decode(response.body);
      final List data = (body['data'] as List?) ?? [];

      if (data.isEmpty) {
        return _GpsResult(success: false, error: 'Employee not found');
      }

      // Take the first (and usually only) match
      final employee = data.first as Map<String, dynamic>;
      final gps = employee['gps'] as Map<String, dynamic>?;

      // Guard: null lat/lng means device hasn't sent location yet
      if (gps == null || gps['latitude'] == null || gps['longitude'] == null) {
        return _GpsResult(success: false, error: 'No GPS data available');
      }

      return _GpsResult(success: true, data: EmployeeGpsSnapshot.fromJson(gps));
    } on TimeoutException {
      return _GpsResult(success: false, error: 'Request timed out');
    } catch (e) {
      return _GpsResult(success: false, error: e.toString());
    }
  }
}
