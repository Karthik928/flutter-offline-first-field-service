// lib/services/connectivity_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';

class ConnectivityService {
  static Future<bool> hasTransport() async {
    final c = await Connectivity().checkConnectivity();
    return !c.contains(ConnectivityResult.none);
  }

  /// Very short ping to your API to confirm internet reachability.
  static Future<bool> canReachApi() async {
    final candidates = [
      AppConfig.uri('/healthz'),
      AppConfig.uri('/'),
    ];
    for (final u in candidates) {
      try {
        final r = await http.get(u).timeout(const Duration(seconds: 3));
        if (r.statusCode >= 200 && r.statusCode < 500) return true;
      } catch (_) {}
    }
    return false;
  }
}
