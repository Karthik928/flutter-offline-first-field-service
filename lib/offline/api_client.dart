// lib/offline/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // MediaType
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/offline/cache_store.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

import 'queue_store.dart';
import 'request_envelope.dart';

class CachedGetResult {
  final int statusCode;
  final dynamic data; // decoded JSON (Map/List) or null
  final bool fromCache;
  CachedGetResult({
    required this.statusCode,
    required this.data,
    required this.fromCache,
  });
}

class ApiClient {
  final http.Client _client;
  final QueueStore queue;
  final CacheStore? cache; // optional

  ApiClient(this._client, this.queue, {this.cache});

  Future<bool> _online({Duration timeout = const Duration(seconds: 4)}) async {
    if (kIsWeb) {
      // On web, socket APIs are not available — use an HTTP probe
      try {
        final resp = await _client
            .get(Uri.parse('https://clients3.google.com/generate_204'))
            .timeout(timeout);
        return resp.statusCode == 204 ||
            (resp.statusCode >= 200 && resp.statusCode < 400);
      } catch (e) {
        return false;
      }
    }

    // Non-web: try TCP connect to a public DNS server (fast)
    try {
      final socket = await Socket.connect('8.8.8.8', 53, timeout: timeout);
      socket.destroy();
      return true;
    } catch (e) {
      // fallback to HTTP probe (some networks block port 53)
      try {
        final resp = await _client
            .get(Uri.parse('https://clients3.google.com/generate_204'))
            .timeout(timeout);
        return resp.statusCode == 204 ||
            (resp.statusCode >= 200 && resp.statusCode < 400);
      } catch (e2) {
        // final fallback to example.com
        try {
          final r2 = await _client
              .get(Uri.parse('https://example.com'))
              .timeout(timeout);
          return r2.statusCode >= 200 && r2.statusCode < 400;
        } catch (e3) {
          return false;
        }
      }
    }
  }

  /// Call this from your code when debugging connectivity issues.
  /// It prints details (socket + HTTP) to debug logs and returns true/false.
  Future<bool> checkConnectivityDetailed({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // 1) Socket check to 8.8.8.8:53
    try {
      final s = await Socket.connect('8.8.8.8', 53, timeout: timeout);
      s.destroy();
      return true;
      // ignore: empty_catches
    } catch (e) {}

    // 2) HTTP check to google generate_204
    try {
      final resp = await _client
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(timeout);

      if (resp.statusCode == 204 ||
          (resp.statusCode >= 200 && resp.statusCode < 400)) {
        return true;
      }
    } catch (e, st) {
      debugPrint(
        '❌ [checkConnectivityDetailed] http generate_204 failed: $e\n$st',
      );
    }

    // 3) Final fallback: try a simple GET to example.com
    try {
      final resp = await _client
          .get(Uri.parse('https://example.com'))
          .timeout(timeout);
      debugPrint(
        'ℹ️ [checkConnectivityDetailed] http example.com status=${resp.statusCode}',
      );
      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        debugPrint('✅ [checkConnectivityDetailed] http -> OK (example.com)');
        return true;
      }
    } catch (e) {
      debugPrint('❌ [checkConnectivityDetailed] http example.com failed: ');
    }

    debugPrint('🔻 [checkConnectivityDetailed] All checks failed → offline');
    return false;
  }

