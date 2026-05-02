// lib/offline/sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FieldService_app/config.dart';
import 'package:geocoding/geocoding.dart';
import 'package:FieldService_app/offline/failed_record_model.dart';
import 'package:FieldService_app/offline/failed_record_store.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

import 'queue_store.dart';
import 'request_envelope.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SyncEvent
// ─────────────────────────────────────────────────────────────────────────────

/// Simple event you can listen to: tells you if a queued item synced or failed.
class SyncEvent {
  final String id;
  final bool success;
  final int statusCode;
  final String method;
  final String path;
  final String? error;

  SyncEvent({
    required this.id,
    required this.success,
    required this.statusCode,
    required this.method,
    required this.path,
    this.error,
  });

  @override
  String toString() =>
      'SyncEvent(id=$id, success=$success, code=$statusCode, $method $path, err=$error)';
}

// ─────────────────────────────────────────────────────────────────────────────
// SyncService
// ─────────────────────────────────────────────────────────────────────────────

class SyncService {
  final QueueStore _store;
  final http.Client _client;
  final FailedRecordStore _failedStore; // ← NEW: 3rd positional arg

  /// Maximum retry attempts before a record is dropped and persisted as failed.
  final int maxAttempts;

  Timer? _tick;
  bool _running = false;

  /// Max times a deferred item (waiting for TripStart mapping) is skipped
  /// before being dropped and recorded as failed.
  static const int maxDeferredSkips = 6;

