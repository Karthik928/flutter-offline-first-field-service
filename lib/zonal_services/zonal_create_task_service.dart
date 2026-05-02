import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class CreateTaskResponse {
  final bool success;
  final String? error;

  CreateTaskResponse({required this.success, this.error});
}

class ZonalCreateTaskService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.zonalCreateTasks;

  Future<CreateTaskResponse> createTask({
    required String title,
    required String type,
    required String priority,
    required String assignedTo,
    required String location,
    required String customerName, // 👈 ADD

    required String dueDate,
    required String description,
  }) async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return CreateTaskResponse(success: false, error: 'UNAUTHORIZED');
      }

      final body = {
        "title": title.trim(),
        "type": type.trim(),
        "priority": priority.trim(),
        "assignedTo": assignedTo.trim(),
        "location": location.trim(),
        "customerName": customerName.trim(), // 👈 ADD
        "dueDate": dueDate.trim(),
        "description": description.trim(),
      };

      debugPrint('CREATE TASK URL  => $baseUrl$endpoint');
      debugPrint('CREATE TASK BODY => $body');
      debugPrint('TOKEN PRESENT    => ${token.isNotEmpty}');

      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      final rawBody = utf8.decode(response.bodyBytes);

      debugPrint('CREATE TASK STATUS => ${response.statusCode}');
      debugPrint('CREATE TASK RESP   => $rawBody');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return CreateTaskResponse(success: true);
      }

      if (response.statusCode == 401) {
        return CreateTaskResponse(success: false, error: 'UNAUTHORIZED');
      }

      String errorMsg = 'Error ${response.statusCode}';

      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map<String, dynamic>) {
          errorMsg =
              decoded['message']?.toString() ??
              decoded['error']?.toString() ??
              errorMsg;
        } else if (rawBody.isNotEmpty) {
          errorMsg = rawBody;
        }
      } catch (_) {
        if (rawBody.isNotEmpty) {
          errorMsg = rawBody;
        }
      }

      return CreateTaskResponse(success: false, error: errorMsg);
    } catch (e) {
      return CreateTaskResponse(success: false, error: e.toString());
    }
  }
}
