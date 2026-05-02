import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalDashboardResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  ZonalDashboardResponse({required this.success, this.data, this.error});
}

class ZonalDashboardService {
  final String baseUrl = AppConfig.apiBase; // Replace with your actual base URL
  static const String endpoint = AppConfig.zonalDashboard;

  Future<ZonalDashboardResponse> fetchDashboard() async {
    try {
      final token = await SecureStorageService.getToken();

      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ZonalDashboardResponse(success: true, data: jsonData['data']);
      }

      if (response.statusCode == 401) {
        return ZonalDashboardResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalDashboardResponse(
        success: false,
        error: 'Something went wrong',
      );
    } catch (e) {
      return ZonalDashboardResponse(success: false, error: '__NO_INTERNET__');
    }
  }
}
