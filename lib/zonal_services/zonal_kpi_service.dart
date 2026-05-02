import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result model
// ─────────────────────────────────────────────────────────────────────────────

class ZonalKpiResult {
  final bool success;

  /// Yearly sales target (raw rupees).
  final double yearlyTarget;

  /// Revenue actually received so far.
  final double achievedRevenue;

  /// Percentage of target achieved (0–100+).
  final double achievedPercentage;

  /// Sales amount billed (may differ from received revenue).
  final double salesAmount;

  /// Non-null when the caller should force-logout the user.
  final bool forceLogout;

  /// Non-null on a recoverable error (network, parse, etc.).
  final String? error;

  const ZonalKpiResult({
    required this.success,
    this.yearlyTarget = 0,
    this.achievedRevenue = 0,
    this.achievedPercentage = 0,
    this.salesAmount = 0,
    this.forceLogout = false,
    this.error,
  });

  /// Convenience: progress fraction clamped to [0, 1] for a LinearProgressIndicator.
  double get progressFraction => (achievedPercentage / 100).clamp(0.0, 1.0);

  static const ZonalKpiResult empty = ZonalKpiResult(success: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class ZonalKpiService {
  static const String _cacheKey = 'zonal_dashboard:kpi';

  final http.Client _client;
  final bool _ownsClient;

  /// Pass an existing [http.Client] to share connections, or omit to create one.
  ZonalKpiService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;
    }
    return 0.0;
  }

  ZonalKpiResult _parse(Map<String, dynamic> body) {
    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) return ZonalKpiResult.empty;

    final salesObj = data['sales'] as Map<String, dynamic>?;
    final revenueObj = data['revenue'] as Map<String, dynamic>?;
    final targetObj = data['target'] as Map<String, dynamic>?;

    final salesAmount = _parseNum(salesObj?['salesAmount']);
    final achievedRevenue = _parseNum(revenueObj?['receivedAmount']);
    final yearlyTarget = _parseNum(targetObj?['yearlyTarget']);
    final achievedPercentage = _parseNum(targetObj?['achievedPercentage']);

    return ZonalKpiResult(
      success: true,
      yearlyTarget: yearlyTarget > 0 ? yearlyTarget : 100000,
      achievedRevenue: achievedRevenue,
      achievedPercentage: achievedPercentage,
      salesAmount: salesAmount,
    );
  }

  // ── public API ─────────────────────────────────────────────────────────────

  /// Fetches KPI data from the server.
  /// Falls back to cached data on network errors so the UI is never blank.
  Future<ZonalKpiResult> fetchKpi() async {
    final prefs = await SharedPreferences.getInstance();

    // Helper: return cached result if available, otherwise empty.
    ZonalKpiResult fromCache() {
      try {
        final cached = prefs.getString(_cacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          return _parse(decoded);
        }
      } catch (e) {
        debugPrint('[ZonalKpiService] cache parse error: $e');
      }
      return ZonalKpiResult.empty;
    }

    // ── token guard ──────────────────────────────────────────────────────────
    final token = await SecureStorageService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[ZonalKpiService] no token — using cache');
      return fromCache();
    }

    // ── network call ─────────────────────────────────────────────────────────
    try {
      final uri = AppConfig.u(AppConfig.reportsByToken);
      final response = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      // 401 → session expired
      if (response.statusCode == 401) {
        debugPrint('[ZonalKpiService] 401 — force logout');
        return const ZonalKpiResult(success: false, forceLogout: true);
      }

      // Non-2xx → fall back to cache silently
      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          '[ZonalKpiService] HTTP ${response.statusCode} — using cache',
        );
        return fromCache();
      }

      // ── parse + persist ──────────────────────────────────────────────────
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await prefs.setString(_cacheKey, response.body);
      return _parse(decoded);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ZonalKpiService] error: $e\n$st');
      // Network / timeout error → serve stale cache
      return fromCache();
    }
  }
}
