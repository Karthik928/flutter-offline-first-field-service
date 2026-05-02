import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class ZonalTaskActionResponse {
  final bool success;
  final String? error;

  ZonalTaskActionResponse({required this.success, this.error});
}

class ZonalEditDeleteTaskService {
  final String baseUrl = AppConfig.apiBase;

  Future<ZonalTaskActionResponse> updateTask({
    required String taskId,
    required String title,
    required String type,
    required String priority,
    required String assignedTo,
    required String customerName,
    required String location,
    required String dueDate,
    required String description,
  }) async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalTaskActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      final response = await http.put(
        Uri.parse('$baseUrl/api/tasks/$taskId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'title': title,
          'type': type,
          'priority': priority,
          'assignedTo': assignedTo,
          "customerName": customerName.trim(),
          'location': location,
          'dueDate': dueDate,
          'description': description,
        }),
      );

      if (response.statusCode == 200) {
        return ZonalTaskActionResponse(success: true);
      }

      if (response.statusCode == 401) {
        return ZonalTaskActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalTaskActionResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalTaskActionResponse(success: false, error: e.toString());
    }
  }

  Future<ZonalTaskActionResponse> deleteTask(String taskId) async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return ZonalTaskActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/api/tasks/$taskId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return ZonalTaskActionResponse(success: true);
      }

      if (response.statusCode == 401) {
        return ZonalTaskActionResponse(success: false, error: 'UNAUTHORIZED');
      }

      return ZonalTaskActionResponse(
        success: false,
        error: 'Error ${response.statusCode}',
      );
    } catch (e) {
      return ZonalTaskActionResponse(success: false, error: e.toString());
    }
  }
}
