import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:FieldService_app/config.dart';
import 'package:FieldService_app/services/secure_storage_service.dart';

class TasksResponse {
  final bool success;
  final List<TaskItem> tasks;
  final String? error;

  TasksResponse({required this.success, required this.tasks, this.error});
}

class TaskItem {
  final String id;
  final String title;
  final String type;
  final String priority;
  final String assignedToId;
  final String assignedToName;
  final String? assignedByName; // ← NEW
  final String? roleAssignedBy; // ← NEW
  final String location;
  final double? latitude; // ← NEW
  final double? longitude; // ← NEW
  final DateTime dueDate;
  final String description;
  final String status;
  final String? referenceId;
  final String? referenceType;
  final String? updateDescription; // ← NEW  (completion note)
  final String? updateImage; // ← NEW  (completion photo path)

  TaskItem({
    required this.id,
    required this.title,
    required this.type,
    required this.priority,
    required this.assignedToId,
    required this.assignedToName,
    this.assignedByName,
    this.roleAssignedBy,
    required this.location,
    this.latitude,
    this.longitude,
    required this.dueDate,
    required this.description,
    required this.status,
    this.referenceId,
    this.referenceType,
    this.updateDescription,
    this.updateImage,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final assignedTo = json['assignedTo'];
    final assignedBy = json['assignedBy'];

    final String? byFirstName = assignedBy?['firstName']?.toString();
    final String? byLastName = assignedBy?['lastName']?.toString();
    final String? byFullName = (byFirstName != null || byLastName != null)
        ? '${byFirstName ?? ''} ${byLastName ?? ''}'.trim()
        : null;

    return TaskItem(
      id: json['_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      priority: json['priority']?.toString() ?? '',
      assignedToId: assignedTo?['_id']?.toString() ?? '',
      assignedToName:
          '${assignedTo?['firstName'] ?? ''} ${assignedTo?['lastName'] ?? ''}'
              .trim(),
      assignedByName: byFullName,
      roleAssignedBy: json['roleAssignedBy']?.toString(),
      location: json['location']?.toString() ?? '',
      latitude: (json['latitude'] != null)
          ? double.tryParse(json['latitude'].toString())
          : null,
      longitude: (json['longitude'] != null)
          ? double.tryParse(json['longitude'].toString())
          : null,

      dueDate:
          DateTime.tryParse(json['dueDate']?.toString() ?? '') ??
          DateTime.now(),
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      referenceId: json['referenceId']?.toString(),
      referenceType: json['referenceType']?.toString(),
      updateDescription: json['updateDescription']?.toString(),
      updateImage: json['updateImage']?.toString(),
    );
  }

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isCompleted => status.toLowerCase() == 'completed';

  String get dueDateLabel {
    final d = dueDate;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Color get priorityColor {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF1AB69C);
      default:
        return Colors.grey;
    }
  }
}

class AllTasksService {
  final String baseUrl = AppConfig.apiBase;
  static const String endpoint = AppConfig.allPendingTasks;

  Future<TasksResponse> fetchAllTasks() async {
    try {
      final token = await SecureStorageService.getToken();

      if (token == null || token.isEmpty) {
        return TasksResponse(success: false, tasks: [], error: 'UNAUTHORIZED');
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      // 🔥 CALL BOTH APIs IN PARALLEL
      final responses = await Future.wait([
        http.get(
          Uri.parse('$baseUrl${AppConfig.allPendingTasks}'),
          headers: headers,
        ),
        http.get(
          Uri.parse('$baseUrl${AppConfig.allCompletedTasks}'),
          headers: headers,
        ),
      ]);

      final pendingResponse = responses[0];
      final completedResponse = responses[1];

      // Decode safely
      final pendingBody = utf8.decode(pendingResponse.bodyBytes);
      final completedBody = utf8.decode(completedResponse.bodyBytes);

      List<TaskItem> allTasks = [];

      // ✅ HANDLE PENDING
      if (pendingResponse.statusCode >= 200 &&
          pendingResponse.statusCode < 300) {
        final decoded = jsonDecode(pendingBody) as Map<String, dynamic>;
        final list = (decoded['data'] as List? ?? [])
            .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
            .toList();
        allTasks.addAll(list);
      } else if (pendingResponse.statusCode == 401) {
        return TasksResponse(success: false, tasks: [], error: 'UNAUTHORIZED');
      }

      // ✅ HANDLE COMPLETED
      if (completedResponse.statusCode >= 200 &&
          completedResponse.statusCode < 300) {
        final decoded = jsonDecode(completedBody) as Map<String, dynamic>;
        final list = (decoded['data'] as List? ?? [])
            .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
            .toList();
        allTasks.addAll(list);
      } else if (completedResponse.statusCode == 401) {
        return TasksResponse(success: false, tasks: [], error: 'UNAUTHORIZED');
      }

      // ✅ SORT: latest due date first
      allTasks.sort((a, b) => b.dueDate.compareTo(a.dueDate));

      return TasksResponse(success: true, tasks: allTasks);
    } catch (e) {
      return TasksResponse(success: false, tasks: [], error: e.toString());
    }
  }
}
