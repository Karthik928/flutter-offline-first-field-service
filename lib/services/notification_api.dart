import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/main.dart';
import 'package:FieldService_app/offline/request_envelope.dart';

class NotificationsApi {
  /// Schedule a server-side push notification.
  /// `sendAtUtc` must be an ISO-8601 UTC string, e.g. "2025-11-09T06:50:00.000Z".
  static Future<ScheduleResult> schedule({
    required String title,
    required String dealerId, // NEW
    required String dealerName,
    required String shopName,
    required num amount,
    required String mobile,
    required String body,
    required String fcmToken,
    required String sendAtUtc,
    String? tripId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = (prefs.getString('userId') ?? '').trim();
      final companyId = (prefs.getString('companyId') ?? '').trim();

      if (employeeId.isEmpty || companyId.isEmpty) {
        return ScheduleResult(
          success: false,
          message: 'Missing employee/company id. Please re-login.',
          id: '',
        );
      }

      // Normalize sendAt to UTC ISO-8601 with trailing 'Z'
      String normalizedSendAt;
      try {
        final dt = DateTime.parse(sendAtUtc);
        normalizedSendAt = dt.toUtc().toIso8601String();
      } catch (_) {
        // If parse fails, fallback to original (server may still accept)
        normalizedSendAt = sendAtUtc.endsWith('Z') ? sendAtUtc : sendAtUtc;
      }

      final Map<String, dynamic> payload = {
        "employeeId": employeeId,
        "companyId": companyId,
        "dealerId": dealerId, // NEW
        if (tripId != null && tripId.trim().isNotEmpty) "tripId": tripId.trim(),
        "title": title,
        "dealerName": dealerName,
        "shopName": shopName,
        "amount": amount,
        "mobile": mobile,
        "body": body,
        "fcmToken": fcmToken,
        "sendAt": normalizedSendAt,
      };

      final resp = await apiClient.sendOrQueue(
        method: HttpVerb.post,
        path: '/api/notifications/schedule',
        jsonBody: payload,
        // optimisticOk: true (default) → returns null when queued
      );

      // If null ⇒ request was queued (offline/retriable). Treat as success for UX.
      if (resp == null) {
        return ScheduleResult(
          success: true,
          message: 'Queued offline — will sync automatically',
          id: '',
        );
      }

      // Server responded immediately
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body);
        final success = json['success'] == true;
        final message = (json['message'] ?? '').toString();
        final id = ((json['notification'] ?? {})['_id'] ?? '').toString();
        return ScheduleResult(success: success, message: message, id: id);
      }

      return ScheduleResult(
        success: false,
        message:
            'Server error: ${resp.statusCode}'
            '${resp.body.isNotEmpty ? " | ${resp.body}" : ""}',
        id: '',
      );
    } catch (e) {
      return ScheduleResult(
        success: false,
        message: 'Network/queue error: $e',
        id: '',
      );
    }
  }
}

class ScheduleResult {
  final bool success;
  final String message;
  final String id;

  ScheduleResult({
    required this.success,
    required this.message,
    required this.id,
  });
}
