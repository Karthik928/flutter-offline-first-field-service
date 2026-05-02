import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class UpdateTaskResponse {
  final bool success;
  final String? error;
  final Map<String, dynamic>? data;

  UpdateTaskResponse({required this.success, this.error, this.data});
}

class UpdateTaskService {
  final String baseUrl = AppConfig.apiBase;

  /// PATCH /api/tasks/{task_id}/status
  /// Form-data: status (Text), description (Text), image (File, optional)
  Future<UpdateTaskResponse> updateTaskStatus({
    required String taskId,
    required String status,
    required String description,
    File? imageFile,
  }) async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return UpdateTaskResponse(success: false, error: 'UNAUTHORIZED');
      }

      final endpoint = AppConfig.updatingTasks.replaceAll('{task_id}', taskId);

      final uri = Uri.parse('$baseUrl$endpoint');

      final request = http.MultipartRequest('PATCH', uri);

      // ── Headers ──────────────────────────────────────────
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      // ── Form fields ───────────────────────────────────────
      request.fields['status'] = status;
      request.fields['description'] = description;

      // ── Optional image ────────────────────────────────────
      if (imageFile != null) {
        final mimeType = _mimeTypeFromPath(imageFile.path);

        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: mimeType,
          ),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      final responseBody = await streamedResponse.stream.bytesToString();
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

      if (streamedResponse.statusCode == 401) {
        return UpdateTaskResponse(success: false, error: 'UNAUTHORIZED');
      }

      if (streamedResponse.statusCode >= 200 &&
          streamedResponse.statusCode < 300) {
        return UpdateTaskResponse(
          success: true,
          data: decoded['data'] as Map<String, dynamic>?,
        );
      }

      final message = decoded['message']?.toString() ?? 'Failed to update task';
      return UpdateTaskResponse(success: false, error: message);
    } catch (e) {
      return UpdateTaskResponse(success: false, error: e.toString());
    }
  }

  /// Derive a basic MediaType from file extension.
  http.MediaType _mimeTypeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return http.MediaType('image', 'jpeg');
      case 'png':
        return http.MediaType('image', 'png');
      case 'gif':
        return http.MediaType('image', 'gif');
      case 'webp':
        return http.MediaType('image', 'webp');
      default:
        return http.MediaType('application', 'octet-stream');
    }
  }
}