  /// Broadcast stream — listen anywhere for sync results.
  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  SyncService(
    this._store,
    this._client,
    this._failedStore, { // ← NEW positional arg
    this.maxAttempts = 5,
  });

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void start() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => flush());
    Future.delayed(const Duration(seconds: 3), () => flush());
  }

  void stop() => _tick?.cancel();

  void dispose() {
    _tick?.cancel();
    _events.close();
  }

  // ── Logging helper ─────────────────────────────────────────────────────────

  void _log(String level, String message) {
    // Uncomment to enable verbose logging:
    // final ts = DateTime.now().toUtc().toIso8601String();
    // debugPrint('[$ts] [$level] $message');
  }

  // ── Failed-record persistence ──────────────────────────────────────────────

  /// Converts a terminal [RequestEnvelope] into a [FailedRecord] and writes it
  /// to [_failedStore] so the user can review it on the Failed Records screen.
  Future<void> _persistFailedRecord(
    RequestEnvelope env, {
    required int statusCode,
    required FailureReason reason,
    String? errorDetail,
  }) async {
    try {
      final record = FailedRecord(
        id: env.id,
        envelopeId: env.id,
        method: env.method.name.toUpperCase(),
        path: env.path,
        jsonBody: env.jsonBody != null
            ? Map<String, dynamic>.from(env.jsonBody!)
            : null,
        // Strip Authorization header — never persist tokens
        headers: Map<String, String>.from(env.headers)..remove('Authorization'),
        attachedFileNames: (env.files ?? []).map((f) => f.filename).toList(),
        lastStatusCode: statusCode,
        failureReason: reason,
        errorDetail: errorDetail,
        enqueuedAt: env.createdAt,
        failedAt: DateTime.now().toUtc(),
        attemptCount: env.attempt,
        recordType: FailedRecord.typeFromPath(
          env.path,
          env.method.name.toUpperCase(),
        ),
      );

      await _failedStore.add(record);
      _log(
        'INFO',
        'Persisted failed record id=${env.id} reason=${reason.name}',
      );
    } catch (e) {
      _log('WARN', 'Could not persist failed record id=${env.id}: $e');
    }
  }

  // ── Path helpers ───────────────────────────────────────────────────────────

  bool _isTripLifecyclePath(String path) =>
      path == AppConfig.trips || path.startsWith('/api/trips');

  // ── Remap after TripStart ──────────────────────────────────────────────────

  /// After a TripStart POST succeeds, update every queued item that still
  /// references [localId] (placeholder) to use the real [serverId].
  Future<void> _remapQueuedItemsAfterStart(
    String localId,
    String serverId,
  ) async {
    try {
      final items = await _store.all();
      for (final item in items) {
        var changed = false;

        // 1) Replace {localTripId} placeholder or literal localId in path
        if (item.path.contains('{localTripId}')) {
          final old = item.path;
          item.path = item.path.replaceAll('{localTripId}', serverId);
          changed = true;
          _log(
            'DEBUG',
            'Remap {localTripId} for ${item.id}: "$old" → "${item.path}"',
          );
        } else if (item.path.contains(localId)) {
          final old = item.path;
          item.path = item.path.replaceAll(localId, serverId);
          changed = true;
          _log('DEBUG', 'Remap path for ${item.id}: "$old" → "${item.path}"');
        }

        // 2) Replace localTripId in jsonBody and remove __deferUntilMapped
        String? bodyLocal;
        try {
          if (item.jsonBody != null) {
            bodyLocal = item.jsonBody!['localTripId']?.toString();
            if (bodyLocal == localId) {
              item.jsonBody!['localTripId'] = serverId;
              item.jsonBody!.remove('__deferUntilMapped');
              changed = true;
              _log(
                'DEBUG',
                'Rewrote json.localTripId for ${item.id} -> $serverId',
              );
            }
          }

          if (changed) {
            await _store.update(item);
            _log('DEBUG', 'Persisted remapped env ${item.id}');
            _events.add(
              SyncEvent(
                id: item.id,
                success: false,
                statusCode: 0,
                method: item.method.name.toUpperCase(),
                path: item.path,
                error: 'remapped-after-start',
              ),
            );
          }
        } catch (_) {}

        // 3) If path ends with a stale 24-hex ObjectId, replace it
        try {
          final re = RegExp(r'(/api/trips/)([^/]+)$');
          final m = re.firstMatch(item.path);
          if (m != null) {
            final existingId = m.group(2);
            if (existingId != null &&
                existingId.isNotEmpty &&
                existingId != serverId &&
                RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(existingId)) {
              final oldPath = item.path;
              item.path = item.path.replaceFirst(existingId, serverId);
              changed = true;
              _log(
                'DEBUG',
                'Replaced stale trailing id for ${item.id}: '
                    '"$oldPath" → "${item.path}"',
              );
            }
          }
        } catch (e) {
          _log('WARN', 'path-fix check failed for ${item.id}: $e');
        }

        // 4) If body localTripId matched but path has a different stale id
        try {
          if (!changed && bodyLocal == serverId) {
            final re = RegExp(r'(/api/trips/)([^/]+)$');
            final m = re.firstMatch(item.path);
            if (m != null) {
              final existingId = m.group(2);
              if (existingId != null &&
                  existingId.isNotEmpty &&
                  existingId != serverId &&
                  RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(existingId)) {
                final old = item.path;
                item.path = item.path.replaceFirst(existingId, serverId);
                changed = true;
                _log(
                  'DEBUG',
                  'Replaced stale id (body match) for ${item.id}: '
                      '"$old" → "${item.path}"',
                );
              }
            }
          }
        } catch (e) {
          _log('WARN', 'path-fix (body match) failed for ${item.id}: $e');
        }

        if (changed) {
          await _store.update(item);
          _events.add(
            SyncEvent(
              id: item.id,
              success: false,
              statusCode: 0,
              method: item.method.name.toUpperCase(),
              path: item.path,
              error: 'remapped-after-start',
            ),
          );
        }
      }
    } catch (e) {
      _log(
        'WARN',
        'Failed to remap queued items for $localId → $serverId : $e',
      );
    }
  }

  // ── flush() ────────────────────────────────────────────────────────────────

  /// Process the offline queue. Pass [force]=true to ignore backoff windows.
  Future<void> flush({bool force = false}) async {
    if (_running) {
      _log('DEBUG', 'flush skipped — already running');
      return;
    }
    _running = true;

    try {
      // Preflight: skip entirely if no transport
      final net = await Connectivity().checkConnectivity();
      if (net.contains(ConnectivityResult.none)) {
        _log('INFO', 'offline → skip flush (no backoff)');
        return;
      }

      // Secondary check: device actually has internet access
      if (!await _hasInternet()) {
        _log('WARN', 'connectivity available but internet unreachable');
        return;
      }

      var all = await _store.all();
      if (all.isEmpty) {
        _log('INFO', 'Queue empty → nothing to flush');
        return;
      }

      _log('INFO', 'flush start → ${all.length} item(s) (force=$force)');

      final now = DateTime.now().toUtc();

      for (var original in all) {
        // Reload latest from store to avoid stale envelope
        var env = await _store.getById(original.id) ?? original;

        _log('INFO', 'Processing queue item: ${env.id} (${env.path})');

        // Respect backoff window
        if (!force &&
            env.nextAttemptAt != null &&
            now.isBefore(env.nextAttemptAt!)) {
          final left = env.nextAttemptAt!.difference(now).inSeconds;
          _log('DEBUG', 'skip id=${env.id} (backoff ${left}s left)');
          continue;
        }

        // Refresh Authorization header
        try {
          final fresh = await SecureStorageService.getToken();
          if (fresh != null && fresh.isNotEmpty) {
            env.headers['Authorization'] = 'Bearer $fresh';
          }
        } catch (_) {}

        // Normalize location map → "lat lon" string
        if (env.jsonBody != null && env.jsonBody!.containsKey('location')) {
          final loc = env.jsonBody!['location'];
          if (loc is Map) {
            final lat = (loc['latitude'] ?? loc['lat'] ?? '').toString().trim();
            final lon = (loc['longitude'] ?? loc['lng'] ?? '')
                .toString()
                .trim();
            env.jsonBody!['location'] = '$lat $lon'
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
          } else if (loc is String) {
            env.jsonBody!['location'] = loc
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
          }
        }

        // Enrich address fields from coordinates if needed
        await _enrichAddressFromLocationIfNeeded(env);

        // Resolve localTripId → serverId mapping
        final mapping = await _readTripMapping();
        String resolvedPath = env.path;

        var deferFlag = env.jsonBody?['__deferUntilMapped'] == true;
        String localId = env.jsonBody?['localTripId']?.toString() ?? '';

        if (deferFlag && localId.isNotEmpty) {
          String? mapped = mapping[localId];

          // Try to recover mapping from path if json was already rewritten
          if (mapped == null || mapped.isEmpty) {
            for (final entry in mapping.entries) {
              final value = entry.value.toString();
              if (value.isNotEmpty && env.path.contains(value)) {
                mapped = value;
                localId = entry.key.toString();
                _log(
                  'DEBUG',
                  'Recovered mapping from path: $localId -> $value',
                );
                break;
              }
            }
          }

          // If server id is already in the path, bypass defer
          if (mapped != null &&
              mapped.isNotEmpty &&
              env.path.contains(mapped)) {
            _log('DEBUG', 'Mapping already in path → skip defer');
            deferFlag = false;
            resolvedPath = env.path;
            env.jsonBody?.remove('__deferUntilMapped');
            await _store.update(env);
          }

          // Still deferred: apply backoff or drop
          if (deferFlag) {
            env.attempt = env.attempt + 1;

            if (env.attempt >= maxAttempts || env.attempt >= maxDeferredSkips) {
              _log(
                'WARN',
                'TripEnd ${env.id}: no mapping for $localId after '
                    '${env.attempt} attempts → dropping',
              );

              // ── FAILED RECORD: dropped-deferred-no-mapping ──────────────
              await _persistFailedRecord(
                env,
                statusCode: 0,
                reason: FailureReason.droppedDeferredNoMapping,
                errorDetail:
                    'localTripId=$localId had no server mapping after '
                    '${env.attempt} attempts',
              );
              // ────────────────────────────────────────────────────────────

              await _store.remove(env.id);
              _events.add(
                SyncEvent(
                  id: env.id,
                  success: false,
                  statusCode: 0,
                  method: env.method.name.toUpperCase(),
                  path: env.path,
                  error: 'dropped-deferred-no-mapping',
                ),
              );
              continue;
            }

            final secs = _scheduleBackoff(env, reason: 'deferred-no-mapping');
            await _store.update(env);
            _events.add(
              SyncEvent(
                id: env.id,
                success: false,
                statusCode: 0,
                method: env.method.name.toUpperCase(),
                path: env.path,
                error: 'deferred-no-mapping',
              ),
            );
            _log(
              'DEBUG',
              'TripEnd deferred: $localId not mapped yet; '
                  'backoff ${secs}s (attempt=${env.attempt})',
            );
            continue;
          }
        }

        // Always sync resolvedPath with the (possibly updated) env.path
        resolvedPath = env.path;

        final uri = AppConfig.uri(resolvedPath);
        _log(
          'INFO',
          'send id=${env.id} ${env.method.name.toUpperCase()} $uri '
              '(attempt=${env.attempt + 1}, force=$force)',
        );

        try {
          http.Response resp;

          // ── Multipart (file upload) ──────────────────────────────────────
          if ((env.files ?? const []).isNotEmpty) {
            final req = http.MultipartRequest(
              env.method == HttpVerb.post ? 'POST' : 'PUT',
              uri,
            )..headers.addAll(env.headers);

            env.jsonBody?.forEach((k, v) {
              req.fields[k] = (v is String) ? v : jsonEncode(v);
            });

            for (final f in env.files!) {
              final http_parser.MediaType? mt = _guessMediaType(f.filename);
              req.files.add(
                await http.MultipartFile.fromPath(
                  f.field,
                  f.path,
                  filename: f.filename,
                  contentType: mt,
                ),
              );
            }

            final streamed = await req.send().timeout(AppConfig.httpTimeout);
            resp = await http.Response.fromStream(streamed);
          }
          // ── JSON request ─────────────────────────────────────────────────
          else {
            final hdrs = {...env.headers, 'Content-Type': 'application/json'};
            switch (env.method) {
              case HttpVerb.post:
                resp = await _client
                    .post(
                      uri,
                      headers: hdrs,
                      body: jsonEncode(env.jsonBody ?? {}),
                    )
                    .timeout(AppConfig.httpTimeout);
                break;
              case HttpVerb.put:
                resp = await _client
                    .put(
                      uri,
                      headers: hdrs,
                      body: jsonEncode(env.jsonBody ?? {}),
                    )
                    .timeout(AppConfig.httpTimeout);
                break;
              case HttpVerb.delete:
                resp = await _client
                    .delete(uri, headers: hdrs)
                    .timeout(AppConfig.httpTimeout);
                break;
              default:
                continue; // GET should not be in the write queue
            }
          }

          final preview = resp.body.length > 600
              ? '${resp.body.substring(0, 600)}…'
              : resp.body;
          _log('DEBUG', 'id=${env.id} HTTP ${resp.statusCode} body: $preview');

          // ─────────────────────────────────────────────────────────────────
          // Result classification
          // ─────────────────────────────────────────────────────────────────

          // ── 2xx Success ───────────────────────────────────────────────────
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            // Capture TripStart mapping
            try {
              if (env.path == AppConfig.trips ||
                  env.path.endsWith('/api/trips')) {
                final decoded = jsonDecode(resp.body);
                final serverId = decoded['data']?['_id'];
                final localId =
                    env.jsonBody?['__localTripId']?.toString() ??
                    env.jsonBody?['localTripId']?.toString() ??
                    '';

                if (serverId != null &&
                    serverId is String &&
                    localId.isNotEmpty) {
                  final map = await _readTripMapping();
                  map[localId] = serverId;
                  await _writeTripMapping(map);

                  try {
                    final prefs = await SharedPreferences.getInstance();
                    final curLocal = prefs.getString('currentTripLocalId');
                    if (curLocal == localId) {
                      await prefs.setString('currentTripId', serverId);
                    }
                  } catch (_) {}

                  _log('DEBUG', 'SyncService mapping: $localId -> $serverId');
                  await _remapQueuedItemsAfterStart(localId, serverId);

                  all = await _store.all();
                  env = all.firstWhere(
                    (e) => e.id == env.id,
                    orElse: () => env,
                  );
                }
              }
            } catch (e) {
              _log('WARN', 'mapping parse error: $e');
            }

            await _store.remove(env.id);
            _events.add(
              SyncEvent(
                id: env.id,
                success: true,
                statusCode: resp.statusCode,
                method: env.method.name.toUpperCase(),
                path: env.path,
              ),
            );
            _log('INFO', 'synced & removed id=${env.id}');
          }
          // ── 401 / 403 ─────────────────────────────────────────────────────
          else if (resp.statusCode == 401 ||
              (resp.statusCode == 403 && _isTripLifecyclePath(env.path))) {
            // Trip lifecycle paths get a backoff retry (token may refresh)
            if (_isTripLifecyclePath(env.path)) {
              final secs = _scheduleBackoff(
                env,
                reason: 'HTTP ${resp.statusCode} trip-auth',
              );
              await _store.update(env);
              _events.add(
                SyncEvent(
                  id: env.id,
                  success: false,
                  statusCode: resp.statusCode,
                  method: env.method.name.toUpperCase(),
                  path: env.path,
                  error: 'trip-auth-${resp.statusCode}',
                ),
              );
              _log(
                'WARN',
                'trip lifecycle HTTP ${resp.statusCode} → '
                    'backoff ${secs}s for id=${env.id}',
              );
              continue;
            }

            // Non-trip auth failure → persist as failed and stop flush
            // ── FAILED RECORD: auth failure ──────────────────────────────
            await _persistFailedRecord(
              env,
              statusCode: resp.statusCode,
              reason: FailureReason.authFailure,
              errorDetail: resp.statusCode == 401
                  ? 'Unauthorized'
                  : 'Forbidden',
            );
            // ────────────────────────────────────────────────────────────

            _events.add(
              SyncEvent(
                id: env.id,
                success: false,
                statusCode: resp.statusCode,
                method: env.method.name.toUpperCase(),
                path: env.path,
                error: resp.statusCode == 401 ? 'Unauthorized' : 'Forbidden',
              ),
            );
            _log(
              'ERROR',
              'HTTP ${resp.statusCode} auth failure → stopping flush',
            );
            break;
          }
          // ── 409 Conflict ──────────────────────────────────────────────────
          else if (resp.statusCode == 409) {
            // Treat as already-resolved; drop without recording as failure
            await _store.remove(env.id);
            _events.add(
              SyncEvent(
                id: env.id,
                success: true,
                statusCode: resp.statusCode,
                method: env.method.name.toUpperCase(),
                path: env.path,
              ),
            );
            _log('WARN', '409 Conflict → dropped id=${env.id}');
          }
          // ── 408 / 429 / 5xx — retryable ───────────────────────────────────
          else if (resp.statusCode == 408 ||
              resp.statusCode == 429 ||
              resp.statusCode >= 500) {
            if (env.attempt + 1 >= maxAttempts) {
              // ── FAILED RECORD: max attempts ─────────────────────────────
              await _persistFailedRecord(
                env,
                statusCode: resp.statusCode,
                reason: FailureReason.maxAttemptsReached,
                errorDetail:
                    'HTTP ${resp.statusCode} after $maxAttempts attempts',
              );
              // ────────────────────────────────────────────────────────────

              await _store.remove(env.id);
              _events.add(
                SyncEvent(
                  id: env.id,
                  success: false,
                  statusCode: resp.statusCode,
                  method: env.method.name.toUpperCase(),
                  path: env.path,
                  error: 'max-attempts-reached',
                ),
              );
              _log(
                'ERROR',
                'drop id=${env.id} after $maxAttempts attempts '
                    '(HTTP ${resp.statusCode})',
              );
            } else {
              final secs = _scheduleBackoff(
                env,
                reason: 'HTTP ${resp.statusCode}',
              );
              await _store.update(env);
              _events.add(
                SyncEvent(
                  id: env.id,
                  success: false,
                  statusCode: resp.statusCode,
                  method: env.method.name.toUpperCase(),
                  path: env.path,
                  error: 'HTTP ${resp.statusCode}',
                ),
              );
              _log(
                'WARN',
                'keep id=${env.id} (HTTP ${resp.statusCode}) '
                    'backoff ${secs}s',
              );
            }
          }
          // ── Permanent 4xx (400 / 404 / 422 / …) ──────────────────────────
          else {
            // ── FAILED RECORD: permanent client error ────────────────────
            await _persistFailedRecord(
              env,
              statusCode: resp.statusCode,
              reason: FailureReason.permanentClientError,
              errorDetail:
                  'HTTP ${resp.statusCode}: '
                  '${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}',
            );
            // ────────────────────────────────────────────────────────────

            await _store.remove(env.id);
            _events.add(
              SyncEvent(
                id: env.id,
                success: false,
                statusCode: resp.statusCode,
                method: env.method.name.toUpperCase(),
                path: env.path,
                error: 'permanent-4xx',
              ),
            );
            _log(
              'ERROR',
              'permanent ${resp.statusCode} → dropped id=${env.id}',
            );
          }
        }
        // ── SocketException: pure offline ─────────────────────────────────
        on SocketException catch (e) {
          _events.add(
            SyncEvent(
              id: env.id,
              success: false,
              statusCode: 0,
              method: env.method.name.toUpperCase(),
              path: env.path,
              error: 'SocketException: $e',
            ),
          );
          _log('WARN', 'SocketException → stop flush; retry on next tick');
          break;
        }
        // ── Timeout ───────────────────────────────────────────────────────
        on TimeoutException catch (e) {
          final secs = _scheduleBackoff(env, reason: 'timeout');
          await _store.update(env);
          _events.add(
            SyncEvent(
              id: env.id,
              success: false,
              statusCode: 0,
              method: env.method.name.toUpperCase(),
              path: env.path,
              error: 'Timeout: $e',
            ),
          );
          _log('WARN', 'timeout → backoff ${secs}s ($e)');
        }
        // ── Unexpected error ──────────────────────────────────────────────
        catch (e) {
          final secs = _scheduleBackoff(env, reason: 'error');
          await _store.update(env);
          _events.add(
            SyncEvent(
              id: env.id,
              success: false,
              statusCode: 0,
              method: env.method.name.toUpperCase(),
              path: env.path,
              error: e.toString(),
            ),
          );
          _log('ERROR', 'error → backoff ${secs}s ($e)');
        }
      }
    } finally {
      _running = false;
      _log('INFO', 'flush complete');
    }
  }

  // ── Internet check ─────────────────────────────────────────────────────────

  Future<bool> _hasInternet() async {
    try {
      final uri = Uri.parse('https://clients3.google.com/generate_204');
      final resp = await _client.get(uri).timeout(const Duration(seconds: 3));
      return resp.statusCode == 204 || resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Address enrichment ─────────────────────────────────────────────────────

  Future<void> _enrichAddressFromLocationIfNeeded(RequestEnvelope env) async {
    final body = env.jsonBody;
    if (body == null) return;

    const targets = [
      ('shopAddress', 'location'),
      ('startLocationName', 'startLocation'),
      ('endLocationName', 'endLocation'),
      ('address', 'location'),
    ];

    bool updated = false;

    bool needs(String v) {
      final s = v.trim().toLowerCase();
      return s.isEmpty ||
          s.contains('offline') ||
          s.contains('await') ||
          s.contains('unavailable');
    }

    String buildAddressFromPlacemark(Placemark p) {
      String joinNonEmpty(List<String?> xs) => xs
          .where((e) => e != null && e.trim().isNotEmpty)
          .map((e) => e!.trim())
          .join(', ');
      final address = joinNonEmpty([
        p.name,
        p.street,
        p.thoroughfare,
        p.subLocality,
        p.locality,
        p.subAdministrativeArea,
        p.administrativeArea,
        p.postalCode,
        p.country,
      ]);
      return address.isEmpty ? p.toString() : address;
    }

    Future<String?> reverseGeocodeWithGoogle(double lat, double lon) async {
      final key = AppConfig.googleMapsApiKey;
      if (key.trim().isEmpty) return null;

      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lon',
        'key': key,
        'language': 'en',
      });

      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) return null;
        final data = jsonDecode(resp.body);
        if (data == null) return null;
        final status = (data['status'] as String?)?.toLowerCase() ?? '';
        if (status != 'ok') return null;
        final results = (data['results'] as List?) ?? [];
        if (results.isEmpty) return null;
        final first = results.first as Map<String, dynamic>;
        final formatted = (first['formatted_address'] as String?)?.trim();
        if (formatted != null && formatted.isNotEmpty) return formatted;
        final comps = (first['address_components'] as List?) ?? [];
        final compMap = <String, String>{};
        for (final dynamic c in comps) {
          final comp = c as Map<String, dynamic>;
          final longName = (comp['long_name'] as String?)?.trim();
          final types = (comp['types'] as List?)?.cast<String>() ?? <String>[];
          if (longName == null) continue;
          for (final t in types) {
            compMap.putIfAbsent(t, () => longName);
          }
        }
        final parts = [
          compMap['premise'],
          compMap['subpremise'],
          compMap['street_number'],
          compMap['route'],
          compMap['neighborhood'],
          compMap['sublocality'],
          compMap['locality'],
          compMap['administrative_area_level_2'],
          compMap['administrative_area_level_1'],
          compMap['postal_code'],
          compMap['country'],
        ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
        return parts.isNotEmpty ? parts : null;
      } catch (e) {
        _log('WARN', 'Google geocode failed for $lat,$lon: $e');
        return null;
      }
    }

    for (final (addrKey, locKey) in targets) {
      final addr = (body[addrKey]?.toString().trim() ?? '');
      final loc = (body[locKey]?.toString().trim() ?? '');
      if (!needs(addr) || loc.isEmpty) continue;

      final parsed = extractLatLon(body[locKey]);
      if (parsed == null) continue;

      final lat = parsed['lat']!;
      final lon = parsed['lon']!;

      String? full;
      try {
        full = await reverseGeocodeWithGoogle(lat, lon);
      } catch (e) {
        _log('WARN', 'Google geocode threw for env=${env.id}: $e');
        full = null;
      }

      if (full == null) {
        try {
          final placemarks = await placemarkFromCoordinates(
            lat,
            lon,
          ).timeout(const Duration(seconds: 5));
          if (placemarks.isNotEmpty) {
            full = buildAddressFromPlacemark(placemarks.first);
          }
        } catch (e) {
          _log('WARN', 'Platform geocode failed for env=${env.id}: $e');
        }
      }

      if (full != null && full.trim().isNotEmpty) {
        body[addrKey] = full;
        updated = true;
      }
    }

    if (updated) {
      try {
        await _store.update(env);
      } catch (e) {
        _log('ERROR', 'Failed to persist enriched envelope id=${env.id}: $e');
      }
    }
  }

  Map<String, double>? extractLatLon(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final lat = double.tryParse(raw['latitude']?.toString() ?? '');
      final lon = double.tryParse(raw['longitude']?.toString() ?? '');
      if (lat != null && lon != null) return {'lat': lat, 'lon': lon};
    }
    if (raw is String) {
      final cleaned = raw
          .replaceAll(',', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final parts = cleaned.split(' ');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0]);
        final lon = double.tryParse(parts[1]);
        if (lat != null && lon != null) return {'lat': lat, 'lon': lon};
      }
    }
    return null;
  }

  // ── Trip mapping helpers ───────────────────────────────────────────────────

  Future<Map<String, String>> _readTripMapping() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('tripMapping_v1');
    if (s == null || s.isEmpty) return {};
    try {
      final m = Map<String, dynamic>.from(jsonDecode(s));
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeTripMapping(Map<String, String> m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tripMapping_v1', jsonEncode(m));
  }

  // ── Backoff scheduler ──────────────────────────────────────────────────────

  /// Exponential backoff: 2, 4, 8, 16, 32, 64, 64 seconds.
  int _scheduleBackoff(RequestEnvelope env, {String? reason}) {
    env.attempt += 1;
    final secs = (1 << (env.attempt.clamp(0, 6))) * 2;
    env.nextAttemptAt = DateTime.now().toUtc().add(Duration(seconds: secs));
    _log(
      'DEBUG',
      'backoff id=${env.id} +${secs}s '
          '(attempt=${env.attempt}${reason != null ? ', reason=$reason' : ''})',
    );
    return secs;
  }

  // ── Media type guesser ─────────────────────────────────────────────────────

  http_parser.MediaType? _guessMediaType(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return http_parser.MediaType('image', 'jpeg');
      case 'png':
        return http_parser.MediaType('image', 'png');
      case 'pdf':
        return http_parser.MediaType('application', 'pdf');
      case 'doc':
        return http_parser.MediaType('application', 'msword');
      case 'docx':
        return http_parser.MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      default:
        return http_parser.MediaType('application', 'octet-stream');
    }
  }
}
