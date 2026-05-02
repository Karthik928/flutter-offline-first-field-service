import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Response Models
// ─────────────────────────────────────────────────────────────────────────────

class ZonalOrdersResponse {
  final bool success;
  final OrdersSummary? summary;
  final List<OrderData> orders;
  final String? error;

  ZonalOrdersResponse({
    required this.success,
    required this.orders,
    this.summary,
    this.error,
  });
}

class OrderActionResponse {
  final bool success;
  final String? message;
  final String? error;

  OrderActionResponse({required this.success, this.message, this.error});
}

class OrdersSummary {
  final num totalAmount;
  final int totalOrders;

  OrdersSummary({required this.totalAmount, required this.totalOrders});

  factory OrdersSummary.fromJson(Map<String, dynamic> json) {
    return OrdersSummary(
      totalAmount: json['totalAmount'] ?? 0,
      totalOrders: json['totalOrders'] ?? 0,
    );
  }
}

class OrderData {
  final String orderId;
  final String customer;
  final String type;
  final String employee;
  final num amount;
  final num paidAmount;
  final num outstanding;
  final String status;
  final DateTime date;

  OrderData({
    required this.orderId,
    required this.customer,
    required this.type,
    required this.employee,
    required this.amount,
    required this.paidAmount,
    required this.outstanding,
    required this.status,
    required this.date,
  });

  factory OrderData.fromJson(Map<String, dynamic> json) {
    return OrderData(
      orderId: json['orderId']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      employee: json['employee']?.toString() ?? '',
      amount: json['amount'] ?? 0,
      paidAmount: json['paidAmount'] ?? 0,
      outstanding: json['outstanding'] ?? 0,
      status: json['status']?.toString() ?? 'Pending',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFF1AB69C);
      case 'partially delivered':
        return const Color(0xFFF59E0B);
      case 'pending':
        return const Color(0xFF4D8AF0);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  String get dateLabel {
    final d = date;
    return '${d.day.toString().padLeft(2, '0')} ${_monthName(d.month)}, ${d.year}';
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class ZonalOrdersService {
  final String _baseUrl = AppConfig.apiBase;
  static const String _listEndpoint = AppConfig.zonalAllOrders;

  // ── Shared: build auth headers ─────────────────────────────────────────────
  Future<Map<String, String>?> _authHeaders() async {
    final token = await SecureStorageService.getToken();
    if (token == null || token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  // ── Shared: parse error message from response body ─────────────────────────
  String _parseErrorMessage(String rawBody, int statusCode) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded['message']?.toString() ??
            decoded['error']?.toString() ??
            'Error $statusCode';
      }
    } catch (_) {}
    return 'Error $statusCode';
  }

  // ── Fetch all orders ───────────────────────────────────────────────────────
  Future<ZonalOrdersResponse> fetchOrders({String? employeeId}) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return ZonalOrdersResponse(
          success: false,
          orders: [],
          error: 'UNAUTHORIZED',
        );
      }

      final uri = Uri.parse('$_baseUrl$_listEndpoint').replace(
        queryParameters: (employeeId != null && employeeId.isNotEmpty)
            ? {'employeeId': employeeId}
            : null,
      );

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      final rawBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 401) {
        return ZonalOrdersResponse(
          success: false,
          orders: [],
          error: 'UNAUTHORIZED',
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
        final summaryJson = decoded['summary'] as Map<String, dynamic>?;
        final list = (decoded['data'] as List? ?? [])
            .map((e) => OrderData.fromJson(e as Map<String, dynamic>))
            .toList();

        return ZonalOrdersResponse(
          success: true,
          summary: summaryJson != null
              ? OrdersSummary.fromJson(summaryJson)
              : null,
          orders: list,
        );
      }

      return ZonalOrdersResponse(
        success: false,
        orders: [],
        error: _parseErrorMessage(rawBody, response.statusCode),
      );
    } catch (e) {
      return ZonalOrdersResponse(
        success: false,
        orders: [],
        error: 'Network error. Please try again.',
      );
    }
  }

  // ── Approve an order ───────────────────────────────────────────────────────
  /// PUT {{baseUrl}}/api/zonal-data/orders/{orderId}/approve
  Future<OrderActionResponse> approveOrder(String orderId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return OrderActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      // Build URL by replacing {orderId} placeholder then appending /approve
      final endpoint = AppConfig.zonalOrdersUpdate.replaceAll(
        '{orderId}',
        orderId,
      );
      final uri = Uri.parse('$_baseUrl$endpoint/approve');

      final response = await http
          .put(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      final rawBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 401) {
        return OrderActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String? message;
        try {
          final decoded = jsonDecode(rawBody);
          if (decoded is Map<String, dynamic>) {
            message = decoded['message']?.toString();
          }
        } catch (_) {}
        return OrderActionResponse(
          success: true,
          message: message ?? 'Order approved successfully.',
        );
      }

      return OrderActionResponse(
        success: false,
        error: _parseErrorMessage(rawBody, response.statusCode),
      );
    } catch (e) {
      return OrderActionResponse(
        success: false,
        error: 'Network error. Please try again.',
      );
    }
  }

  // ── Reject an order ────────────────────────────────────────────────────────
  /// PUT {{baseUrl}}/api/zonal-data/orders/{orderId}/reject
  /// Body: { "reason": `"<string>"` }
  Future<OrderActionResponse> rejectOrder(
    String orderId, {
    required String reason,
  }) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) {
        return OrderActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      final endpoint = AppConfig.zonalOrdersUpdate.replaceAll(
        '{orderId}',
        orderId,
      );
      final uri = Uri.parse('$_baseUrl$endpoint/reject');

      final response = await http
          .put(
            uri,
            headers: headers,
            body: jsonEncode({'reason': reason.trim()}),
          )
          .timeout(const Duration(seconds: 30));

      final rawBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 401) {
        return OrderActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String? message;
        try {
          final decoded = jsonDecode(rawBody);
          if (decoded is Map<String, dynamic>) {
            message = decoded['message']?.toString();
          }
        } catch (_) {}
        return OrderActionResponse(
          success: true,
          message: message ?? 'Order rejected successfully.',
        );
      }

      return OrderActionResponse(
        success: false,
        error: _parseErrorMessage(rawBody, response.statusCode),
      );
    } catch (e) {
      return OrderActionResponse(
        success: false,
        error: 'Network error. Please try again.',
      );
    }
  }

  // ── Fetch single order by ID ───────────────────────────────────────────────
  Future<Map<String, dynamic>?> fetchOrderById(String orderId) async {
    try {
      final headers = await _authHeaders();
      if (headers == null) return null;

      final response = await http
          .get(Uri.parse('$_baseUrl/api/order/$orderId'), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['order'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
