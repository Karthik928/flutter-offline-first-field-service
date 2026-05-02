import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalTasksResponse {
  final bool success;
  final List<dynamic>? data;
  final String? error;

  ZonalTasksResponse({required this.success, this.data, this.error});
}

class ZonalTasksService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalAllTasks;

  Future<ZonalTasksResponse> fetchTasks() async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalTasksResponse(success: false, error: 'UNAUTHORIZED');
      }

      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ZonalTasksResponse(success: true, data: jsonData['data']);
      }

      if (response.statusCode == 401) {
        return ZonalTasksResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalTasksResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalTasksResponse(success: false, error: e.toString());
    }
  }
}