  Future<Map<String, String>> _authHeaders([Map<String, String>? extra]) async {
    //final prefs = await SharedPreferences.getInstance();
    // prefer 'authToken'; fall back to older 'token'
    // final token =
    //     prefs.getString('authToken') ?? prefs.getString('token') ?? '';
    final token = await SecureStorageService.getToken();
    final base = <String, String>{
      'Accept': 'application/json',
      if (token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    if (extra != null) base.addAll(extra);
    return base;
  }

  // ---------- GET (no cache) ----------
  Future<http.Response> getRaw(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? query,
  }) async {
    final uri = AppConfig.uri(path, query);
    final hdrs = await _authHeaders(headers);
    debugPrint('🌍 [ApiClient] GET $uri');
    return _client.get(uri, headers: hdrs).timeout(AppConfig.httpTimeout);
  }

  // ---------- GET (with small cache) ----------
  Future<CachedGetResult> getJsonCached({
    required String path,
    Map<String, String>? query,
    Map<String, String>? headers,
    required String cacheKey,
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final uri = AppConfig.uri(path, query);
    final hdrs = await _authHeaders(headers);

    // 1) Try cache first
    final entry = cache?.get(cacheKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh =
        entry != null && (now - entry.storedAtMillis <= ttl.inMilliseconds);

    if (fresh) {
      // kick a silent refresh
      () async {
        try {
          final resp = await _client
              .get(uri, headers: hdrs)
              .timeout(AppConfig.httpTimeout);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            await cache?.put(
              cacheKey,
              CacheEntry(
                body: resp.body,
                storedAtMillis: DateTime.now().millisecondsSinceEpoch,
                statusCode: resp.statusCode,
              ),
            );
            debugPrint(
              '🔄 [GETCACHE] refreshed "$cacheKey" (${resp.statusCode})',
            );
          } else {
            debugPrint(
              '⚠️ [GETCACHE] refresh failed "$cacheKey" ${resp.statusCode}',
            );
          }
        } catch (e) {
          debugPrint('⚠️ [GETCACHE] refresh error "$cacheKey": $e');
        }
      }();

      final decoded = entry.body.isNotEmpty ? jsonDecode(entry.body) : null;
      debugPrint('🟢 [GETCACHE] serve FRESH cache "$cacheKey"');
      return CachedGetResult(
        statusCode: entry.statusCode,
        data: decoded,
        fromCache: true,
      );
    }

    // 2) Try network
    try {
      debugPrint('🌍 [ApiClient] GET $uri (cacheKey=$cacheKey)');
      final resp = await _client
          .get(uri, headers: hdrs)
          .timeout(AppConfig.httpTimeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await cache?.put(
          cacheKey,
          CacheEntry(
            body: resp.body,
            storedAtMillis: DateTime.now().millisecondsSinceEpoch,
            statusCode: resp.statusCode,
          ),
        );
        final decoded = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        debugPrint('🟢 [GETCACHE] network OK "$cacheKey"');
        return CachedGetResult(
          statusCode: resp.statusCode,
          data: decoded,
          fromCache: false,
        );
      }

      // network not 2xx → stale cache fallback
      if (entry != null) {
        final decoded = entry.body.isNotEmpty ? jsonDecode(entry.body) : null;
        debugPrint(
          '🟡 [GETCACHE] network ${resp.statusCode} → STALE cache "$cacheKey"',
        );
        return CachedGetResult(
          statusCode: resp.statusCode,
          data: decoded,
          fromCache: true,
        );
      }

      debugPrint(
        '🔴 [GETCACHE] network ${resp.statusCode} and NO cache "$cacheKey"',
      );
      return CachedGetResult(
        statusCode: resp.statusCode,
        data: null,
        fromCache: false,
      );
    } catch (e) {
      // error/offline → stale cache if exists
      if (entry != null) {
        final decoded = entry.body.isNotEmpty ? jsonDecode(entry.body) : null;
        debugPrint('🟡 [GETCACHE] error ($e) → STALE cache "$cacheKey"');
        return CachedGetResult(
          statusCode: entry.statusCode,
          data: decoded,
          fromCache: true,
        );
      }
      debugPrint('🔴 [GETCACHE] error ($e) and NO cache "$cacheKey"');
      return CachedGetResult(statusCode: 0, data: null, fromCache: false);
    }
  }

  bool _isRetriable(int code) =>
      code == 0 || code == 408 || code == 429 || code >= 500;

  bool _isTripLifecyclePath(String path) =>
      path == AppConfig.trips || path.startsWith('/api/trips');

  bool _shouldQueueFailedWrite(String path, int statusCode) {
    if (_isRetriable(statusCode)) return true;

    // Trip start/end must not be dropped on immediate auth/permission failures.
    // Keep them in the offline queue so they can be retried after auth/state recovers.
    return _isTripLifecyclePath(path) &&
        (statusCode == 401 || statusCode == 403);
  }

  // ---------- Write APIs: POST/PUT/DELETE (online or queue) ----------
  Future<http.Response?> sendOrQueue({
    required HttpVerb method,
    required String path,
    Map<String, String>? headers,
    Map<String, dynamic>? jsonBody,
    List<QueuedFile>? files, // multipart support
    Map<String, String>? query,
    bool optimisticOk = true, // allow callers to treat as success if queued
  }) async {
    final hdrs = await _authHeaders(headers);

    // --- PATCH START: resolve localTripId using mapping (correct behaviour) ---
    String resolvedPath = path;
    final localTripId = jsonBody?['localTripId']?.toString();

    if (localTripId != null && localTripId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final mapRaw = prefs.getString('tripMapping_v1') ?? '{}';
        final Map<String, dynamic> mapping = jsonDecode(mapRaw);
        final mappedServerId = mapping[localTripId]?.toString();

        if (mappedServerId != null && mappedServerId.isNotEmpty) {
          // mapping exists → replace path and body
          resolvedPath = resolvedPath.replaceAll(localTripId, mappedServerId);
          resolvedPath = resolvedPath.replaceAll('{id}', mappedServerId);
          resolvedPath = resolvedPath.replaceAll(
            '{localTripId}',
            mappedServerId,
          );

          // Preserve original local ID for SyncService
          if (jsonBody != null && jsonBody.containsKey('localTripId')) {
            jsonBody['__localTripId'] = jsonBody['localTripId'];
          }

          // deep replace inside JSON body
          void deepReplace(Map m) {
            m.forEach((k, v) {
              if (v is String && v == localTripId && k != 'localTripId') {
                m[k] = mappedServerId;
              } else if (v is Map) {
                deepReplace(v);
              } else if (v is List) {
                for (var i = 0; i < v.length; i++) {
                  if (v[i] is String && v[i] == localTripId) {
                    v[i] = mappedServerId;
                  } else if (v[i] is Map) {
                    deepReplace(v[i]);
                  }
                }
              }
            });
          }

          if (jsonBody != null) deepReplace(jsonBody);
          debugPrint(
            "🔁 [ApiClient] resolved $localTripId → $mappedServerId (path=$resolvedPath)",
          );
        } else {
          // mapping NOT yet available
          final defer = jsonBody?['__deferUntilMapped'] == true;
          if (defer) {
            // → ALWAYS queue when mapping missing
            final env = RequestEnvelope(
              id: const Uuid().v4(),
              method: method,
              path: resolvedPath,
              headers: hdrs,
              jsonBody: jsonBody,
              files: files,
              authTokenSnapshot:
                  hdrs['Authorization']?.replaceFirst('Bearer ', '') ?? '',
            );

            debugPrint(
              "🟡 [ApiClient] mapping missing for $localTripId → queued id=${env.id}",
            );
            await queue.add(env);
            return null;
          }
          // If not deferred, we let it fall through and send normally
        }
      } catch (e, st) {
        debugPrint("⚠️ [ApiClient] mapping-resolve error: $e\n$st");
      }
    }
    // --- PATCH END ---

    final env = RequestEnvelope(
      id: const Uuid().v4(),
      method: method,
      path:
          resolvedPath, // keep plain path; SyncService will resolve uri() later
      headers: hdrs,
      jsonBody: jsonBody,
      files: files,
      authTokenSnapshot:
          hdrs['Authorization']?.replaceFirst('Bearer ', '') ?? '',
    );

    final online = await _online();
    debugPrint('🔎 [ApiClient] _online() => $online');
    if (!online) {
      debugPrint(
        '🟡 [ApiClient] going to queue (offline) id=${env.id} path=${env.path}',
      );
      await queue.add(env);
      return null;
    }

    // --- Attempt request immediately. Avoid TOCTOU by not relying only on _online() ---
    final uri = AppConfig.uri(resolvedPath, query);
    try {
      debugPrint(
        '🌍 [ApiClient] attempting ${method.name} $uri (id=${env.id})',
      );

      if (files != null && files.isNotEmpty) {
        final req = http.MultipartRequest(
          method == HttpVerb.post ? 'POST' : 'PUT',
          uri,
        )..headers.addAll(hdrs);

        // fields (JSON-encode non-strings)
        jsonBody?.forEach((k, v) {
          req.fields[k] = (v is String) ? v : jsonEncode(v);
        });

        // files
        for (final f in files) {
          final mt = (f.contentType.isNotEmpty)
              ? MediaType.parse(f.contentType)
              : null;
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
        final resp = await http.Response.fromStream(streamed);

        debugPrint(
          '🌍 [ApiClient] multipart response ${resp.statusCode} for id=${env.id}',
        );

        if (_shouldQueueFailedWrite(env.path, resp.statusCode)) {
          await queue.add(env);
          debugPrint(
            '🟠 [ApiClient] retriable ${resp.statusCode} → queued ${method.name} ${env.path} id=${env.id} body=${_safeSnip(resp.body)}',
          );
          return null;
        }

        return resp;
      } else {
        late http.Response resp;
        final jsonHeaders = {...hdrs, 'Content-Type': 'application/json'};

        switch (method) {
          case HttpVerb.post:
            resp = await _client
                .post(
                  uri,
                  headers: jsonHeaders,
                  body: jsonEncode(jsonBody ?? {}),
                )
                .timeout(AppConfig.httpTimeout);
            break;
          case HttpVerb.put:
            resp = await _client
                .put(
                  uri,
                  headers: jsonHeaders,
                  body: jsonEncode(jsonBody ?? {}),
                )
                .timeout(AppConfig.httpTimeout);
            break;
          case HttpVerb.delete:
            resp = await _client
                .delete(uri, headers: jsonHeaders)
                .timeout(AppConfig.httpTimeout);
            break;
          default:
            throw UnsupportedError(
              'GET should use getRaw() or getJsonCached()',
            );
        }

        debugPrint(
          '🌍 [ApiClient] response ${resp.statusCode} for id=${env.id}',
        );

        if (_shouldQueueFailedWrite(env.path, resp.statusCode)) {
          await queue.add(env);
          debugPrint(
            '🟠 [ApiClient] retriable ${resp.statusCode} → queued ${method.name} ${env.path} id=${env.id} body=${_safeSnip(resp.body)}',
          );
          return null;
        }

        return resp;
      }
    } on SocketException catch (e, st) {
      debugPrint("💥 FINAL ERROR: $e");
      debugPrint("📛 STACK: $st");
      // real network error → queue
      await queue.add(env);
      debugPrint(
        '🟠 [ApiClient] SocketException → queued id=${env.id} path=${env.path} error=$e\n$st',
      );
      return null;
    } on TimeoutException catch (e, st) {
      // timed out waiting for response → queue
      await queue.add(env);
      debugPrint(
        '🟠 [ApiClient] TimeoutException → queued id=${env.id} path=${env.path} error=$e\n$st',
      );
      return null;
    } catch (e, st) {
      // Any other exception (including file errors for multipart)
      await queue.add(env);
      debugPrint(
        '🟠 [ApiClient] exception (${e.runtimeType}) → queued id=${env.id} path=${env.path} error=$e\n$st',
      );
      return null;
    }
  }

  // small helper to avoid spamming logs with huge bodies
  String _safeSnip(String? s, [int limit = 300]) {
    if (s == null || s.isEmpty) return '';
    if (s.length <= limit) return s;
    return '${s.substring(0, limit)}...[${s.length} bytes]';
  }
}
