import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/main.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String dealerName;
  final String shopName;
  final num amount;
  final String mobile;
  final String fcmToken;
  final DateTime sendAt;
  final bool sent;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.dealerName,
    required this.shopName,
    required this.amount,
    required this.mobile,
    required this.fcmToken,
    required this.sendAt,
    required this.sent,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    return AppNotification(
      id: (j['_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      dealerName: (j['dealerName'] ?? '').toString(),
      shopName: (j['shopName'] ?? '').toString(),
      amount: (j['amount'] ?? 0) as num,
      mobile: (j['mobile'] ?? '').toString(),
      fcmToken: (j['fcmToken'] ?? '').toString(),
      sendAt:
          DateTime.tryParse((j['sendAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sent: j['sent'] == true,
      createdAt:
          DateTime.tryParse((j['createdAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
    );
  }
}

class NotificationsService {
  /// Notifier that publishes the current unread count (best-effort).
  static final ValueNotifier<int> unreadNotifier = ValueNotifier<int>(0);

  /// Fetch all scheduled and sent notifications for the logged-in employee.
  static Future<List<AppNotification>> fetchAll() async {
    final prefs = await SharedPreferences.getInstance();
    final employeeId = (prefs.getString('userId') ?? '').trim();
    if (employeeId.isEmpty) return <AppNotification>[];

    final path = AppConfig.fill('/api/notifications/employee/{id}', {
      'id': employeeId,
    });
    final cacheKey = 'notifs:$employeeId';

    debugPrint('🌍 [Notif] GET $path (cacheKey=$cacheKey)');
    final result = await apiClient.getJsonCached(
      path: path,
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 3),
    );

    debugPrint(
      '↩️ [Notif] code=${result.statusCode} fromCache=${result.fromCache}',
    );

    final root = result.data;
    final listJson = (root is Map ? (root['data'] as List?) : null) ?? const [];

    final list = listJson
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();

    // Sort: reminders (unsent) first, then sent (latest first)
    list.sort((a, b) {
      if (a.sent != b.sent) return a.sent ? 1 : -1;
      if (!a.sent && !b.sent) return a.sendAt.compareTo(b.sendAt);
      return b.sendAt.compareTo(a.sendAt);
    });

    // Compute and publish unread count (best-effort)
    try {
      final lastSeen = await getLastSeen();
      final unread = list.where((n) => n.sent && n.createdAt.toUtc().isAfter(lastSeen.toUtc())).length;
      unreadNotifier.value = unread;
    } catch (_) {}

    return list;
  }

  /// Get the last time the user viewed/cleared notifications.
  static Future<DateTime> getLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('notifs:lastSeen') ?? '';
    if (v.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(v)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Set the last seen time for notifications (use UTC).
  static Future<void> setLastSeen(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notifs:lastSeen', dt.toUtc().toIso8601String());
    // publish a 0 unread count after marking seen
    try {
      unreadNotifier.value = 0;
    } catch (_) {}
  }
}

